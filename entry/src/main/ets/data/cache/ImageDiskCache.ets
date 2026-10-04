import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { localized } from '../../common/Localization';

const COVER_CACHE_FOLDER_NAME: string = 'lanark-cover-cache-v2';
const LEGACY_COVER_CACHE_FOLDER_NAME: string = 'lanark-image-cache';
const READER_CACHE_FOLDER_NAME: string = 'lanark-reader-cache';
// Separates an archive id from its reading session in a reader-cache folder
// name, as in `<archiveId>-s<token>`. The suffix is what lets a cleanup tell a
// folder written by a later session from the one it set out to delete.
const SESSION_SUFFIX_MARKER: string = '-s';

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

// Makes temporary write paths unique within the process; `Date.now()` alone
// collides when two writers target the same cover or page in the same
// millisecond, and the second open truncates the first writer's file.
let temporaryWriteSequence: number = 0;

function temporaryWritePath(path: string): string {
  temporaryWriteSequence += 1;
  return `${path}.${Date.now()}-${temporaryWriteSequence}.tmp`;
}

export class ImageCacheStats {
  readonly bytes: number;
  readonly fileCount: number;

  constructor(bytes: number = 0, fileCount: number = 0) {
    this.bytes = bytes;
    this.fileCount = fileCount;
  }
}

export class ImageDiskCache {
  /** AppStorage key holding the identifier of the current reading session. */
  private static readonly SESSION_TOKEN_KEY: string = 'lanarkReaderCacheSession';
  // Makes the per-session folder suffix unique when two sessions are started
  // within the same millisecond.
  private static sessionSequence: number = 0;
  private readonly filesDir: string;
  private readonly cacheDir: string;
  private readonly coverRootPath: string;
  private readonly legacyCoverRootPath: string;
  private readonly readerRootPath: string;
  private readonly coverServerPath: string;
  private readonly readerServerPath: string;

  constructor(context: common.UIAbilityContext, serverUrl: string = '') {
    this.filesDir = context.filesDir;
    this.cacheDir = context.cacheDir;
    this.coverRootPath = `${this.filesDir}/${COVER_CACHE_FOLDER_NAME}`;
    this.legacyCoverRootPath = `${this.filesDir}/${LEGACY_COVER_CACHE_FOLDER_NAME}`;
    this.readerRootPath = `${this.cacheDir}/${READER_CACHE_FOLDER_NAME}`;
    const namespace: string = this.serverNamespace(serverUrl);
    this.coverServerPath = `${this.coverRootPath}/${namespace}`;
    this.readerServerPath = `${this.readerRootPath}/${namespace}`;
    this.purgeLegacyCoverCache();
  }

  readCover(archiveId: string): ArrayBuffer | undefined {
    return this.readFile(this.coverPath(archiveId));
  }

  async writeCover(archiveId: string, pixelMap: image.PixelMap): Promise<void> {
    const packer: image.ImagePacker = image.createImagePacker();
    try {
      const packed: ArrayBuffer = await packer.packToData(pixelMap, {
        format: 'image/jpeg',
        quality: 72
      });
      this.writeFileIfMissing(this.coverPath(archiveId), packed);
    } catch (error) {
      // Cache encoding failures must not interrupt browsing.
    } finally {
      await packer.release();
    }
  }

  readPage(archiveId: string, pageNumber: number): ArrayBuffer | undefined {
    return this.readFile(this.pagePath(archiveId, pageNumber));
  }

  writePage(archiveId: string, pageNumber: number, data: ArrayBuffer): void {
    this.writeFileIfMissing(this.pagePath(archiveId, pageNumber), data);
  }

