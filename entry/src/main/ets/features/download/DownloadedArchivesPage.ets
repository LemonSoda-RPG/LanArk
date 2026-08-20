import { common } from '@kit.AbilityKit';
import { OfflineArchiveCache, OfflineArchiveRecord } from '../../data/cache/OfflineArchiveCache';
import { ServerConfigRepository } from '../../data/config/ServerConfigRepository';
import { ArchiveItem, ReaderRouteParams, ServerConfig } from '../../domain/model/LanraragiModels';
import { localized } from '../../common/Localization';

@Component
export struct DownloadedArchivesPage {
  @Consume('pathStack') private pathStack: NavPathStack = new NavPathStack();
  @State private records: Array<OfflineArchiveRecord> = [];
  @State private serverUrl: string = '';

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
                  param: new ReaderRouteParams(record.archive, false)
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
      Column() {
        Text(archive.fileExtension.toUpperCase())
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.extension_text'))
      }
      .width(68)
      .height(92)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius(10)

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
      this.records = new OfflineArchiveCache(context, config.serverUrl).listRecords();
    } catch (error) {
      this.records = [];
    }
  }
}
