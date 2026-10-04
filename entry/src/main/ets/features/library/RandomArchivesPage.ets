import { common } from '@kit.AbilityKit';
import {
  LibrarySettings,
  LibrarySettingsRepository
} from '../../data/config/LibrarySettingsRepository';
import { ServerConfigRepository } from '../../data/config/ServerConfigRepository';
import { LanraragiApiClient } from '../../data/network/LanraragiApiClient';
import {
  ArchiveInfoRouteParams,
  ArchiveItem,
  ServerConfig
} from '../../domain/model/LanraragiModels';
import { localized } from '../../common/Localization';
import { AppLog } from '../../data/log/AppLog';
import { ArchiveCoverView } from '../library/ArchiveCoverView';

/**
 * A fresh random sample of the library, redrawn on demand.
 *
 * Picked by the server out of the whole search result rather than out of a
 * loaded page, so it can surface an archive the library grid has never scrolled
 * to. Meant for the "what should I read" case, which is why drawing again is the
 * primary action.
 */
@Component
export struct RandomArchivesPage {
  @Consume('pathStack') private pathStack: NavPathStack = new NavPathStack();
  @State private archives: Array<ArchiveItem> = [];
  @State private isLoading: boolean = false;
  @State private loadError: string = '';
  @State private coverCrop: boolean = true;
  private serverUrl: string = '';
  private apiKey: string = '';
  // How many to draw each time. Twenty fills a screen or two on a phone without
  // making the draw itself slow.
  private drawCount: number = 20;
  // Three columns: a browsing screen, so covers stay big enough to recognise.
  private readonly gridColumns: number = 3;

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    this.loadError = '';
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const config: ServerConfig = await new ServerConfigRepository(context).load();
      this.serverUrl = config.serverUrl;
      this.apiKey = config.apiKey;
      const settings: LibrarySettings = await new LibrarySettingsRepository(context).load();
      this.coverCrop = settings.coverCrop;

      if (this.serverUrl.length === 0) {
        this.loadError = localized('请先在设置中配置服务器');
        return;
      }
      const client: LanraragiApiClient = new LanraragiApiClient(this.serverUrl, this.apiKey);
      this.archives = await client.fetchRandomArchives(this.drawCount, '', '');
      AppLog.info('random', `drew ${this.archives.length} archives`);
    } catch (error) {
      this.loadError = localized('随机档案加载失败');
      AppLog.error('random', `draw failed: ${AppLog.describe(error)}`);
    } finally {
      this.isLoading = false;
    }
  }

  /** Opening the card shows the same archive page the library grid opens. */
  private openArchive(archive: ArchiveItem): void {
    this.pathStack.pushPath({
      name: 'ArchiveInfo',
      param: new ArchiveInfoRouteParams(archive, false)
    });
  }

  build() {
    NavDestination() {
      Column({ space: 12 }) {
        Row({ space: 10 }) {
          Text(`${this.archives.length} ${localized('本', 'archives')}`)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
            .layoutWeight(1)

          Button() {
            Image($r('app.media.icon_refresh'))
              .width(19)
              .height(19)
              .renderMode(ImageRenderMode.Template)
              .fillColor($r('app.color.accent_text'))
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .enabled(!this.isLoading)
          .backgroundColor($r('app.color.accent_soft'))
          .accessibilityText(localized('换一批'))
          .onClick(() => {
            this.load();
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        if (this.loadError.length > 0) {
          Text(this.loadError)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(14)
            .fontColor($r('app.color.error'))
            .width('100%')
            .padding({ left: 16, right: 16 })
        }

        if (this.isLoading && this.archives.length === 0) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(32)
              .height(32)
            Text(localized('正在抽取…'))
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Grid() {
            ForEach(this.archives, (archive: ArchiveItem) => {
              GridItem() {
                Column({ space: 6 }) {
                  ArchiveCoverView({
                    archiveId: archive.id,
                    fileExtension: archive.fileExtension,
                    serverUrl: this.serverUrl,
                    apiKey: this.apiKey,
                    coverWidth: '100%',
                    coverHeight: 168,
                    cropCover: this.coverCrop
                  })

                  Text(archive.title)
                    .copyOption(CopyOptions.LocalDevice)
                    .fontSize(12)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .fontColor($r('app.color.text_primary'))
                    .width('100%')
                }
                .width('100%')
                .accessibilityText(archive.title)
                .onClick(() => {
                  this.openArchive(archive);
                })
              }
            }, (archive: ArchiveItem) => `${archive.id}-${archive.title}`)
          }
          .columnsTemplate(this.gridTemplate())
          .columnsGap(12)
          .rowsGap(14)
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, bottom: 24 })
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: 6 })
      .backgroundColor($r('app.color.page_background'))
    }
    .title(localized('随机档案'))
    .backgroundColor($r('app.color.page_background'))
  }

  private gridTemplate(): string {
    return `repeat(${this.gridColumns}, 1fr)`;
  }
}