  /**
   * Sums the cache contents without blocking the UI thread.
   *
   * The synchronous walk used `listFileSync` and `statSync`, one call per file,
   * so opening the settings page stalled once the cover cache was large.
   */
  async statsAsync(): Promise<ImageCacheStats> {
    const coverStats: ImageCacheStats = await this.collectStatsAsync(this.coverRootPath);
    const readerStats: ImageCacheStats = await this.collectStatsAsync(this.readerRootPath);
    return new ImageCacheStats(
      coverStats.bytes + readerStats.bytes,
      coverStats.fileCount + readerStats.fileCount
    );
  }

  clearAll(): void {
    this.removeValidatedRoot(
      this.coverRootPath,
      `${this.filesDir}/${COVER_CACHE_FOLDER_NAME}`,
      this.filesDir
    );
    this.removeValidatedRoot(
      this.readerRootPath,
      `${this.cacheDir}/${READER_CACHE_FOLDER_NAME}`,
      this.cacheDir
    );
    this.removeValidatedRoot(
      this.legacyCoverRootPath,
      `${this.filesDir}/${LEGACY_COVER_CACHE_FOLDER_NAME}`,
      this.filesDir
    );
  }

  /**
   * Empties every cache this class owns, off the UI thread.
   *
   * The synchronous variant walks the whole tree with `listFileSync`,
   * `statSync` and `unlinkSync`, one call per file: on a library of tens of
   * thousands of covers that freezes the settings page for seconds. Stats and
   * per-document cleanup were already moved off the frame; this is the last
   * caller of the synchronous walk.
   */
  async clearAllAsync(): Promise<void> {
    await this.removeRootAsync(this.coverRootPath);
    await this.removeRootAsync(this.readerRootPath);
    await this.removeRootAsync(this.legacyCoverRootPath);
  }

  private async removeRootAsync(rootPath: string): Promise<void> {
    try {
      if (!(await fs.access(rootPath))) {
        return;
      }
      await this.removeDirectoryContentsAsync(rootPath, 0, new Map<string, number>());
      await this.removeEmptyDirectoryAsync(rootPath);
    } catch (error) {
      // A cache that cannot be emptied only costs disk space until it is fixed.
    }
  }

  private async removeEmptyDirectoryAsync(path: string): Promise<void> {
    try {
      await fs.rmdir(path);
    } catch (error) {
      // A directory that still holds files stays; the next clear retries it.
    }
  }

  clearArchivePages(archiveId: string): void {
    const archivePath: string = this.readerArchivePath(archiveId);
    if (this.exists(archivePath)) {
      this.removeDirectoryContents(archivePath);
      this.removeDirectory(archivePath);
    }
  }

  /**
   * Drops the reader cache of one archive off the UI thread.
   *
   * Deleting a document is one `stat` plus one `unlink` per cached page, which
   * the synchronous variant runs on the UI thread: closing a long document used
   * to spend that time in the frame that returns to the library. The reader
   * cache only exists so a page is not downloaded twice while reading, so
   * losing this cleanup on error is harmless.
   *
   * This runs while the user is already back in the library, so the same
   * archive can be opened again before the walk finishes and start writing to
   * the very directory being emptied. Only files that existed when the walk
   * started are deleted, which leaves those fresh pages alone.
   */
  async clearArchivePagesAsync(archiveId: string): Promise<void> {
    const archivePath: string = this.readerArchivePath(archiveId);
    if (archivePath.length === 0) {
      return;
    }
    try {
      if (!(await fs.access(archivePath))) {
        return;
      }
      // Only files that predate this walk go: the same archive opened again
      // while the walk runs writes pages this must not touch.
      await this.removeDirectoryContentsAsync(
        archivePath,
        Date.now(),
        new Map<string, number>()
      );
      await this.removeEmptyDirectoryAsync(archivePath);
    } catch (error) {
      // The pages stay cached, which only costs disk space the system reclaims.
    }
  }

