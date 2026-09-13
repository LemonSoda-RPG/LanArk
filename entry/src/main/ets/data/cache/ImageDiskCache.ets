import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { localized } from '../../common/Localization';

const COVER_CACHE_FOLDER_NAME: string = 'lanark-cover-cache-v2';
const LEGACY_COVER_CACHE_FOLDER_NAME: string = 'lanark-image-cache';
const READER_CACHE_FOLDER_NAME: string = 'lanark-reader-cache';

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

  clearArchivePages(archiveId: string): void {
    const archivePath: string =
      `${this.readerServerPath}/${this.safePathPart(archiveId)}`;
    if (!archivePath.startsWith(`${this.readerRootPath}/`)) {
      throw new Error(localized('阅读缓存目录校验失败', 'Reading cache directory validation failed'));
    }
    if (this.exists(archivePath)) {
      this.removeDirectoryContents(archivePath);
      this.removeDirectory(archivePath);
    }
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
    return `${this.readerServerPath}/${this.safePathPart(archiveId)}/${pageNumber}.image`;
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
