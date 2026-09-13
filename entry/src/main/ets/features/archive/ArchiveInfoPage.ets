import { common } from '@kit.AbilityKit';
import { OfflineArchiveCache } from '../../data/cache/OfflineArchiveCache';
import { ServerConfigRepository } from '../../data/config/ServerConfigRepository';
import { LanraragiApiClient } from '../../data/network/LanraragiApiClient';
import { DownloadManager, DownloadTask } from '../../data/download/DownloadManager';
import { OfflineProgressRepository } from '../../data/download/OfflineProgressRepository';
import {
  ArchiveIndexPayload,
  ArchiveItem,
  ServerConfig
} from '../../domain/model/LanraragiModels';
import { describeUserFacingError, isEnglishSystemLanguage, localized } from '../../common/Localization';

function emptyArchive(): ArchiveItem {
  const payload: ArchiveIndexPayload = {
    arcid: '',
    extension: '',
    isnew: false,
    tags: '',
    title: '',
    pagecount: 0,
    progress: 0
  };
  return new ArchiveItem(payload);
}

interface DeleteDialogResult {
  index: number;
}

@Component
export struct ArchiveInfoPage {
  @Consume('pathStack') private pathStack: NavPathStack = new NavPathStack();
  archive: ArchiveItem = emptyArchive();
  offline: boolean = false;
  offlineServerUrl: string = '';
  onTagSelected: (tag: string) => void = (tag: string): void => {};
  onArchiveDeleted: (archiveId: string) => void = (archiveId: string): void => {};
  onLocalDownloadDeleted: (archiveId: string) => void = (archiveId: string): void => {};
  @State private isDeleting: boolean = false;
  @State private deleteError: string = '';
  @State private downloadTask: DownloadTask | undefined = undefined;
  @State private isDownloaded: boolean = false;
  // `isDownloaded` is only meaningful once a check has actually succeeded. A
  // failed check must not read as "not downloaded", because that is exactly what
  // decides whether deleting touches the server copy.
  @State private isDownloadStateKnown: boolean = false;
  // Bound once so the same reference can be unregistered.
  private readonly downloadListener: () => void = (): void => {
    this.onDownloadChanged();
  };

  aboutToAppear(): void {
    this.refreshDownloadState();
    DownloadManager.addChangeListener(this.downloadListener);
  }

  aboutToDisappear(): void {
    DownloadManager.removeChangeListener(this.downloadListener);
  }

  /**
   * Reacts to a download change instead of polling twice a second.
   *
   * The snapshot is only reassigned when it actually differs, and the on-disk
   * state is re-checked once the task stops running, because that is when the
   * manifest can have appeared. Polling here used to cost a keystore query, a
   * manifest parse and one stat per page file every 500 ms.
   */
  private onDownloadChanged(): void {
    const next: DownloadTask | undefined = DownloadManager.taskFor(this.archive.id);
    const changed: boolean = this.downloadTask === undefined || next === undefined ||
      next.status !== this.downloadTask.status ||
      next.completedPages !== this.downloadTask.completedPages;
    if (changed) {
      this.downloadTask = next;
    }
    if (!DownloadManager.isActive(this.archive.id)) {
      this.refreshDownloadState();
    }
  }

