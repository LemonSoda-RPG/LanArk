import { localized } from '../../common/Localization';

export interface ServerInfoPayload {
  archives_per_page: number;
  debug_mode: boolean;
  has_password: boolean;
  motd: string;
  name: string;
  nofun_mode: boolean;
  server_tracks_progress: boolean;
  version: string;
  version_name: string;
}

export class ServerInfo {
  readonly archivesPerPage: number;
  readonly debugMode: boolean;
  readonly hasPassword: boolean;
  readonly motd: string;
  readonly name: string;
  readonly nofunMode: boolean;
  readonly serverTracksProgress: boolean;
  readonly version: string;
  readonly versionName: string;

  constructor(payload: ServerInfoPayload) {
    this.archivesPerPage = payload.archives_per_page;
    this.debugMode = payload.debug_mode;
    this.hasPassword = payload.has_password;
    this.motd = payload.motd;
    this.name = payload.name;
    this.nofunMode = payload.nofun_mode;
    this.serverTracksProgress = payload.server_tracks_progress;
    this.version = payload.version;
    this.versionName = payload.version_name;
  }

  static fromJson(json: string): ServerInfo {
    const payload: ServerInfoPayload = JSON.parse(json) as ServerInfoPayload;
    if (payload.name === undefined || payload.version === undefined ||
      payload.archives_per_page === undefined) {
      throw new Error(localized('服务器信息格式不完整', 'The server information is incomplete'));
    }
    return new ServerInfo(payload);
  }
}

export class ServerConfig {
  readonly serverUrl: string;
  readonly apiKey: string;

  constructor(serverUrl: string = '', apiKey: string = '') {
    this.serverUrl = serverUrl;
    this.apiKey = apiKey;
  }
}

/** A saved LANraragi endpoint and its locally protected API key. */
export class ServerProfile {
  readonly id: string;
  readonly name: string;
  readonly serverUrl: string;
  readonly apiKey: string;

  constructor(id: string, serverUrl: string, apiKey: string = '', name: string = '') {
    this.id = id;
    this.serverUrl = serverUrl;
    this.apiKey = apiKey;
    this.name = name.length > 0 ? name : serverUrl;
  }

  toConfig(): ServerConfig {
    return new ServerConfig(this.serverUrl, this.apiKey);
  }
}

export interface ArchiveIndexPayload {
  arcid: string;
  extension: string;
  isnew: string | boolean | number;
  tags?: string;
  title: string;
  pagecount: number;
  progress: number;
  lastreadtime?: number;
  archive_count?: number;
}

@Observed
export class ArchiveItem {
  readonly id: string;
  readonly fileExtension: string;
  readonly isNew: boolean;
  readonly tags: string;
  readonly title: string;
  readonly pageCount: number;
  progress: number;
  // Epoch seconds of the last read, as reported by the server (the library index
  // already carries `lastreadtime`). Bumped locally while reading so the history
  // stays fresh until the next full index refresh.
  lastReadTime: number;
  readonly archiveCount: number;
  readonly dateAdded: number;
  // `tags` never changes after construction, so the parsed forms are built once.
  // Sorting by a tag and rendering `displayTags` used to re-split the tag string
  // on every comparison and on every row render.
  private tagIndexCache: Map<string, string> | undefined = undefined;
  private tagItemsCache: Array<string> | undefined = undefined;
  private displayTagsCache: string | undefined = undefined;
  private searchKeyCache: string | undefined = undefined;

  constructor(payload: ArchiveIndexPayload) {
    this.id = payload.arcid;
    this.fileExtension = payload.extension;
    this.isNew = payload.isnew === true || payload.isnew === 1 ||
      payload.isnew === '1' || payload.isnew === 'true';
    this.tags = payload.tags ?? '';
    this.title = payload.title;
    this.pageCount = payload.pagecount;
    this.progress = payload.progress;
    this.lastReadTime = payload.lastreadtime ?? 0;
    this.archiveCount = payload.archive_count ?? 0;
    this.dateAdded = this.extractNumericTag('date_added');
  }

  get progressText(): string {
    if (this.pageCount <= 0 || this.progress <= 0) {
      return localized('未读');
    }
    if (this.progress >= this.pageCount) {
      return localized('已读完');
    }
    return `${this.progress}/${this.pageCount}`;
  }

  get progressRatio(): number {
    if (this.pageCount <= 0 || this.progress <= 0) {
      return 0;
    }
    return Math.min(this.progress / this.pageCount, 1);
  }

  get readingState(): number {
    if (this.progress <= 0) {
      return 0;
    }
    if (this.pageCount > 0 && this.progress >= this.pageCount) {
      return 2;
    }
    return 1;
  }

  get displayAsNew(): boolean {
    return this.isNew && this.progress <= 0;
  }

