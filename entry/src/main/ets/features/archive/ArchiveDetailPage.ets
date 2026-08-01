import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { ImageDiskCache } from '../../data/cache/ImageDiskCache';
import { ServerConfigRepository } from '../../data/config/ServerConfigRepository';
import { LanraragiApiClient } from '../../data/network/LanraragiApiClient';
import {
  ArchiveIndexPayload,
  ArchiveItem,
  ReaderRouteParams,
  ServerConfig
} from '../../domain/model/LanraragiModels';

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

@Component
export struct ArchiveDetailPage {
  @Consume('pathStack') private pathStack: NavPathStack = new NavPathStack();
  archive: ArchiveItem = emptyArchive();
  @State private thumbnail: image.PixelMap | undefined = undefined;
  @State private isThumbnailLoading: boolean = false;
  @State private thumbnailError: string = '';

  aboutToAppear(): void {
    this.loadThumbnail();
  }

  aboutToBeDeleted(): void {
    if (this.thumbnail !== undefined) {
      this.thumbnail.release();
    }
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 22 }) {
          Stack() {
            if (this.thumbnail !== undefined) {
              Image(this.thumbnail as image.PixelMap)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Contain)
            } else if (this.isThumbnailLoading) {
              LoadingProgress()
                .width(42)
                .height(42)
            } else {
              Column({ space: 8 }) {
                Text(this.archive.fileExtension.toUpperCase())
                  .copyOption(CopyOptions.LocalDevice)
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.extension_text'))
                if (this.thumbnailError.length > 0) {
                  Text(this.thumbnailError)
                    .copyOption(CopyOptions.LocalDevice)
                    .fontSize(13)
                    .fontColor($r('app.color.text_tertiary'))
                    .textAlign(TextAlign.Center)
                }
              }
            }
          }
          .width('100%')
          .height(360)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius(18)

          Column({ space: 12 }) {
            Row({ space: 10 }) {
              Text(this.archive.title)
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(25)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
              if (this.archive.isNew) {
                Text('NEW')
                  .copyOption(CopyOptions.LocalDevice)
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor($r('app.color.new_badge'))
                  .borderRadius(7)
              }
            }
            .width('100%')

            Text(`${this.archive.pageCount} 页 · ${this.archive.progressText}`)
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(15)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

            if (this.archive.tags.length > 0) {
              Column({ space: 10 }) {
                Text('标签')
                  .copyOption(CopyOptions.LocalDevice)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(
                    this.archive.tagItems()
                      .filter((tag: string) => {
                        return !tag.toLowerCase().startsWith('date_added:');
                      })
                      .slice(0, 30),
                    (tag: string) => {
                      Text(tag)
                        .copyOption(CopyOptions.LocalDevice)
                        .fontSize(12)
                        .fontColor($r('app.color.accent_text'))
                        .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                        .margin({ right: 7, bottom: 7 })
                        .backgroundColor($r('app.color.accent_soft'))
                        .borderRadius(10)
                    }
                  )
                }
                .width('100%')
              }
              .width('100%')
              .padding(14)
              .backgroundColor($r('app.color.surface'))
              .borderRadius(12)
            }
          }
          .width('100%')

          Button(this.archive.progress > 0 ? '继续阅读' : '开始阅读')
            .width('100%')
            .height(52)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.accent'))
            .onClick(() => {
              this.openReader(false);
            })

          if (this.archive.progress > 0) {
            Button('从第一页开始')
              .width('100%')
              .height(50)
              .fontSize(16)
              .backgroundColor($r('app.color.accent_soft'))
              .fontColor($r('app.color.accent_text'))
              .onClick(() => {
                this.openReader(true);
              })
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: 720 })
        .padding({ left: 20, right: 20, top: 20, bottom: 48 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .title('档案详情')
  }

  private openReader(fromStart: boolean): void {
    this.pathStack.pushPath({
      name: 'ArchiveReader',
      param: new ReaderRouteParams(this.archive, fromStart)
    });
  }

  private async loadThumbnail(): Promise<void> {
    if (this.archive.id.length === 0 || this.isThumbnailLoading) {
      return;
    }
    this.isThumbnailLoading = true;
    this.thumbnailError = '';
    try {
      const config: ServerConfig = await this.repository().load();
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const cache: ImageDiskCache = new ImageDiskCache(context, config.serverUrl);
      let buffer: ArrayBuffer | undefined = cache.readCover(this.archive.id);
      let shouldCache: boolean = false;
      const client: LanraragiApiClient =
        new LanraragiApiClient(config.serverUrl, config.apiKey);
      if (buffer === undefined) {
        buffer = await client.fetchArchiveThumbnail(this.archive.id);
        shouldCache = buffer !== undefined;
      }
      if (buffer === undefined) {
        this.thumbnailError = '缩略图正在生成';
        return;
      }
      const source: image.ImageSource = image.createImageSource(buffer);
      try {
        if (shouldCache) {
          const info: image.ImageInfo = await source.getImageInfo();
          let targetWidth: number = Math.min(info.size.width, 480);
          let targetHeight: number = info.size.width > 0 ?
            Math.max(Math.round(info.size.height * targetWidth / info.size.width), 1) : 720;
          if (targetHeight > 720) {
            targetWidth = Math.max(Math.round(targetWidth * 720 / targetHeight), 1);
            targetHeight = 720;
          }
          this.thumbnail = await source.createPixelMap({
            desiredSize: { width: Math.max(targetWidth, 1), height: targetHeight }
          });
        } else {
          this.thumbnail = await source.createPixelMap();
        }
        if (shouldCache) {
          await cache.writeCover(this.archive.id, this.thumbnail);
        }
      } finally {
        await source.release();
      }
    } catch (error) {
      this.thumbnailError = this.describeError(error);
    } finally {
      this.isThumbnailLoading = false;
    }
  }

  private repository(): ServerConfigRepository {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    return new ServerConfigRepository(context);
  }

  private describeError(error: Object): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return '缩略图加载失败';
  }
}