  /**
   * Empties the whole reader cache while nothing can be reading.
   *
   * The reader drops its own cache when a document is closed, so this only
   * covers what that signal missed: a document left open by a process that was
   * killed, and the caches kept by builds that did not clean up at all.
   *
   * Passed `0` as the cutoff this removes everything, which is what a start-up
   * sweep wants — but the walk is not instantaneous, so a folder written by the
   * session that starts meanwhile must survive it. `newSessionToken` gives that
   * session a folder of its own, and `isStaleFile` also refuses anything written
   * after the cutoff, so neither route can delete a page being read.
   */
  async clearReaderRootAsync(): Promise<void> {
    try {
      if (!(await fs.access(this.readerRootPath))) {
        return;
      }
      await this.removeDirectoryContentsAsync(
        this.readerRootPath,
        0,
        new Map<string, number>()
      );
      await this.removeEmptyDirectoryAsync(this.readerRootPath);
    } catch (error) {
      // Stale pages cost disk space only; the next start tries again.
    }
  }

  /** Validated reader-cache directory of one archive, or '' if it is not one. */
  private readerArchivePath(archiveId: string): string {
    if (archiveId.length === 0) {
      return '';
    }
    const archivePath: string =
      `${this.readerServerPath}/${this.safePathPart(archiveId)}${this.readerSessionSuffix()}`;
    // `readerRootPath` is derived from `cacheDir` and a constant folder name, so
    // this can only fail if that construction changes. Deleting a directory is
    // not something to get wrong quietly.
    if (!archivePath.startsWith(`${this.readerRootPath}/`) ||
      archivePath.length <= this.readerRootPath.length + 1) {
      throw new Error(localized('阅读缓存目录校验失败', 'Reading cache directory validation failed'));
    }
    return archivePath;
  }

  /**
   * Creates the identifier of one reading session.
   *
   * `Index` calls this when the library page starts, so the identifier changes
   * once per cold start. A reader always writes into its own
   * `server-<hash>/<archiveId>-s<identifier>/` folder, which is what keeps a
   * cleanup that is still running from touching a document opened afterwards.
   */
  static newSessionToken(): string {
    return `${Date.now()}-${ImageDiskCache.sessionSequence++}`;
  }

  /**
   * Identifies this process' reading session.
   *
   * Falling back to a fixed value only costs cache reuse: the mtime guard in
   * `removeDirectoryContentsAsync` still stops a cleanup from eating pages
   * written afterwards.
   */
  private readerSessionSuffix(): string {
    const token: string | undefined =
      AppStorage.get<string>(ImageDiskCache.SESSION_TOKEN_KEY);
    return token === undefined || token.length === 0 ?
      '' : `${SESSION_SUFFIX_MARKER}${this.safePathPart(token)}`;
  }

  clearArchiveCover(archiveId: string): void {
    const path: string = this.coverPath(archiveId);
    if (!path.startsWith(`${this.coverRootPath}/`)) {
      throw new Error(localized('封面缓存路径校验失败', 'Cover cache path validation failed'));
    }
    if (this.exists(path)) {
      this.deleteFileIfExists(path);
    }
  }

  private coverPath(archiveId: string): string {
    return `${this.coverServerPath}/covers/${this.safePathPart(archiveId)}.image`;
  }

  private pagePath(archiveId: string, pageNumber: number): string {
    // Must stay in step with `readerArchivePath`: that is the directory this
    // file lives in, and it is the directory a cleanup deletes.
    return `${this.readerArchivePath(archiveId)}/${pageNumber}.image`;
  }