  get displayTags(): string {
    if (this.displayTagsCache === undefined) {
      this.displayTagsCache = this.tagItems()
        .filter((tag: string) => !tag.toLowerCase().startsWith('date_added:'))
        .slice(0, 3)
        .join(' · ');
    }
    return this.displayTagsCache;
  }

  /** Parsed tags. The returned array is shared; callers must not mutate it. */
  tagItems(): Array<string> {
    if (this.tagItemsCache === undefined) {
      this.tagItemsCache = this.tags.length === 0 ? [] :
        this.tags.split(',')
          .map((tag: string) => tag.trim())
          .filter((tag: string) => tag.length > 0);
    }
    return this.tagItemsCache;
  }

  /** Namespace to value map, so a lookup never re-splits the tag string. */
  private tagIndex(): Map<string, string> {
    if (this.tagIndexCache === undefined) {
      const index: Map<string, string> = new Map<string, string>();
      const parts: Array<string> = this.tagItems();
      for (let position: number = 0; position < parts.length; position++) {
        const tag: string = parts[position];
        const separator: number = tag.indexOf(':');
        if (separator <= 0) {
          continue;
        }
        const namespace: string = tag.substring(0, separator).trim().toLowerCase();
        if (!index.has(namespace)) {
          index.set(namespace, tag.substring(separator + 1).trim());
        }
      }
      this.tagIndexCache = index;
    }
    return this.tagIndexCache;
  }

  tagValue(namespace: string): string {
    const value: string | undefined = this.tagIndex().get(namespace.toLowerCase());
    return value === undefined ? '' : value;
  }

  /** Lower-cased title and tags, built once for library search. */
  searchKey(): string {
    if (this.searchKeyCache === undefined) {
      this.searchKeyCache = `${this.title}\n${this.tags}`.toLowerCase();
    }
    return this.searchKeyCache;
  }

