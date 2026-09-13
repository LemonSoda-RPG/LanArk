import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { ImageDiskCache } from '../cache/ImageDiskCache';
import { OfflineArchiveCache } from '../cache/OfflineArchiveCache';
import { LanraragiApiClient } from '../network/LanraragiApiClient';
import {
  ArchiveItem,
  ReaderPage,
  ServerConfig
} from '../../domain/model/LanraragiModels';
import { describeUserFacingError, localized } from '../../common/Localization';

export type DownloadTaskStatus = 'queued' | 'downloading' | 'completed' | 'failed';

export class DownloadTask {
  readonly archiveId: string;
  readonly title: string;
  totalPages: number;
  completedPages: number;
  status: DownloadTaskStatus;
  errorMessage: string;
  updatedAt: number;
  // Set by `forget`, so the worker stops before it writes more files.
  cancelled: boolean = false;
  // Resolves when the worker has finished, so a delete can wait for it.
  settled: Promise<void> | undefined = undefined;

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
  // Pages used to poll every 500 ms, which meant a keystore query, a manifest
  // parse and one stat per page file twice a second. They subscribe instead.
  private static listeners: Array<() => void> = [];

  static addChangeListener(listener: () => void): void {
    if (DownloadManager.listeners.indexOf(listener) < 0) {
      DownloadManager.listeners.push(listener);
    }
  }

  static removeChangeListener(listener: () => void): void {
    const index: number = DownloadManager.listeners.indexOf(listener);
    if (index >= 0) {
      DownloadManager.listeners.splice(index, 1);
    }
  }

  private static notifyChanged(): void {
    DownloadManager.listeners.forEach((listener: () => void) => {
      try {
        listener();
      } catch (error) {
        // An observer must never break the download it is watching.
      }
    });
  }

  /** True when both snapshots describe the same tasks with the same progress. */
  static sameTasks(left: Array<DownloadTask>, right: Array<DownloadTask>): boolean {
    if (left.length !== right.length) {
      return false;
    }
    for (let index: number = 0; index < left.length; index += 1) {
      const a: DownloadTask = left[index];
      const b: DownloadTask = right[index];
      if (a.archiveId !== b.archiveId || a.status !== b.status ||
        a.completedPages !== b.completedPages) {
        return false;
      }
    }
    return true;
  }

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
    // The promise is kept on the task so `forget` can wait for the worker to
    // stop before the caller deletes the files it is still writing.
    task.settled = DownloadManager.run(context, config, archive, task)
      .catch((error: Object) => {
        DownloadManager.fail(task, error);
      });
    DownloadManager.notifyChanged();
  }

  static async forget(archiveId: string): Promise<void> {
    const task: DownloadTask | undefined = DownloadManager.tasks.find((item: DownloadTask) => {
      return item.archiveId === archiveId;
    });
    if (task !== undefined) {
      task.cancelled = true;
      if (task.settled !== undefined) {
        try {
          await task.settled;
        } catch (error) {
          // A failed worker is already reported through the task status.
        }
      }
    }
    DownloadManager.tasks = DownloadManager.tasks.filter((item: DownloadTask) => {
      return item.archiveId !== archiveId;
    });
    DownloadManager.notifyChanged();
  }

  /** True while a download for this archive is queued or running. */
  static isActive(archiveId: string): boolean {
    const task: DownloadTask | undefined = DownloadManager.tasks.find((item: DownloadTask) => {
      return item.archiveId === archiveId;
    });
    return task !== undefined && (task.status === 'queued' || task.status === 'downloading');
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
    const imageCache: ImageDiskCache = new ImageDiskCache(context, config.serverUrl);
    const client: LanraragiApiClient =
      new LanraragiApiClient(config.serverUrl, config.apiKey);
    await DownloadManager.cacheCover(client, imageCache, archive.id);
    const pages: Array<ReaderPage> = await client.fetchArchivePages(archive.id);
    if (pages.length === 0) {
      throw new Error(localized('离线档案页面列表为空'));
    }
    task.totalPages = pages.length;
    task.completedPages = cache.countDownloadedPages(archive.id, pages);
    for (let index = 0; index < pages.length; index += 1) {
      if (task.cancelled) {
        // Removed while running. Stop before the manifest is committed, so the
        // archive cannot reappear after the caller deleted its files.
        return;
      }
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
      DownloadManager.notifyChanged();
    }
    // The manifest is committed last, so an interrupted download never appears
    // as a usable offline archive.
    cache.saveManifest(archive, pages);
    task.completedPages = pages.length;
    task.status = 'completed';
    task.errorMessage = '';
    task.updatedAt = Date.now();
    DownloadManager.notifyChanged();
  }

  private static async cacheCover(
    client: LanraragiApiClient,
    cache: ImageDiskCache,
    archiveId: string
  ): Promise<void> {
    if (cache.readCover(archiveId) !== undefined) {
      return;
    }
    try {
      const data: ArrayBuffer | undefined = await client.fetchArchiveThumbnail(archiveId);
      if (data === undefined) {
        return;
      }
      const source: image.ImageSource = image.createImageSource(data);
      let cover: image.PixelMap | undefined = undefined;
      try {
        const info: image.ImageInfo = await source.getImageInfo();
        let width: number = Math.min(Math.max(info.size.width, 1), 480);
        let height: number = info.size.width > 0 ?
          Math.max(Math.round(info.size.height * width / info.size.width), 1) : 720;
        if (height > 720) {
          width = Math.max(Math.round(width * 720 / height), 1);
          height = 720;
        }
        cover = await source.createPixelMap({ desiredSize: { width, height } });
        await cache.writeCover(archiveId, cover);
      } finally {
        if (cover !== undefined) {
          cover.release();
        }
        await source.release();
      }
    } catch (error) {
      // A cover is optional; page downloading must continue when it fails.
    }
  }

  private static fail(task: DownloadTask, error: Object): void {
    task.status = 'failed';
    task.errorMessage = describeUserFacingError(error, localized('下载档案失败'));
    task.updatedAt = Date.now();
    DownloadManager.notifyChanged();
  }
}
