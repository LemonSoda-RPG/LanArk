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
import { isEnglishSystemLanguage, localized } from '../../common/Localization';

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
  onTagSelected: (tag: string) => void = (tag: string): void => {};
  onArchiveDeleted: (archiveId: string) => void = (archiveId: string): void => {};
  @State private isDeleting: boolean = false;
  @State private deleteError: string = '';
  @State private downloadTask: DownloadTask | undefined = undefined;
  @State private isDownloaded: boolean = false;
  private downloadRefreshTimer: number = -1;

  aboutToAppear(): void {
    this.refreshDownloadState();
    this.downloadRefreshTimer = setInterval(() => {
      this.refreshDownloadState();
    }, 500);
  }

  aboutToDisappear(): void {
    if (this.downloadRefreshTimer >= 0) {
      clearInterval(this.downloadRefreshTimer);
      this.downloadRefreshTimer = -1;
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
      Text(localized('危险操作'))
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.error'))
        .width('100%')
      Text(localized('删除会同时移除服务器中的档案文件和元数据，此操作无法撤销。'))
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

      Button(this.isDeleting ? localized('正在删除…') : localized('删除当前档案'))
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
      const result: DeleteDialogResult = await
        (this.getUIContext().getPromptAction().showDialog({
        title: localized('确认删除当前档案？'),
        message: isEnglishSystemLanguage() ?
          `“${this.archive.title}” will be permanently deleted from the server. Files and metadata cannot be recovered.` :
          `“${this.archive.title}”将从服务器永久删除，文件和元数据均无法恢复。`,
        buttons: [
          { text: localized('取消'), color: '#5D6B7A' },
          { text: localized('删除'), color: '#C43E3E' }
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
      const config: ServerConfig = await this.repository().load();
      const client: LanraragiApiClient =
        new LanraragiApiClient(config.serverUrl, config.apiKey);
      await client.deleteArchive(this.archive.id);
      new OfflineArchiveCache(context, config.serverUrl).clearArchive(this.archive.id);
      DownloadManager.forget(this.archive.id);
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
      if (config.serverUrl.length > 0) {
        this.isDownloaded = new OfflineArchiveCache(context, config.serverUrl)
          .isDownloaded(this.archive.id);
      }
    } catch (error) {
      this.isDownloaded = false;
    }
  }

  private describeDownloadError(error: Object): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return localized('下载档案失败');
  }

  private describeError(error: Object): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return localized('删除档案失败');
  }
}
