import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { ImageDiskCache } from '../../data/cache/ImageDiskCache';
import { OfflineArchiveCache, OfflineArchiveRecord } from '../../data/cache/OfflineArchiveCache';
import { LanraragiApiClient } from '../../data/network/LanraragiApiClient';
import { ServerConfigRepository } from '../../data/config/ServerConfigRepository';
import { DownloadManager } from '../../data/download/DownloadManager';
import { OfflineProgressRepository } from '../../data/download/OfflineProgressRepository';
import { ArchiveItem, ReaderRouteParams, ServerConfig } from '../../domain/model/LanraragiModels';
import { localized } from '../../common/Localization';

interface OfflineDeleteDialogResult {
  index: number;
}

@Component
struct DownloadedCoverView {
  archiveId: string = '';
  fileExtension: string = '';
  serverUrl: string = '';
  apiKey: string = '';
  @State private cover: image.PixelMap | undefined = undefined;
  @State private isLoading: boolean = false;
  // Set when the component is destroyed; a decode still awaiting at that point
  // would otherwise assign `cover` after the only release ran.
  private destroyed: boolean = false;

  aboutToAppear(): void {
    this.loadCover();
  }

  aboutToBeDeleted(): void {
    this.destroyed = true;
    this.releaseCover();
  }

  private releaseCover(): void {
    if (this.cover !== undefined) {
      this.cover.release().catch(() => {});
      this.cover = undefined;
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
        const decoded: image.PixelMap = await source.createPixelMap({
          desiredSize: { width: targetWidth, height: targetHeight }
        });
        if (this.destroyed) {
          // aboutToBeDeleted already ran, so releasing here is the last chance.
          decoded.release().catch(() => {});
          return;
        }
        this.cover = decoded;
        if (shouldCache) {
          await cache.writeCover(this.archiveId, decoded);
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

class OfflineRecordDataSource implements IDataSource {
  private records: Array<OfflineArchiveRecord> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.records.length;
  }

  getData(index: number): OfflineArchiveRecord {
    return this.records[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  replace(records: Array<OfflineArchiveRecord>): void {
    this.records = records;
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }
}

@Component
export struct DownloadedArchivesPage {
  @Consume('pathStack') private pathStack: NavPathStack = new NavPathStack();
  @State private records: Array<OfflineArchiveRecord> = [];
  private recordDataSource: OfflineRecordDataSource = new OfflineRecordDataSource();
  @State private serverUrl: string = '';
  @State private apiKey: string = '';
  @State private deletingArchiveId: string = '';

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
            // Only visible rows are built. Each row decodes a cover, so ForEach
            // used to decode every offline archive before the first frame.
            LazyForEach(this.recordDataSource, (record: OfflineArchiveRecord) => {
              ListItem() {
                this.archiveRow(record)
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
          .cachedCount(6)
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
  private archiveRow(record: OfflineArchiveRecord) {
    Row({ space: 14 }) {
      DownloadedCoverView({
        archiveId: record.archive.id,
        fileExtension: record.archive.fileExtension,
        serverUrl: this.serverUrl,
        apiKey: this.apiKey
      })

      Column({ space: 6 }) {
        Text(record.archive.title)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(`${record.pages.length} ${localized('页', 'pages')} · ${localized('可离线阅读')}`)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      .layoutWeight(1)

      Button(localized('删除本地下载'))
        .height(38)
        .fontSize(12)
        .fontColor($r('app.color.error'))
        .backgroundColor($r('app.color.error_soft'))
        .borderRadius(19)
        .enabled(this.deletingArchiveId.length === 0)
        .onClick(() => {
          this.confirmDelete(record);
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  private async confirmDelete(record: OfflineArchiveRecord): Promise<void> {
    if (this.deletingArchiveId.length > 0) {
      return;
    }
    try {
      const result: OfflineDeleteDialogResult = await
        (this.getUIContext().getPromptAction().showDialog({
          title: localized('确认删除本地下载？'),
          message: localized('只会删除手机上的离线副本，不会删除服务器档案。'),
          buttons: [
            { text: localized('取消'), color: $r('app.color.text_secondary') },
            { text: localized('删除'), color: $r('app.color.error') }
          ]
        }) as Promise<OfflineDeleteDialogResult>);
      if (result.index === 1) {
        await this.deleteLocalArchive(record);
      }
    } catch (error) {
      // Closing the dialog must not affect the offline library.
    }
  }

  private async deleteLocalArchive(record: OfflineArchiveRecord): Promise<void> {
    this.deletingArchiveId = record.archive.id;
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      // This path is deliberately local-only: no API client and no server call.
      new OfflineArchiveCache(context, this.serverUrl).clearArchive(record.archive.id);
      await DownloadManager.forget(record.archive.id);
      await new OfflineProgressRepository(context).clear(record.archive.id);
      this.records = this.records.filter((item: OfflineArchiveRecord) => {
        return item.archive.id !== record.archive.id;
      });
      this.recordDataSource.replace(this.records);
      try {
        this.getUIContext().getPromptAction().showToast({
          message: localized('本地下载已删除')
        });
      } catch (error) {
        // The local deletion already completed if the toast is unavailable.
      }
    } finally {
      this.deletingArchiveId = '';
    }
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
      // The lookups are independent, so they run together instead of one after
      // another; each one opens the preferences store.
      const progressValues: Array<number> = await Promise.all(
        records.map((record: OfflineArchiveRecord) => {
          return progressRepository.load(record.archive.id);
        })
      );
      for (let index = 0; index < records.length; index += 1) {
        if (progressValues[index] > 0) {
          records[index].archive.setProgress(progressValues[index]);
        }
      }
      this.records = records;
      this.recordDataSource.replace(records);
    } catch (error) {
      this.records = [];
      this.recordDataSource.replace([]);
    }
  }
}
