import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { ImageDiskCache } from '../../data/cache/ImageDiskCache';
import { OfflineArchiveCache, OfflineArchiveRecord } from '../../data/cache/OfflineArchiveCache';
import { LanraragiApiClient } from '../../data/network/LanraragiApiClient';
import { ServerConfigRepository } from '../../data/config/ServerConfigRepository';
import { OfflineProgressRepository } from '../../data/download/OfflineProgressRepository';
import { ArchiveItem, ReaderRouteParams, ServerConfig } from '../../domain/model/LanraragiModels';
import { localized } from '../../common/Localization';

@Component
struct DownloadedCoverView {
  archiveId: string = '';
  fileExtension: string = '';
  serverUrl: string = '';
  apiKey: string = '';
  @State private cover: image.PixelMap | undefined = undefined;
  @State private isLoading: boolean = false;

  aboutToAppear(): void {
    this.loadCover();
  }

  aboutToBeDeleted(): void {
    if (this.cover !== undefined) {
      this.cover.release();
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.cover !== undefined) {
        Image(this.cover as image.PixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else {
        Text(this.fileExtension.toUpperCase())
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.extension_text'))
          .hitTestBehavior(HitTestMode.None)
        if (this.isLoading) {
          LoadingProgress()
            .width(22)
            .height(22)
            .margin({ top: 48 })
        }
      }
    }
    .width(68)
    .height(92)
    .backgroundColor($r('app.color.surface_muted'))
    .borderRadius(10)
    .clip(true)
  }

  private async loadCover(): Promise<void> {
    if (this.isLoading || this.archiveId.length === 0) {
      return;
    }
    this.isLoading = true;
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const cache: ImageDiskCache = new ImageDiskCache(context, this.serverUrl);
      let buffer: ArrayBuffer | undefined = cache.readCover(this.archiveId);
      let shouldCache: boolean = false;
      if (buffer === undefined && this.serverUrl.length > 0) {
        const client: LanraragiApiClient =
          new LanraragiApiClient(this.serverUrl, this.apiKey);
        buffer = await client.fetchArchiveThumbnail(this.archiveId);
        shouldCache = buffer !== undefined;
      }
      if (buffer === undefined) {
        return;
      }
      const source: image.ImageSource = image.createImageSource(buffer);
      try {
        const info: image.ImageInfo = await source.getImageInfo();
        let targetWidth: number = Math.min(Math.max(info.size.width, 1), 480);
        let targetHeight: number = info.size.width > 0 ?
          Math.max(Math.round(info.size.height * targetWidth / info.size.width), 1) : 720;
        if (targetHeight > 720) {
          targetWidth = Math.max(Math.round(targetWidth * 720 / targetHeight), 1);
          targetHeight = 720;
        }
        this.cover = await source.createPixelMap({
          desiredSize: { width: targetWidth, height: targetHeight }
        });
        if (shouldCache && this.cover !== undefined) {
          await cache.writeCover(this.archiveId, this.cover);
        }
      } finally {
        await source.release();
      }
    } catch (error) {
      // Keep the extension placeholder if the cover is unavailable offline.
    } finally {
      this.isLoading = false;
    }
  }
}

@Component
export struct DownloadedArchivesPage {
  @Consume('pathStack') private pathStack: NavPathStack = new NavPathStack();
  @State private records: Array<OfflineArchiveRecord> = [];
  @State private serverUrl: string = '';
  @State private apiKey: string = '';

  aboutToAppear(): void {
    this.refresh();
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
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
          .accessibilityText(localized('返回档案库'))
          .onClick(() => this.pathStack.pop())

          Text(localized('已下载'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Button(localized('下载管理'))
            .height(38)
            .fontSize(13)
            .fontColor($r('app.color.accent_text'))
            .backgroundColor($r('app.color.accent_soft'))
            .borderRadius(19)
            .onClick(() => {
              this.pathStack.pushPath({ name: 'DownloadManager', param: new Object() });
            })
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })

        if (this.records.length === 0) {
          Column({ space: 10 }) {
            Text(localized('没有已下载档案'))
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
            Text(localized('在档案信息中点击下载，即可在无网络时阅读。'))
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding(24)
        } else {
          List({ space: 10 }) {
            ForEach(this.records, (record: OfflineArchiveRecord) => {
              ListItem() {
                this.archiveRow(record.archive, record.pages.length)
              }
              .onClick(() => {
                this.pathStack.pushPath({
                  name: 'ArchiveReader',
                  param: new ReaderRouteParams(
                    record.archive,
                    false,
                    true,
                    this.serverUrl
                  )
                });
              })
            }, (record: OfflineArchiveRecord) => `offline-${record.archive.id}`)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .padding({ left: 16, right: 16, bottom: 20 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private archiveRow(archive: ArchiveItem, pageCount: number) {
    Row({ space: 14 }) {
      DownloadedCoverView({
        archiveId: archive.id,
        fileExtension: archive.fileExtension,
        serverUrl: this.serverUrl,
        apiKey: this.apiKey
      })

      Column({ space: 6 }) {
        Text(archive.title)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(`${pageCount} ${localized('页', 'pages')} · ${localized('可离线阅读')}`)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  private async refresh(): Promise<void> {
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const config: ServerConfig = await new ServerConfigRepository(context).load();
      this.serverUrl = config.serverUrl;
      this.apiKey = config.apiKey;
      const records: Array<OfflineArchiveRecord> =
        new OfflineArchiveCache(context, config.serverUrl).listRecords();
      const progressRepository: OfflineProgressRepository =
        new OfflineProgressRepository(context);
      for (let index = 0; index < records.length; index += 1) {
        const progress: number = await progressRepository.load(records[index].archive.id);
        if (progress > 0) {
          records[index].archive.setProgress(progress);
        }
      }
      this.records = records;
    } catch (error) {
      this.records = [];
    }
  }
}