  private readFile(path: string): ArrayBuffer | undefined {
    try {
      if (!fs.accessSync(path)) {
        return undefined;
      }
      const size: number = fs.statSync(path).size;
      if (size <= 0 || size > MAX_CACHED_FILE_BYTES) {
        return undefined;
      }
      const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const buffer: ArrayBuffer = new ArrayBuffer(size);
        // `readSync` is not required to fill the buffer in a single call. A
        // short read used to be reported as a cache miss, which made an
        // existing cached page look like it had never been written.
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

  private writeFileIfMissing(path: string, data: ArrayBuffer): void {
    if (data.byteLength <= 0 || this.exists(path)) {
      return;
    }
    const parentPath: string = path.substring(0, path.lastIndexOf('/'));
    this.ensureDirectory(parentPath);
    const temporaryPath: string = temporaryWritePath(path);
    let temporaryExists: boolean = false;
    try {
      const file: fs.File = fs.openSync(
        temporaryPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
      );
      temporaryExists = true;
      try {
        const bytesWritten: number = fs.writeSync(file.fd, data);
        if (bytesWritten !== data.byteLength) {
          throw new Error(localized('图片缓存写入不完整', 'Image cache write was incomplete'));
        }
      } finally {
        fs.closeSync(file);
      }
      if (this.exists(path)) {
        this.deleteFileIfExists(temporaryPath);
        temporaryExists = false;
        return;
      }
      fs.renameSync(temporaryPath, path);
      temporaryExists = false;
    } catch (error) {
      if (temporaryExists) {
        this.deleteFileIfExists(temporaryPath);
      }
      // Cache failures must not interrupt browsing or reading.
    }
  }

  private async collectStatsAsync(path: string): Promise<ImageCacheStats> {
    let totalBytes: number = 0;
    let totalFiles: number = 0;
    try {
      const children: Array<string> = await fs.listFile(path);
      for (const name of children) {
        const childPath: string = `${path}/${name}`;
        const stat: fs.Stat = await fs.stat(childPath);
        if (stat.isDirectory()) {
          const childStats: ImageCacheStats = await this.collectStatsAsync(childPath);
          totalBytes += childStats.bytes;
          totalFiles += childStats.fileCount;
        } else {
          totalBytes += stat.size;
          totalFiles += 1;
        }
      }
    } catch (error) {
      // A missing root simply contributes nothing.
    }
    return new ImageCacheStats(totalBytes, totalFiles);
  }

  private removeDirectoryContents(path: string): void {
    try {
      const children: Array<string> = fs.listFileSync(path);
      children.forEach((name: string) => {
        const childPath: string = `${path}/${name}`;
        const stat: fs.Stat = fs.statSync(childPath);
        if (stat.isDirectory()) {
          this.removeDirectoryContents(childPath);
          this.removeDirectory(childPath);
        } else {
          this.deleteFileIfExists(childPath);
        }
      });
    } catch (error) {
      // Cache cleanup is best effort.
    }
  }

  /**
   * Same as `removeDirectoryContents`, awaited instead of blocking the caller.
   *
   * `startedAtMs` is the wall-clock millisecond when the deletion started, and
   * `0` means "delete everything". Files written during the walk belong to a
   * reading session that began while it ran — the same archive reopened right
   * after it was closed — so they are left alone by `isStaleFile`. `sessions`
   * carries the session number each archive folder was created with, so a
   * reopened archive is recognised even when the filesystem clock is too coarse
   * to separate the two.
   */
  private async removeDirectoryContentsAsync(
    path: string,
    startedAtMs: number,
    sessions: Map<string, number>
  ): Promise<void> {
    let children: Array<string> = [];
    try {
      children = await fs.listFile(path);
    } catch (error) {
      // An unreadable directory keeps whatever it still contains.
      return;
    }
    for (const name of children) {
      const childPath: string = `${path}/${name}`;
      try {
        const stat: fs.Stat = await fs.stat(childPath);
        if (stat.isDirectory()) {
          if (this.isNewerSessionFolder(name, sessions)) {
            // An archive folder of a later session than this walk belongs to;
            // its pages are in use right now.
            continue;
          }
          await this.removeDirectoryContentsAsync(childPath, startedAtMs, sessions);
          try {
            await fs.rmdir(childPath);
          } catch (error) {
            // A directory that cannot be removed leaves its files cached.
          }
        } else if (startedAtMs === 0 || this.isStaleFile(stat, startedAtMs)) {
          await fs.unlink(childPath);
        }
      } catch (error) {
        // One unreadable entry must not stop the rest of the archive.
      }
    }
  }

  /**
   * True when the file predates the deletion that is asking about it.
   *
   * `fs.Stat.mtime` is in seconds while `Date.now()` is in milliseconds, so the
   * comparison has to be made in one unit; `mtimeNs` is used when the platform
   * provides it, which also survives two writes inside the same second.
   */
  private isStaleFile(stat: fs.Stat, startedAtMs: number): boolean {
    const modifiedNs: bigint | undefined = stat.mtimeNs;
    if (modifiedNs !== undefined) {
      return modifiedNs < BigInt(startedAtMs) * BigInt(1_000_000);
    }
    // Seconds to milliseconds: a file modified in the same second as the cutoff
    // counts as stale, which deletes at most one extra page of a fresh session.
    return stat.mtime * 1000 < startedAtMs;
  }

  /**
   * Records the session number of archive folders as they are walked, and says
   * whether one belongs to a session newer than this walk's.
   *
   * A folder is `<server>/<archiveId>-s<session>`; the same archive opened again
   * during the walk gets a new number. Folders written by builds without a
   * session suffix are recorded on first sight, so they are treated as the
   * walk's own and cleaned normally.
   */
  private isNewerSessionFolder(name: string, sessions: Map<string, number>): boolean {
    const marker: number = name.lastIndexOf(SESSION_SUFFIX_MARKER);
    if (marker < 0) {
      return false;
    }
    const suffix: string = name.substring(marker + SESSION_SUFFIX_MARKER.length);
    if (suffix.length === 0) {
      return false;
    }
    const sessionNumber: number = Number.parseInt(suffix.split('-')[0], 10);
    if (Number.isNaN(sessionNumber)) {
      return false;
    }
    const seen: number | undefined = sessions.get(name);
    if (seen === undefined) {
      sessions.set(name, sessionNumber);
      return false;
    }
    return sessionNumber > seen;
  }

  private removeValidatedRoot(path: string, expectedPath: string, parentPath: string): void {
    if (path !== expectedPath || !path.startsWith(`${parentPath}/`)) {
      throw new Error(localized('缓存目录校验失败', 'Cache directory validation failed'));
    }
    if (this.exists(path)) {
      this.removeDirectoryContents(path);
      this.removeDirectory(path);
    }
  }

  private exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (error) {
      return false;
    }
  }

  private ensureDirectory(path: string): void {
    try {
      if (!this.exists(path)) {
        fs.mkdirSync(path, true);
      }
    } catch (error) {
      // The caller will handle a subsequent file-open failure.
    }
  }

  private removeDirectory(path: string): void {
    try {
      if (this.exists(path)) {
        fs.rmdirSync(path);
      }
    } catch (error) {
      // Cache cleanup is best effort.
    }
  }

  private deleteFileIfExists(path: string): void {
    try {
      if (this.exists(path)) {
        fs.unlinkSync(path);
      }
    } catch (error) {
      // Cache cleanup is best effort.
    }
  }

  private purgeLegacyCoverCache(): void {
    try {
      this.removeValidatedRoot(
        this.legacyCoverRootPath,
        `${this.filesDir}/${LEGACY_COVER_CACHE_FOLDER_NAME}`,
        this.filesDir
      );
    } catch (error) {
      // A concurrent cover component may already be removing the legacy cache.
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
      // Nothing was substituted, so the identifier is already unambiguous.
      return result.length > 0 ? result : 'unknown';
    }
    // The substitution is lossy (`a/b`, `a.b` and `a_b` all become `a_b`), so a
    // hash of the original keeps distinct archives in distinct directories
    // without moving the paths of ordinary identifiers.
    return `${result.length > 0 ? result : 'unknown'}-${pathHash(value)}`;
  }
}