  private extractNumericTag(namespace: string): number {
    const value: string = this.tagValue(namespace);
    if (value.length === 0) {
      return 0;
    }
    const parsed: number = Number.parseInt(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  static listFromJson(json: string): Array<ArchiveItem> {
    const payloads: Array<ArchiveIndexPayload> =
      JSON.parse(json) as Array<ArchiveIndexPayload>;
    return ArchiveItem.listFromPayloads(payloads);
  }

  static listFromPayloads(payloads: Array<ArchiveIndexPayload>): Array<ArchiveItem> {
    return payloads.map((payload: ArchiveIndexPayload) => new ArchiveItem(payload));
  }

  toPayload(): ArchiveIndexPayload {
    return {
      arcid: this.id,
      extension: this.fileExtension,
      isnew: this.isNew,
      tags: this.tags,
      title: this.title,
      pagecount: this.pageCount,
      progress: this.progress,
      lastreadtime: this.lastReadTime,
      archive_count: this.archiveCount
    };
  }

  /** Records that the archive was just read, for the history ordering. */
  markReadAt(timestampSeconds: number): void {
    if (timestampSeconds > this.lastReadTime) {
      this.lastReadTime = timestampSeconds;
    }
  }

  withProgress(progress: number): ArchiveItem {
    const payload: ArchiveIndexPayload = this.toPayload();
    payload.progress = progress;
    return new ArchiveItem(payload);
  }

  setProgress(progress: number): void {
    this.progress = progress;
  }
}

export interface ArchiveSearchPayload {
  data: Array<ArchiveIndexPayload>;
  draw?: number;
  recordsFiltered: number;
  recordsTotal: number;
}

/**
 * A batch of library entries, plus the size of the whole result.
 *
 * `total` is what tells the caller whether another batch is worth asking for.
 * The server caps every page at its own `archives_per_page` setting and ignores
 * a larger request, so a batch arrives with whatever it decides to send.
 */
export class ArchiveIndexPageResult {
  readonly archives: Array<ArchiveItem>;
  readonly total: number;

  constructor(archives: Array<ArchiveItem>, total: number) {
    this.archives = archives;
    this.total = total;
  }
}

export interface CategoryPayload {
  archives?: Array<string>;
  id: string;
  last_used?: string;
  name: string;
  pinned: string | boolean | number;
  search?: string;
}

export class CategoryItem {
  readonly id: string;
  readonly name: string;
  readonly archiveIds: Array<string>;
  readonly search: string;
  readonly pinned: boolean;

  constructor(payload: CategoryPayload) {
    this.id = payload.id;
    this.name = payload.name;
    this.archiveIds = payload.archives ?? [];
    this.search = payload.search ?? '';
    this.pinned = payload.pinned === true || payload.pinned === 1 ||
      payload.pinned === '1' || payload.pinned === 'true';
  }

  static listFromJson(json: string): Array<CategoryItem> {
    const payloads: Array<CategoryPayload> =
      JSON.parse(json) as Array<CategoryPayload>;
    return CategoryItem.listFromPayloads(payloads);
  }

  static listFromPayloads(payloads: Array<CategoryPayload>): Array<CategoryItem> {
    return payloads.map((payload: CategoryPayload) => new CategoryItem(payload));
  }

  toPayload(): CategoryPayload {
    return {
      archives: this.archiveIds,
      id: this.id,
      name: this.name,
      pinned: this.pinned,
      search: this.search
    };
  }
}

/**
 * A tankoubon ID, as LANraragi reports it in search results.
 *
 * Tankoubons are database-only groupings of archives: they have no file of
 * their own, and every archive endpoint rejects their ID. The ones that apply
 * are under `/api/tankoubons`.
 */
export function isTankoubonId(id: string): boolean {
  return id.startsWith('TANK_');
}

/**
 * Short label used where a file extension is shown (cover placeholder, offline
 * list). A tankoubon has no real file, so ".TANK" would be a lie: show the
 * collection type instead.
 */
export function archiveTypeLabel(extension: string): string {
  return extension.toLowerCase() === '.tank' ?
    localized('单行本', 'Tankoubon') : extension.toUpperCase();
}

/** A tankoubon's own record, as returned by `/api/tankoubons/{id}/full`. */
export interface TankoubonPayload {
  id: string;
  name?: string;
  summary?: string;
  tags?: string;
  progress?: number;
  /** IDs of the archives in reading order; may itself contain tankoubons. */
  archives?: Array<string>;
  /** Metadata for the archives, in the same order as `archives`. */
  full_data?: Array<ArchiveIndexPayload>;
}

export interface TankoubonFullPayload {
  result?: TankoubonPayload;
  total?: number;
  filtered?: number;
}

export interface ArchivePagesPayload {
  pages: Array<string>;
  /**
   * Present when LANraragi has to extract the archive first: it answers with an
   * empty `pages` and a Minion job, and the caller is expected to come back.
   */
  job?: number;
}

/**
 * One archive inside a tankoubon, with its slice of the concatenated page list.
 *
 * `startPage` and `endPage` are one-based global pages, which is what the
 * reader and the server-side tank progress use.
 */
export class TankChapter {
  readonly archiveId: string;
  readonly title: string;
  readonly pageCount: number;
  readonly startPage: number;
  readonly endPage: number;

  constructor(archiveId: string, title: string, pageCount: number, startPage: number) {
    this.archiveId = archiveId;
    this.title = title;
    this.pageCount = pageCount;
    this.startPage = startPage;
    this.endPage = startPage + Math.max(pageCount, 0) - 1;
  }
}

/** Result of asking for an archive's page list. */
export class ArchivePagesResult {
  readonly pages: Array<ReaderPage>;
  /** Minion job extracting the archive, or 0 when there is none. */
  readonly jobId: number;
  /** Sub-archives when the ID was a tankoubon, in reading order; empty otherwise. */
  readonly chapters: Array<TankChapter>;

  constructor(pages: Array<ReaderPage>, jobId: number = 0,
    chapters: Array<TankChapter> = []) {
    this.pages = pages;
    this.jobId = jobId;
    this.chapters = chapters;
  }

  /** True when the server is still preparing this archive. */
  get isPreparing(): boolean {
    return this.pages.length === 0 && this.jobId > 0;
  }
}

export class ReaderPage {
  readonly path: string;
  readonly pageNumber: number;

  constructor(path: string, pageNumber: number) {
    this.path = path;
    // LANraragi progress and page APIs are one-based. ArkUI indices remain zero-based.
    this.pageNumber = pageNumber;
  }
}

export class ReaderRouteParams {
  readonly archive: ArchiveItem;
  readonly fromStart: boolean;
  readonly offline: boolean;
  readonly offlineServerUrl: string;
  /** One-based page to open at; 0 keeps the saved-progress behaviour. */
  readonly startPageNumber: number;

  constructor(
    archive: ArchiveItem,
    fromStart: boolean,
    offline: boolean = false,
    offlineServerUrl: string = '',
    startPageNumber: number = 0
  ) {
    this.archive = archive;
    this.fromStart = fromStart;
    this.offline = offline;
    this.offlineServerUrl = offlineServerUrl;
    this.startPageNumber = startPageNumber;
  }
}

/** Parameters used when opening archive actions from an online or offline reader. */
export class ArchiveInfoRouteParams {
  readonly archive: ArchiveItem;
  readonly offline: boolean;
  readonly offlineServerUrl: string;
  /**
   * Optional jump target handler. The reader passes one so a tankoubon chapter
   * tapped in the info page moves the reader underneath instead of stacking a
   * second reader on top of it.
   */
  readonly onOpenChapter?: (startPage: number) => void;

  constructor(
    archive: ArchiveItem,
    offline: boolean = false,
    offlineServerUrl: string = '',
    onOpenChapter?: (startPage: number) => void
  ) {
    this.archive = archive;
    this.offline = offline;
    this.offlineServerUrl = offlineServerUrl;
    this.onOpenChapter = onOpenChapter;
  }
}