  build() {
    NavDestination() {
      Column({ space: 8 }) {
        Row({ space: 10 }) {
          Button() {
            Image($r('app.media.icon_chevron_left'))
              .width(21)
              .height(21)
              .renderMode(ImageRenderMode.Template)
              .fillColor($r('app.color.text_primary'))
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor($r('app.color.surface'))
          .border({ width: 1, color: $r('app.color.divider') })
          .accessibilityText(localized('返回阅读界面'))
          .onClick(() => {
            this.pathStack.pop();
          })

          Text(localized('档案信息'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })

        List({ space: 18 }) {
          ListItem() {
            this.archiveSummaryCard()
          }
          ListItem() {
            this.tagSection()
          }
          ListItem() {
            this.downloadSection()
          }
          ListItem() {
            this.dangerSection()
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ left: 16, right: 16, bottom: 32 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private downloadSection() {
    Column({ space: 12 }) {
      Row() {
        Text(localized('离线阅读'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (this.isDownloaded) {
          Text(localized('已下载'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(13)
            .fontColor($r('app.color.accent_text'))
        }
      }
      .width('100%')

      Text(localized('下载到应用内后可在无网络时阅读，下载内容不会修改服务器中的原始档案。'))
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(13)
        .lineHeight(19)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      if (this.downloadTask !== undefined &&
        (this.downloadTask.status === 'downloading' || this.downloadTask.status === 'queued')) {
        Progress({
          value: this.downloadTask.completedPages,
          total: Math.max(this.downloadTask.totalPages, 1),
          type: ProgressType.Linear
        })
          .width('100%')
          .height(6)
          .color($r('app.color.accent'))
          .backgroundColor($r('app.color.surface_muted'))
        Text(`${this.downloadTask.completedPages}/${this.downloadTask.totalPages} ${localized('页', 'pages')} · ${localized('下载中')}`)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      }

      if (this.downloadTask !== undefined && this.downloadTask.status === 'failed') {
        Text(this.downloadTask.errorMessage)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .fontColor($r('app.color.error'))
          .width('100%')
          .padding(10)
          .backgroundColor($r('app.color.error_soft'))
          .borderRadius(10)
      }

      Button(this.isDownloaded ? localized('已下载，可离线阅读') :
        (this.downloadTask !== undefined && this.downloadTask.status === 'downloading' ?
          localized('下载管理中') : localized('下载当前档案')))
        .width('100%')
        .height(48)
        .enabled(!this.isDownloaded &&
          (this.downloadTask === undefined ||
            (this.downloadTask.status !== 'downloading' && this.downloadTask.status !== 'queued')))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDownloaded ? $r('app.color.accent_text') : Color.White)
        .backgroundColor(this.isDownloaded ?
          $r('app.color.accent_soft') : $r('app.color.accent'))
        .onClick(() => {
          this.startDownload();
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1, color: $r('app.color.divider') })
    .borderRadius(16)
  }

  @Builder
  private archiveSummaryCard() {
    Column({ space: 7 }) {
      Text(this.archive.title)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(`${this.archive.pageCount} ${localized('页', 'pages')} · ${this.archive.progressText}`)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1, color: $r('app.color.divider') })
    .borderRadius(16)
  }

  @Builder
  private tagSection() {
    Column({ space: 12 }) {
      Row() {
        Text(localized('全部标签'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`${this.archive.tagItems().length} ${localized('项', 'tags')}`)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')

      if (this.archive.tagItems().length === 0) {
        Text(localized('当前档案没有标签'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ top: 10, bottom: 10 })
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.archive.tagItems(), (tag: string, index: number) => {
            Row() {
              Text(tag)
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(13)
                .lineHeight(19)
                .fontColor($r('app.color.accent_text'))
                .maxLines(3)
                .hitTestBehavior(HitTestMode.None)
            }
            .constraintSize({ maxWidth: '100%' })
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .margin({ right: 8, bottom: 8 })
            .backgroundColor($r('app.color.accent_soft'))
            .borderRadius(11)
            .accessibilityText(`${localized('搜索标签', 'Search tag')} ${tag}`)
            .onClick(() => {
              this.onTagSelected(tag);
            })
          }, (tag: string, index: number) => `archive-tag-${index}-${tag}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1, color: $r('app.color.divider') })
    .borderRadius(16)
  }

  @Builder
  private dangerSection() {
    Column({ space: 12 }) {
      Text(this.isDownloaded || this.offline ? localized('本地下载管理') : localized('危险操作'))
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.isDownloaded || this.offline ?
          $r('app.color.text_primary') : $r('app.color.error'))
        .width('100%')
      Text(this.isDownloaded || this.offline ?
        localized('这里只删除本地离线副本，不会删除服务器档案。') :
        localized('删除会同时移除服务器中的档案文件和元数据，此操作无法撤销。'))
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(13)
        .lineHeight(19)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      if (this.deleteError.length > 0) {
        Text(this.deleteError)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .fontColor($r('app.color.error'))
          .width('100%')
          .padding(10)
          .backgroundColor($r('app.color.error_soft'))
          .borderRadius(10)
      }

      Button(this.isDeleting ? localized('正在删除…') :
        (this.isDownloaded || this.offline ? localized('删除本地下载') : localized('删除当前档案')))
        .width('100%')
        .height(48)
        .enabled(!this.isDeleting)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.error'))
        .backgroundColor($r('app.color.error_soft'))
        .onClick(() => {
          this.confirmDelete();
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1, color: $r('app.color.error_soft') })
    .borderRadius(16)
  }

  private async confirmDelete(): Promise<void> {
    if (this.isDeleting || this.archive.id.length === 0) {
      return;
    }
    this.deleteError = '';
    try {
      // Re-check local storage immediately before showing the destructive action.
      // This prevents a downloaded archive from falling through to server deletion
      // while the periodic download-state refresh is still running.
      await this.refreshDownloadState();
      if (DownloadManager.isActive(this.archive.id)) {
        this.deleteError = localized('该档案正在下载，请先在下载管理中清除任务');
        return;
      }
      if (!this.isDownloadStateKnown && !this.offline) {
        this.deleteError = localized('无法确认本地下载状态，请稍后重试');
        return;
      }
      const result: DeleteDialogResult = await
        (this.getUIContext().getPromptAction().showDialog({
        title: this.isDownloaded || this.offline ?
          localized('确认删除本地下载？') : localized('确认删除当前档案？'),
        message: this.isDownloaded || this.offline ?
          localized('只会删除手机上的离线副本，不会删除服务器档案。') :
          (isEnglishSystemLanguage() ?
            `“${this.archive.title}” will be permanently deleted from the server. Files and metadata cannot be recovered.` :
            `“${this.archive.title}”将从服务器永久删除，文件和元数据均无法恢复。`),
        buttons: [
          { text: localized('取消'), color: $r('app.color.text_secondary') },
          { text: localized('删除'), color: $r('app.color.error') }
        ]
      }) as Promise<DeleteDialogResult>);
      if (result.index !== 1) {
        return;
      }
      await this.deleteArchive();
    } catch (error) {
      this.deleteError = this.describeError(error);
    }
  }

  private async deleteArchive(): Promise<void> {
    this.isDeleting = true;
    this.deleteError = '';
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (this.offline && this.offlineServerUrl.length > 0) {
        new OfflineArchiveCache(context, this.offlineServerUrl).clearArchive(this.archive.id);
        await DownloadManager.forget(this.archive.id);
        await new OfflineProgressRepository(context).clear(this.archive.id);
        this.isDownloaded = false;
        this.onLocalDownloadDeleted(this.archive.id);
        return;
      }
      const config: ServerConfig = await this.repository().load();
      if (this.isDownloaded || this.offline) {
        const storageServerUrl: string = this.offlineServerUrl.length > 0 ?
          this.offlineServerUrl : config.serverUrl;
        new OfflineArchiveCache(context, storageServerUrl).clearArchive(this.archive.id);
        await DownloadManager.forget(this.archive.id);
        await new OfflineProgressRepository(context).clear(this.archive.id);
        this.isDownloaded = false;
        this.onLocalDownloadDeleted(this.archive.id);
        return;
      }
      // Never fall through to deleting the server copy while the local state is
      // unknown or a download is still writing files for this archive.
      if (DownloadManager.isActive(this.archive.id) || !this.isDownloadStateKnown) {
        this.deleteError = localized('无法确认本地下载状态，请稍后重试');
        return;
      }
      const client: LanraragiApiClient =
        new LanraragiApiClient(config.serverUrl, config.apiKey);
      await client.deleteArchive(this.archive.id);
      new OfflineArchiveCache(context, config.serverUrl).clearArchive(this.archive.id);
      await DownloadManager.forget(this.archive.id);
      await new OfflineProgressRepository(context).clear(this.archive.id);
      this.onArchiveDeleted(this.archive.id);
    } catch (error) {
      this.deleteError = this.describeError(error);
    } finally {
      this.isDeleting = false;
    }
  }

  private repository(): ServerConfigRepository {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    return new ServerConfigRepository(context);
  }

  private async startDownload(): Promise<void> {
    if (this.archive.id.length === 0 || this.isDownloaded) {
      return;
    }
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const config: ServerConfig = await this.repository().load();
      DownloadManager.start(context, config, this.archive);
      this.downloadTask = DownloadManager.taskFor(this.archive.id);
    } catch (error) {
      this.downloadTask = new DownloadTask(
        this.archive.id,
        this.archive.title,
        this.archive.pageCount,
        0,
        'failed',
        this.describeDownloadError(error)
      );
    }
  }

  private async refreshDownloadState(): Promise<void> {
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const task: DownloadTask | undefined = DownloadManager.taskFor(this.archive.id);
      this.downloadTask = task;
      const config: ServerConfig = await this.repository().load();
      const storageServerUrl: string = this.offlineServerUrl.length > 0 ?
        this.offlineServerUrl : config.serverUrl;
      this.isDownloaded = storageServerUrl.length > 0 &&
        new OfflineArchiveCache(context, storageServerUrl).isDownloaded(this.archive.id);
      this.isDownloadStateKnown = storageServerUrl.length > 0;
    } catch (error) {
      // A failed check leaves the state unknown rather than "not downloaded".
      this.isDownloadStateKnown = false;
    }
  }

  private describeDownloadError(error: Object): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return localized('下载档案失败');
  }

  private describeError(error: Object): string {
    return describeUserFacingError(error, localized('删除档案失败'));
  }
}
