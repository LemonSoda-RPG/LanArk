import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  ArchiveIndexPayload,
  ArchiveItem,
  ReaderPage
} from '../../domain/model/LanraragiModels';

const OFFLINE_ROOT_FOLDER_NAME: string = 'lanark-offline-archives';

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
      if (this.exists(this.pagePath(archiveId, page.pageNumber))) {
        count += 1;
      }
    });
    return count;
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
      const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const buffer: ArrayBuffer = new ArrayBuffer(size);
        return fs.readSync(file.fd, buffer) === size ? buffer : undefined;
      } finally {
        fs.closeSync(file);
      }
    } catch (error) {
      return undefined;
    }
  }

  private writeBinary(path: string, data: ArrayBuffer): void {
    this.ensureDirectory(path.substring(0, path.lastIndexOf('/')));
    let temporaryPath: string = `${path}.${Date.now()}.tmp`;
    let temporaryExists: boolean = false;
    try {
      const file: fs.File = fs.openSync(
        temporaryPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
      );
      temporaryExists = true;
      try {
        fs.writeSync(file.fd, data);
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
    let temporaryPath: string = `${path}.${Date.now()}.tmp`;
    let temporaryExists: boolean = false;
    try {
      const file: fs.File = fs.openSync(
        temporaryPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
      );
      temporaryExists = true;
      try {
        fs.writeSync(file.fd, value);
      } finally {
        fs.closeSync(file);
      }
      if (this.exists(path)) {
        fs.unlinkSync(path);
      }
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
    return result.length > 0 ? result : 'unknown';
  }

  private decodeArchiveDirectory(name: string): string {
    // Archive IDs are sanitized when stored. LANraragi IDs normally use the
    // same safe character set; the manifest remains the source of truth.
    return name;
  }
}
