import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

const COVER_CACHE_FOLDER_NAME: string = 'lanark-cover-cache-v2';
const LEGACY_COVER_CACHE_FOLDER_NAME: string = 'lanark-image-cache';
const READER_CACHE_FOLDER_NAME: string = 'lanark-reader-cache';

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

  stats(): ImageCacheStats {
    let bytes: number = 0;
    let fileCount: number = 0;
    if (this.exists(this.coverRootPath)) {
      const coverStats: ImageCacheStats = this.collectStats(this.coverRootPath);
      bytes += coverStats.bytes;
      fileCount += coverStats.fileCount;
    }
    if (this.exists(this.readerRootPath)) {
      const readerStats: ImageCacheStats = this.collectStats(this.readerRootPath);
      bytes += readerStats.bytes;
      fileCount += readerStats.fileCount;
    }
    return new ImageCacheStats(bytes, fileCount);
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
      throw new Error('阅读缓存目录校验失败');
    }
    if (this.exists(archivePath)) {
      this.removeDirectoryContents(archivePath);
      this.removeDirectory(archivePath);
    }
  }

  clearArchiveCover(archiveId: string): void {
    const path: string = this.coverPath(archiveId);
    if (!path.startsWith(`${this.coverRootPath}/`)) {
      throw new Error('封面缓存路径校验失败');
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
      if (size <= 0) {
        return undefined;
      }
      const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const buffer: ArrayBuffer = new ArrayBuffer(size);
        const bytesRead: number = fs.readSync(file.fd, buffer);
        if (bytesRead !== size) {
          return undefined;
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
    const temporaryPath: string = `${path}.${Date.now()}.tmp`;
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
          throw new Error('图片缓存写入不完整');
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

  private collectStats(path: string): ImageCacheStats {
    try {
      let totalBytes: number = 0;
      let totalFiles: number = 0;
      const children: Array<string> = fs.listFileSync(path);
      children.forEach((name: string) => {
        const childPath: string = `${path}/${name}`;
        const stat: fs.Stat = fs.statSync(childPath);
        if (stat.isDirectory()) {
          const childStats: ImageCacheStats = this.collectStats(childPath);
          totalBytes += childStats.bytes;
          totalFiles += childStats.fileCount;
        } else {
          totalBytes += stat.size;
          totalFiles += 1;
        }
      });
      return new ImageCacheStats(totalBytes, totalFiles);
    } catch (error) {
      return new ImageCacheStats();
    }
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
      throw new Error('缓存目录校验失败');
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
    return result.length > 0 ? result : 'unknown';
  }
}
