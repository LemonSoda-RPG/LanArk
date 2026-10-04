import { common } from '@kit.AbilityKit';
import {
  LibrarySettings,
  LibrarySettingsRepository
} from '../../data/config/LibrarySettingsRepository';
import { ServerConfigRepository } from '../../data/config/ServerConfigRepository';
import { LanraragiApiClient } from '../../data/network/LanraragiApiClient';
import {
  ArchiveItem,
  ReaderRouteParams,
  ServerConfig
} from '../../domain/model/LanraragiModels';
import { localized } from '../../common/Localization';
import { AppLog } from '../../data/log/AppLog';
import { ArchiveGridCard } from './ArchiveGridCard';

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
  // 0 means "work it out from the width", the same way the library grid does;
  // a value set in the library settings overrides it. A hard-coded count made
  // this screen show fewer, larger covers than the library on the same device.
  @State private gridColumns: number = 0;
  @State private contentWidth: number = 0;

  aboutToAppear(): void {
    // The column count comes from the grid's own measured width, which is what
    // the library grid uses, so both screens land on the same count. That width
    // arrives with the first layout; until then the two-column fallback applies,
    // exactly as it does in the library.
    this.load();
  }

  /**
   * Records the grid width, in vp.
   *
   * Area.width from onAreaChange is already in vp. Converting it again divided
   * it by the screen density (2.375 here), which dropped the estimate to a
   * single column and pinned the grid at the two-column fallback.
   */
  private updateContentWidthVp(widthVp: number): void {
    if (widthVp > 0 && Math.abs(widthVp - this.contentWidth) > 0.5) {
      this.contentWidth = widthVp;
    }
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
      this.gridColumns = settings.gridColumns;

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

  /**
   * Tapping a card starts reading it, as tapping a card in the library does.
   *
   * The archive information page is reached from inside the reader, so opening
   * it directly here would put a step between the tap and the pages.
   */
  private openArchive(archive: ArchiveItem): void {
    this.pathStack.pushPath({
      name: 'ArchiveReader',
      param: new ReaderRouteParams(archive, false)
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

        if (this.loadError.length > 0) {
          Text(this.loadError)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(14)
            .fontColor($r('app.color.error'))
            .width('100%')
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
                ArchiveGridCard({
                  archive: archive,
                  coverCrop: this.coverCrop,
                  serverUrl: this.serverUrl,
                  apiKey: this.apiKey
                })
              }
              .onClick(() => {
                this.openArchive(archive);
              })
            }, (archive: ArchiveItem) => `${archive.id}-${archive.title}`)
          }
          .columnsTemplate(this.gridTemplate())
          .columnsGap(10)
          .rowsGap(10)
          .width('100%')
          .layoutWeight(1)
          .padding({ bottom: 24 })
          .scrollBar(BarState.Off)
          .onAreaChange((oldValue: Area, newValue: Area) => {
            // Already in vp, and the horizontal padding now sits on the container
            // above, as it does in the library, so this is the width the columns
            // are actually laid out in.
            if (typeof newValue.width === 'number' && newValue.width > 0) {
              this.updateContentWidthVp(newValue.width);
              AppLog.info('random',
                `grid ${newValue.width}vp, columns=${this.effectiveGridColumns()}`);
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 6 })
      .backgroundColor($r('app.color.page_background'))
    }
    .title(localized('随机档案'))
    .backgroundColor($r('app.color.page_background'))
  }

  /**
   * Columns to show, matching the library grid.
   *
   * A count set in the library settings wins; otherwise it is derived from the
   * width with the same minimum card width and gap the library uses, so a card
   * here is the same size as a card there.
   */
  private effectiveGridColumns(): number {
    if (this.gridColumns > 0) {
      return this.gridColumns;
    }
    const minimumCardWidth: number = 160;
    const gap: number = 10;
    const estimated: number = Math.floor((this.contentWidth + gap) /
      (minimumCardWidth + gap));
    return Math.min(Math.max(estimated, 2), 6);
  }

  private gridTemplate(): string {
    const columns: number = this.effectiveGridColumns();
    return `${'1fr '.repeat(columns)}`.trim();
  }
}
