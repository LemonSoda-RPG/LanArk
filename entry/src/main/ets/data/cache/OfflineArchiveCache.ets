import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  ArchiveIndexPayload,
  ArchiveItem,
  ReaderPage
} from '../../domain/model/LanraragiModels';
import { localized } from '../../common/Localization';

const OFFLINE_ROOT_FOLDER_NAME: string = 'lanark-offline-archives';

// Makes temporary write paths unique within the process. `Date.now()` alone
// collides when two writers target the same destination in the same
// millisecond, and the second open truncates the first writer's file.
let temporaryWriteSequence: number = 0;

function temporaryWritePath(path: string): string {
  temporaryWriteSequence += 1;
  return `${path}.${Date.now()}-${temporaryWriteSequence}.tmp`;
}

// Guards against allocating from a corrupt or absurd stat result.
const MAX_CACHED_FILE_BYTES: number = 128 * 1024 * 1024;

/** djb2 hash of the raw value, used to disambiguate sanitised path parts. */
function pathHash(value: string): string {
  let hash: number = 5381;
  for (let index: number = 0; index < value.length; index += 1) {
    hash = ((hash * 33) ^ value.charCodeAt(index)) >>> 0;
  }
  return hash.toString(16);
}

interface OfflineManifestPayload {
  archive: ArchiveIndexPayload;
  pages: Array<ReaderPagePayload>;
  savedAt: number;
}

interface ReaderPagePayload {
  path: string;
  pageNumber: number;
}

export class OfflineArchiveRecord {
  readonly archive: ArchiveItem;
  readonly pages: Array<ReaderPage>;
  readonly savedAt: number;

  constructor(archive: ArchiveItem, pages: Array<ReaderPage>, savedAt: number) {
    this.archive = archive;
    this.pages = pages;
    this.savedAt = savedAt;
  }
}

/**
 * Persistent page storage for archives explicitly downloaded by the user.
 * This is deliberately separate from ImageDiskCache's temporary reader cache.
 */
export class OfflineArchiveCache {
  private readonly rootPath: string;
  private readonly serverPath: string;

  constructor(context: common.UIAbilityContext, serverUrl: string) {
    this.rootPath = `${context.filesDir}/${OFFLINE_ROOT_FOLDER_NAME}`;
    this.serverPath = `${this.rootPath}/${this.serverNamespace(serverUrl)}`;
  }

  readPage(archiveId: string, pageNumber: number): ArrayBuffer | undefined {
    return this.readFile(this.pagePath(archiveId, pageNumber));
  }

  writePage(archiveId: string, pageNumber: number, data: ArrayBuffer): void {
    if (data.byteLength <= 0) {
      return;
    }
    this.writeBinary(this.pagePath(archiveId, pageNumber), data);
  }

  saveManifest(archive: ArchiveItem, pages: Array<ReaderPage>): void {
    const payload: OfflineManifestPayload = {
      archive: archive.toPayload(),
      pages: pages.map((page: ReaderPage): ReaderPagePayload => {
        return { path: page.path, pageNumber: page.pageNumber };
      }),
      savedAt: Date.now()
    };
    this.writeText(this.manifestPath(archive.id), JSON.stringify(payload));
  }

  readRecord(archiveId: string): OfflineArchiveRecord | undefined {
    try {
      const path: string = this.manifestPath(archiveId);
      if (!this.exists(path)) {
        return undefined;
      }
      const payload: OfflineManifestPayload = JSON.parse(fs.readTextSync(path)) as OfflineManifestPayload;
      if (payload.archive === undefined || !Array.isArray(payload.pages)) {
        return undefined;
      }
      const pages: Array<ReaderPage> = payload.pages.map((page: ReaderPagePayload) => {
        return new ReaderPage(page.path, page.pageNumber);
      });
      if (pages.length === 0) {
        return undefined;
      }
      return new OfflineArchiveRecord(
        new ArchiveItem(payload.archive),
        pages,
        payload.savedAt ?? 0
      );
    } catch (error) {
      return undefined;
    }
  }

  listRecords(): Array<OfflineArchiveRecord> {
    const records: Array<OfflineArchiveRecord> = [];
    try {
      if (!this.exists(this.serverPath)) {
        return records;
      }
      fs.listFileSync(this.serverPath).forEach((name: string) => {
        const archiveId: string = this.decodeArchiveDirectory(name);
        const record: OfflineArchiveRecord | undefined = this.readRecord(archiveId);
        if (record !== undefined) {
          records.push(record);
        }
      });
    } catch (error) {
      // A partially removed offline item should not prevent the rest loading.
    }
    records.sort((left: OfflineArchiveRecord, right: OfflineArchiveRecord) => {
      return right.savedAt - left.savedAt;
    });
    return records;
  }

