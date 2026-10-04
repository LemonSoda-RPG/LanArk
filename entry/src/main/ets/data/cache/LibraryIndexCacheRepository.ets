import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  ArchiveIndexPayload,
  ArchiveItem,
  CategoryItem,
  CategoryPayload
} from '../../domain/model/LanraragiModels';
import { localized } from '../../common/Localization';
import { AppLog } from '../log/AppLog';

const INDEX_FOLDER_NAME: string = 'lanark-library-index';

// Makes temporary write paths unique within the process; `Date.now()` alone
// collides when two writers target the same file in the same millisecond.
let temporaryWriteSequence: number = 0;

function temporaryWritePath(path: string): string {
  temporaryWriteSequence += 1;
  return `${path}.${Date.now()}-${temporaryWriteSequence}.tmp`;
}

interface LibraryIndexPayload {
  archives: Array<ArchiveIndexPayload>;
  categories: Array<CategoryPayload>;
  savedAt: number;
}

export class CachedLibraryIndex {
  readonly archives: Array<ArchiveItem>;
  readonly categories: Array<CategoryItem>;
  readonly savedAt: number;

  constructor(
    archives: Array<ArchiveItem>,
    categories: Array<CategoryItem>,
    savedAt: number
  ) {
    this.archives = archives;
    this.categories = categories;
    this.savedAt = savedAt;
  }
}

export class LibraryIndexCacheRepository {
  private readonly rootPath: string;
  private readonly filePath: string;

  constructor(context: common.UIAbilityContext, serverUrl: string) {
    this.rootPath = `${context.filesDir}/${INDEX_FOLDER_NAME}`;
    this.filePath = `${this.rootPath}/${this.serverNamespace(serverUrl)}.json`;
  }

  load(): CachedLibraryIndex | undefined {
    try {
      if (!fs.accessSync(this.filePath)) {
        return undefined;
      }
      const json: string = fs.readTextSync(this.filePath);
      const payload: LibraryIndexPayload = JSON.parse(json) as LibraryIndexPayload;
      if (!Array.isArray(payload.archives) || !Array.isArray(payload.categories)) {
        AppLog.warn('cache', 'index cache has an unexpected shape, ignoring it');
        return undefined;
      }
      AppLog.info('cache', `index cache loaded: ${payload.archives.length} archives`);
      return new CachedLibraryIndex(
        ArchiveItem.listFromPayloads(payload.archives),
        CategoryItem.listFromPayloads(payload.categories),
        payload.savedAt
      );
    } catch (error) {
      AppLog.warn('cache', `index cache unreadable: ${AppLog.describe(error)}`);
      return undefined;
    }
  }

  save(archives: Array<ArchiveItem>, categories: Array<CategoryItem>): void {
    let temporaryPath: string = '';
    let temporaryExists: boolean = false;
    try {
      if (!this.exists(this.rootPath)) {
        fs.mkdirSync(this.rootPath, true);
      }
      const payload: LibraryIndexPayload = {
        archives: archives.map((archive: ArchiveItem) => archive.toPayload()),
        categories: categories.map((category: CategoryItem) => category.toPayload()),
        savedAt: Date.now()
      };
      temporaryPath = temporaryWritePath(this.filePath);
      const file: fs.File = fs.openSync(
        temporaryPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC
      );
      temporaryExists = true;
      try {
        // Bytes rather than a string so the expected length is exact, and a
        // short write cannot be renamed into place: a truncated index would be
        // dropped by `load` on every start, leaving the library to re-download
        // the whole index until the next successful save.
        const encoded: Uint8Array =
          new util.TextEncoder().encodeInto(JSON.stringify(payload));
        const written: number = fs.writeSync(file.fd, encoded.buffer as ArrayBuffer);
        if (written !== encoded.byteLength) {
          throw new Error(localized('书库索引写入不完整', 'The library index was written incompletely'));
        }
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file);
      }
      // `rename` replaces the destination atomically. Unlinking first would open
      // a window where a crash leaves no index file at all.
      fs.renameSync(temporaryPath, this.filePath);
      temporaryExists = false;
      AppLog.info('cache', `index cache saved: ${archives.length} archives`);
    } catch (error) {
      AppLog.warn('cache', `index cache save failed: ${AppLog.describe(error)}`);
      // A stale cache must not prevent the library from loading from the server.
    } finally {
      if (temporaryExists && this.exists(temporaryPath)) {
        try {
          fs.unlinkSync(temporaryPath);
        } catch (error) {
          // Best-effort cleanup of a temporary cache file.
        }
      }
    }
  }

  private exists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (error) {
      return false;
    }
  }

  /**
   * Removes the cached index of one server, including any leftover temp files.
   *
   * Nothing used to remove these: the index of a server the user deleted stayed
   * on disk with its whole library (titles, tags, ids) in plain JSON, and the
   * temp files of an interrupted save were never reclaimed.
   */
  clearForServer(serverUrl: string): void {
    this.deleteFileIfExists(this.filePath);
    this.pruneTemporaryFiles(this.serverNamespace(serverUrl));
  }

  /** Removes every cached index and every leftover temp file. */
  clearAll(): void {
    let children: Array<string> = [];
    try {
      if (!this.exists(this.rootPath)) {
        return;
      }
      children = fs.listFileSync(this.rootPath);
    } catch (error) {
      return;
    }
    for (const name of children) {
      this.deleteFileIfExists(`${this.rootPath}/${name}`);
    }
  }

  /** Deletes `<namespace>.json.<timestamp>.tmp` files left by a failed save. */
  private pruneTemporaryFiles(namespace: string): void {
    let children: Array<string> = [];
    try {
      if (!this.exists(this.rootPath)) {
        return;
      }
      children = fs.listFileSync(this.rootPath);
    } catch (error) {
      return;
    }
    for (const name of children) {
      if (name.startsWith(`${namespace}.json.`) && name.endsWith('.tmp')) {
        this.deleteFileIfExists(`${this.rootPath}/${name}`);
      }
    }
  }

  private deleteFileIfExists(path: string): void {
    try {
      if (this.exists(path)) {
        fs.unlinkSync(path);
      }
    } catch (error) {
      // Best-effort: a cache file that cannot be removed is retried next time.
    }
  }

  private serverNamespace(serverUrl: string): string {
    let hash: number = 5381;
    for (let index: number = 0; index < serverUrl.length; index += 1) {
      hash = ((hash * 33) ^ serverUrl.charCodeAt(index)) >>> 0;
    }
    return `server-${hash.toString(16)}`;
  }
}
