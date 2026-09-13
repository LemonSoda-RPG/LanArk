import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  ArchiveIndexPayload,
  ArchiveItem,
  CategoryItem,
  CategoryPayload
} from '../../domain/model/LanraragiModels';

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
        return undefined;
      }
      return new CachedLibraryIndex(
        ArchiveItem.listFromPayloads(payload.archives),
        CategoryItem.listFromPayloads(payload.categories),
        payload.savedAt
      );
    } catch (error) {
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
        fs.writeSync(file.fd, JSON.stringify(payload));
      } finally {
        fs.closeSync(file);
      }
      // `rename` replaces the destination atomically. Unlinking first would open
      // a window where a crash leaves no index file at all.
      fs.renameSync(temporaryPath, this.filePath);
      temporaryExists = false;
    } catch (error) {
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

  private serverNamespace(serverUrl: string): string {
    let hash: number = 5381;
    for (let index: number = 0; index < serverUrl.length; index += 1) {
      hash = ((hash * 33) ^ serverUrl.charCodeAt(index)) >>> 0;
    }
    return `server-${hash.toString(16)}`;
  }
}