  countDownloadedPages(archiveId: string, pages: Array<ReaderPage>): number {
    let count: number = 0;
    pages.forEach((page: ReaderPage) => {
      if (this.isReadablePage(this.pagePath(archiveId, page.pageNumber))) {
        count += 1;
      }
    });
    return count;
  }

  /**
   * Whether a page file is one this app can actually read.
   *
   * Judging by existence alone marked an archive complete while a page the
   * reader refuses (empty, or past the size ceiling) could never be displayed.
   */
  private isReadablePage(path: string): boolean {
    try {
      if (!this.exists(path)) {
        return false;
      }
      const size: number = fs.statSync(path).size;
      return size > 0 && size <= MAX_CACHED_FILE_BYTES;
    } catch (error) {
      return false;
    }
  }

  isDownloaded(archiveId: string): boolean {
    const record: OfflineArchiveRecord | undefined = this.readRecord(archiveId);
    if (record === undefined) {
      return false;
    }
    return this.countDownloadedPages(archiveId, record.pages) === record.pages.length;
  }

  clearArchive(archiveId: string): void {
    const path: string = this.archivePath(archiveId);
    if (!path.startsWith(`${this.serverPath}/`)) {
      return;
    }
    this.removeDirectoryContents(path);
    if (this.exists(path)) {
      try {
        fs.rmdirSync(path);
      } catch (error) {
        // Best-effort cleanup.
      }
    }
  }

  /**
   * Removes archive folders that no longer have a usable manifest.
   *
   * A download writes its manifest last, so an interrupted or failed one leaves
   * pages on disk that no listing shows — `listRecords` needs a manifest to
   * return a record. Without this sweep those pages are invisible and cannot be
   * deleted from the UI, and they are never reclaimed.
   */
  pruneOrphans(): void {
    let children: Array<string> = [];
    try {
      if (!this.exists(this.serverPath)) {
        return;
      }
      children = fs.listFileSync(this.serverPath);
    } catch (error) {
      return;
    }
    for (const name of children) {
      const archivePath: string = `${this.serverPath}/${name}`;
      try {
        if (!fs.statSync(archivePath).isDirectory()) {
          continue;
        }
        if (this.readRecord(name) !== undefined) {
          continue;
        }
        this.removeDirectoryContents(archivePath);
        fs.rmdirSync(archivePath);
      } catch (error) {
        // One stubborn folder must not stop the rest of the sweep.
      }
    }
  }

  /** Removes every offline copy kept for one server URL. */
  clearServer(serverUrl: string): void {
    const path: string = `${this.rootPath}/${this.serverNamespace(serverUrl)}`;
    this.removeValidated(path, `${this.rootPath}/`);
  }

  /** Removes every offline copy, for every server. */
  clearAll(): void {
    this.removeValidated(this.rootPath, `${this.rootPath}`);
  }

  /** Deletes a directory tree, refusing anything outside `allowedPrefix`. */
  private removeValidated(path: string, allowedPrefix: string): void {
    if (!path.startsWith(allowedPrefix)) {
      return;
    }
    this.removeDirectoryContents(path);
    if (this.exists(path)) {
      try {
        fs.rmdirSync(path);
      } catch (error) {
        // A directory that still holds files stays for the next attempt.
      }
    }
  }

  private archivePath(archiveId: string): string {
    return `${this.serverPath}/${this.safePathPart(archiveId)}`;
  }

  private manifestPath(archiveId: string): string {
    return `${this.archivePath(archiveId)}/manifest.json`;
  }

  private pagePath(archiveId: string, pageNumber: number): string {
    return `${this.archivePath(archiveId)}/${Math.max(pageNumber, 1)}.image`;
  }

