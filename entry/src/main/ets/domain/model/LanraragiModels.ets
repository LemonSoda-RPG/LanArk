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

export interface ArchiveIndexPayload {
  arcid: string;
  extension: string;
  isnew: string | boolean | number;
  tags?: string;
  title: string;
  pagecount: number;
  progress: number;
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
  readonly archiveCount: number;
  readonly dateAdded: number;

  constructor(payload: ArchiveIndexPayload) {
    this.id = payload.arcid;
    this.fileExtension = payload.extension;
    this.isNew = payload.isnew === true || payload.isnew === 1 ||
      payload.isnew === '1' || payload.isnew === 'true';
    this.tags = payload.tags ?? '';
    this.title = payload.title;
    this.pageCount = payload.pagecount;
    this.progress = payload.progress;
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
    const visible: Array<string> = this.tagItems()
      .filter((tag: string) => !tag.toLowerCase().startsWith('date_added:'))
      .slice(0, 3);
    return visible.join(' · ');
  }

  tagItems(): Array<string> {
    if (this.tags.length === 0) {
      return [];
    }
    return this.tags.split(',')
      .map((tag: string) => tag.trim())
      .filter((tag: string) => tag.length > 0);
  }

  tagValue(namespace: string): string {
    const prefix: string = `${namespace.toLowerCase()}:`;
    const parts: Array<string> = this.tags.split(',');
    for (let index: number = 0; index < parts.length; index++) {
      const tag: string = parts[index].trim();
      if (tag.toLowerCase().startsWith(prefix)) {
        return tag.substring(prefix.length).trim();
      }
    }
    return '';
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
      archive_count: this.archiveCount
    };
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

export interface ArchivePagesPayload {
  pages: Array<string>;
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

  constructor(
    archive: ArchiveItem,
    fromStart: boolean,
    offline: boolean = false,
    offlineServerUrl: string = ''
  ) {
    this.archive = archive;
    this.fromStart = fromStart;
    this.offline = offline;
    this.offlineServerUrl = offlineServerUrl;
  }
}
