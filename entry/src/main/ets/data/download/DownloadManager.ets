import { common } from '@kit.AbilityKit';
import { OfflineArchiveCache } from '../cache/OfflineArchiveCache';
import { LanraragiApiClient } from '../network/LanraragiApiClient';
import {
  ArchiveItem,
  ReaderPage,
  ServerConfig
} from '../../domain/model/LanraragiModels';
import { localized } from '../../common/Localization';

export type DownloadTaskStatus = 'queued' | 'downloading' | 'completed' | 'failed';

export class DownloadTask {
  readonly archiveId: string;
  readonly title: string;
  totalPages: number;
  completedPages: number;
  status: DownloadTaskStatus;
  errorMessage: string;
  updatedAt: number;

  constructor(
    archiveId: string,
    title: string,
    totalPages: number = 0,
    completedPages: number = 0,
    status: DownloadTaskStatus = 'queued',
    errorMessage: string = ''
  ) {
    this.archiveId = archiveId;
    this.title = title;
    this.totalPages = totalPages;
    this.completedPages = completedPages;
    this.status = status;
    this.errorMessage = errorMessage;
    this.updatedAt = Date.now();
  }

  get progressRatio(): number {
    if (this.totalPages <= 0) {
      return 0;
    }
    return Math.min(this.completedPages / this.totalPages, 1);
  }

  copy(): DownloadTask {
    const task: DownloadTask = new DownloadTask(
      this.archiveId,
      this.title,
      this.totalPages,
      this.completedPages,
      this.status,
      this.errorMessage
    );
    task.updatedAt = this.updatedAt;
    return task;
  }
}

/** In-process queue used by the archive info and download management pages. */
export class DownloadManager {
  private static tasks: Array<DownloadTask> = [];

  static snapshot(): Array<DownloadTask> {
    return DownloadManager.tasks.map((task: DownloadTask) => task.copy());
  }

  static taskFor(archiveId: string): DownloadTask | undefined {
    const task: DownloadTask | undefined = DownloadManager.tasks.find((item: DownloadTask) => {
      return item.archiveId === archiveId;
    });
    return task === undefined ? undefined : task.copy();
  }

  static start(
    context: common.UIAbilityContext,
    config: ServerConfig,
    archive: ArchiveItem
  ): void {
    const existing: DownloadTask | undefined = DownloadManager.tasks.find((task: DownloadTask) => {
      return task.archiveId === archive.id;
    });
    if (existing !== undefined &&
      (existing.status === 'queued' || existing.status === 'downloading')) {
      return;
    }

    const task: DownloadTask = existing ?? new DownloadTask(archive.id, archive.title);
    task.status = 'queued';
    task.errorMessage = '';
    task.completedPages = 0;
    task.totalPages = archive.pageCount;
    task.updatedAt = Date.now();
    if (existing === undefined) {
      DownloadManager.tasks.push(task);
    }
    DownloadManager.run(context, config, archive, task).catch((error: Object) => {
      DownloadManager.fail(task, error);
    });
  }

  static removeFinished(archiveId: string): void {
    DownloadManager.tasks = DownloadManager.tasks.filter((task: DownloadTask) => {
      return task.archiveId !== archiveId ||
        (task.status !== 'completed' && task.status !== 'failed');
    });
  }

  static forget(archiveId: string): void {
    DownloadManager.tasks = DownloadManager.tasks.filter((task: DownloadTask) => task.archiveId !== archiveId);
  }

  private static async run(
    context: common.UIAbilityContext,
    config: ServerConfig,
    archive: ArchiveItem,
    task: DownloadTask
  ): Promise<void> {
    if (config.serverUrl.length === 0) {
      throw new Error(localized('请先在设置中配置服务器'));
    }
    task.status = 'downloading';
    task.updatedAt = Date.now();
    const cache: OfflineArchiveCache = new OfflineArchiveCache(context, config.serverUrl);
    const client: LanraragiApiClient =
      new LanraragiApiClient(config.serverUrl, config.apiKey);
    const pages: Array<ReaderPage> = await client.fetchArchivePages(archive.id);
    if (pages.length === 0) {
      throw new Error(localized('离线档案页面列表为空'));
    }
    task.totalPages = pages.length;
    task.completedPages = cache.countDownloadedPages(archive.id, pages);
    for (let index = 0; index < pages.length; index += 1) {
      const page: ReaderPage = pages[index];
      if (cache.readPage(archive.id, page.pageNumber) === undefined) {
        const data: ArrayBuffer | undefined = await client.fetchArchivePage(page, archive.id);
        if (data === undefined) {
          throw new Error(`${localized('下载页面失败')} ${page.pageNumber}`);
        }
        cache.writePage(archive.id, page.pageNumber, data);
      }
      task.completedPages = index + 1;
      task.updatedAt = Date.now();
    }
    // The manifest is committed last, so an interrupted download never appears
    // as a usable offline archive.
    cache.saveManifest(archive, pages);
    task.completedPages = pages.length;
    task.status = 'completed';
    task.errorMessage = '';
    task.updatedAt = Date.now();
  }

  private static fail(task: DownloadTask, error: Object): void {
    task.status = 'failed';
    task.errorMessage = error instanceof Error && error.message.length > 0 ?
      error.message : localized('下载档案失败');
    task.updatedAt = Date.now();
  }
}