  private readFile(path: string): ArrayBuffer | undefined {
    try {
      if (!this.exists(path)) {
        return undefined;
      }
      const size: number = fs.statSync(path).size;
      if (size <= 0) {
        return undefined;
      }
      if (size > MAX_CACHED_FILE_BYTES) {
        // Larger than anything this app will read. Treated as missing *and*
        // discarded, because the download path skips pages that "exist": leaving
        // it would make the archive look complete while this page can never be
        // read or re-fetched.
        this.deleteFileIfExists(path);
        return undefined;
      }
      const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const buffer: ArrayBuffer = new ArrayBuffer(size);
        // `readSync` is not required to fill the buffer in a single call. A
        // short read used to be reported as a missing page, which told the user
        // to re-download an archive that was in fact fully on disk.
        let offset: number = 0;
        while (offset < size) {
          const read: number = fs.readSync(file.fd, buffer, {
            offset: offset,
            length: size - offset
          });
          if (read <= 0) {
            return undefined;
          }
          offset += read;
        }
        return buffer;
      } finally {
        fs.closeSync(file);
      }
    } catch (error) {
      return undefined;
    }
  }

  private writeBinary(path: string, data: ArrayBuffer): void {
    this.ensureDirectory(path.substring(0, path.lastIndexOf('/')));
    let temporaryPath: string = temporaryWritePath(path);
    let temporaryExists: boolean = false;
    try {
      const file: fs.File = fs.openSync(
        temporaryPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
      );
      temporaryExists = true;
      try {
        const written: number = fs.writeSync(file.fd, data);
        // A short write (disk full, for instance) must not be renamed over the
        // real page: the archive would claim to be downloaded while the page can
        // never be decoded, and nothing would ever re-fetch it.
        if (written !== data.byteLength) {
          throw new Error(localized('离线页面写入不完整', 'The offline page was written incompletely'));
        }
      } finally {
        fs.closeSync(file);
      }
      if (this.exists(path)) {
        fs.unlinkSync(temporaryPath);
      } else {
        fs.renameSync(temporaryPath, path);
      }
      temporaryExists = false;
    } catch (error) {
      if (temporaryExists && this.exists(temporaryPath)) {
        try {
          fs.unlinkSync(temporaryPath);
        } catch (cleanupError) {
          // Best-effort cleanup.
        }
      }
    }
  }

  private writeText(path: string, value: string): void {
    this.ensureDirectory(path.substring(0, path.lastIndexOf('/')));
    let temporaryPath: string = temporaryWritePath(path);
    let temporaryExists: boolean = false;
    try {
      const file: fs.File = fs.openSync(
        temporaryPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
      );
      temporaryExists = true;
      try {
        // Written as bytes so the expected length is exact: an incomplete
        // manifest would either hide the archive or claim pages that are not
        // there.
        const encoded: Uint8Array = new util.TextEncoder().encodeInto(value);
        const written: number = fs.writeSync(file.fd, encoded.buffer as ArrayBuffer);
        if (written !== encoded.byteLength) {
          throw new Error(localized('离线清单写入不完整', 'The offline manifest was written incompletely'));
        }
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file);
      }
      // `rename` replaces the destination atomically. Unlinking first would open
      // a window where a crash destroys the manifest and hides an archive whose
      // pages are all still on disk.
      fs.renameSync(temporaryPath, path);
      temporaryExists = false;
    } catch (error) {
      if (temporaryExists && this.exists(temporaryPath)) {
        try {
          fs.unlinkSync(temporaryPath);
        } catch (cleanupError) {
          // Best-effort cleanup.
        }
      }
    }
  }

  private removeDirectoryContents(path: string): void {
    try {
      if (!this.exists(path)) {
        return;
      }
      fs.listFileSync(path).forEach((name: string) => {
        const childPath: string = `${path}/${name}`;
        if (fs.statSync(childPath).isDirectory()) {
          this.removeDirectoryContents(childPath);
          fs.rmdirSync(childPath);
        } else {
          fs.unlinkSync(childPath);
        }
      });
    } catch (error) {
      // Best-effort cleanup.
    }
  }

  private ensureDirectory(path: string): void {
    try {
      if (!this.exists(path)) {
        fs.mkdirSync(path, true);
      }
    } catch (error) {
      // The following file operation will fail harmlessly if creation failed.
    }
  }

  private exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (error) {
      return false;
    }
  }

  private deleteFileIfExists(path: string): void {
    try {
      if (this.exists(path)) {
        fs.unlinkSync(path);
      }
    } catch (error) {
      // Best-effort cleanup of a file that could not be used.
    }
  }

  private serverNamespace(serverUrl: string): string {
    let hash: number = 5381;
    for (let index: number = 0; index < serverUrl.length; index += 1) {
      hash = ((hash * 33) ^ serverUrl.charCodeAt(index)) >>> 0;
    }
    return `server-${hash.toString(16)}`;
  }

  private safePathPart(value: string): string {
    let result: string = '';
    for (let index: number = 0; index < value.length; index += 1) {
      const character: string = value.charAt(index);
      const code: number = value.charCodeAt(index);
      const isDigit: boolean = code >= 48 && code <= 57;
      const isUpper: boolean = code >= 65 && code <= 90;
      const isLower: boolean = code >= 97 && code <= 122;
      result += isDigit || isUpper || isLower || character === '-' || character === '_' ?
        character : '_';
    }
    if (result === value) {
      // Nothing was substituted, so the identifier is already unambiguous and
      // existing directories keep their path.
      return result.length > 0 ? result : 'unknown';
    }
    // The substitution is lossy (`a/b`, `a.b` and `a_b` all become `a_b`), so a
    // hash of the original keeps distinct archives in distinct directories.
    return `${result.length > 0 ? result : 'unknown'}-${pathHash(value)}`;
  }

  private decodeArchiveDirectory(name: string): string {
    // Archive IDs are sanitized when stored. LANraragi IDs normally use the
    // same safe character set; the manifest remains the source of truth.
    return name;
  }
}
