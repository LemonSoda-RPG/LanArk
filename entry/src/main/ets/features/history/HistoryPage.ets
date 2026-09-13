import { common } from '@kit.AbilityKit';
import { ServerConfigRepository } from '../../data/config/ServerConfigRepository';
import { LibrarySettings, LibrarySettingsRepository } from '../../data/config/LibrarySettingsRepository';
import { ArchiveItem, ReaderRouteParams, ServerConfig } from '../../domain/model/LanraragiModels';
import { ArchiveCoverView } from '../library/ArchiveCoverView';
import { localized } from '../../common/Localization';

const SECONDS_PER_MINUTE: number = 60;
const SECONDS_PER_HOUR: number = 3600;
const MILLISECONDS_PER_DAY: number = 86_400_000;
// Same card sizing rule as the library grid, so both screens pick the same
// number of columns on the same device.
const MINIMUM_CARD_WIDTH_VP: number = 160;
const CARD_GAP_VP: number = 10;

class HistoryDataSource implements IDataSource {
  private entries: Array<ArchiveItem> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.entries.length;
  }

  getData(index: number): ArchiveItem {
    return this.entries[index];
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

  replace(entries: Array<ArchiveItem>): void {
    this.entries = entries;
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }
}

@Component
struct HistoryGridCard {
  @ObjectLink archive: ArchiveItem;
  serverUrl: string = '';
  apiKey: string = '';

  build() {
    Column({ space: 6 }) {
      Stack() {
        ArchiveCoverView({
          archiveId: this.archive.id,
          fileExtension: this.archive.fileExtension,
          serverUrl: this.serverUrl,
          apiKey: this.apiKey,
          coverWidth: '100%',
          coverHeight: '100%'
        })
      }
      .width('100%')
      .aspectRatio(0.75)

      // The texts opt out of hit testing so the whole card stays clickable.
      // A `Text` with `copyOption` otherwise keeps the tap for itself and the
      // GridItem's onClick never runs.
      Text(this.archive.title)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .hitTestBehavior(HitTestMode.None)

      Text(describeReadTime(this.archive.lastReadTime))
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor($r('app.color.accent_text'))
        .width('100%')
        .hitTestBehavior(HitTestMode.None)

      Text(`${this.archive.pageCount} ${localized('页', 'pages')} · ${this.archive.progressText}`)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding(10)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
    .border({ width: 1, color: $r('app.color.divider') })
  }
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

function sameCalendarDay(left: Date, right: Date): boolean {
  return left.getFullYear() === right.getFullYear() &&
    left.getMonth() === right.getMonth() &&
    left.getDate() === right.getDate();
}

/** Human-readable age of a read time, precise for today and coarse beyond it. */
function describeReadTime(timestampSeconds: number): string {
  if (!Number.isFinite(timestampSeconds) || timestampSeconds <= 0) {
    return localized('未读');
  }
  const nowMs: number = Date.now();
  const readMs: number = timestampSeconds * 1000;
  const elapsed: number = Math.floor((nowMs - readMs) / 1000);
  // A server clock ahead of the device must not render as a negative age.
  if (elapsed < SECONDS_PER_MINUTE) {
    return localized('刚刚');
  }
  if (elapsed < SECONDS_PER_HOUR) {
    return `${Math.floor(elapsed / SECONDS_PER_MINUTE)} ${localized('分钟前')}`;
  }
  const read: Date = new Date(readMs);
  const clock: string = `${pad2(read.getHours())}:${pad2(read.getMinutes())}`;
  if (sameCalendarDay(read, new Date(nowMs))) {
    return `${localized('今天')} ${clock}`;
  }
  if (sameCalendarDay(read, new Date(nowMs - MILLISECONDS_PER_DAY))) {
    return `${localized('昨天')} ${clock}`;
  }
  if (read.getFullYear() === new Date(nowMs).getFullYear()) {
    return `${read.getMonth() + 1}${localized('月', '/')}${read.getDate()}${localized('日', '')}`;
  }
  return `${read.getFullYear()}-${pad2(read.getMonth() + 1)}-${pad2(read.getDate())}`;
}

/**
 * Reading history: every archive that was opened, most recent first.
 *
 * History is derived from the library index instead of a dedicated request:
 * `/api/archives` already reports `lastreadtime` for each archive, so this page
 * needs no endpoint of its own and keeps working when the server does not track
 * reading progress itself (the value is then bumped locally while reading).
 */
@Component
export struct HistoryPage {
  @Consume('pathStack') private pathStack: NavPathStack = new NavPathStack();
  // Supplied by the library so this page always reads the live archive
  // instances; an archive deleted meanwhile is therefore never listed.
  archivesProvider: () => Array<ArchiveItem> = (): Array<ArchiveItem> => [];
  @State private entries: Array<ArchiveItem> = [];
  @State private onlyReading: boolean = false;
  @State private serverUrl: string = '';
  @State private apiKey: string = '';
  // The grid is built only once the server address is known. A cover view
  // created with an empty address gives up immediately and is never retried,
  // which used to leave the whole page without covers until a scroll recycled
  // the rows.
  @State private configReady: boolean = false;
  // The library's fixed column setting, when the user picked one; 0 means the
  // width-based rule below decides, exactly as it does on the library page.
  @State private preferredColumns: number = 0;
  @State private gridColumns: number = 0;
  private gridContentWidth: number = 0;
  private dataSource: HistoryDataSource = new HistoryDataSource();

  aboutToAppear(): void {
    this.loadLocalPreferences();
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

          Text(localized('观看历史'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Button(localized(this.onlyReading ? '全部历史' : '仅看在读'))
            .height(38)
            .fontSize(13)
            .fontColor($r('app.color.accent_text'))
            .backgroundColor($r('app.color.accent_soft'))
            .borderRadius(19)
            .accessibilityText(localized(this.onlyReading ? '显示全部历史' : '只显示正在阅读的档案'))
            .onClick(() => {
              this.onlyReading = !this.onlyReading;
              this.rebuild();
            })
        }
        .width('100%')
        .height(48)

        if (!this.configReady) {
          Column() {
            LoadingProgress()
              .width(32)
              .height(32)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.entries.length === 0) {
          Column({ space: 10 }) {
            Text(localized(this.onlyReading ? '没有正在阅读的档案' : '还没有阅读记录'))
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
            Text(localized('打开档案开始阅读后，这里会按最近阅读时间排序。'))
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
          Grid() {
            // Only visible cards are built: each one decodes a cover.
            LazyForEach(this.dataSource, (archive: ArchiveItem) => {
              GridItem() {
                HistoryGridCard({
                  archive: archive,
                  serverUrl: this.serverUrl,
                  apiKey: this.apiKey
                })
              }
              .onClick(() => {
                this.openReader(archive);
              })
            }, (archive: ArchiveItem) => `history-${archive.id}`)
          }
          .columnsTemplate(this.columnsTemplate())
          .columnsGap(CARD_GAP_VP)
          .rowsGap(CARD_GAP_VP)
          .cachedCount(6)
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .onAreaChange((oldValue: Area, newValue: Area) => {
            // `Area.width` is already in vp, so it is used as-is here.
            if (typeof newValue.width === 'number' && newValue.width > 0 &&
              Math.abs(newValue.width - this.gridContentWidth) > 0.5) {
              this.gridContentWidth = newValue.width;
              this.gridColumns = this.effectiveGridColumns(newValue.width);
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      // Horizontal insets sit on the container, not on the Grid: a padded Grid
      // reports the narrower content width and would pick fewer columns than
      // the library grid, which is laid out the same way.
      .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      .constraintSize({ maxWidth: 1400 })
      .backgroundColor($r('app.color.page_background'))
    }
    .hideTitleBar(true)
    // Re-sorting here covers both the first display and the return from the
    // reader, where the archive that was just read moved to the front.
    .onShown(() => {
      this.rebuild();
    })
    .backgroundColor($r('app.color.page_background'))
  }

  private async loadLocalPreferences(): Promise<void> {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const config: ServerConfig = await new ServerConfigRepository(context).load();
      this.serverUrl = config.serverUrl;
      this.apiKey = config.apiKey;
    } catch (error) {
      // Covers stay placeholders when the saved server cannot be read.
    }
    try {
      const settings: LibrarySettings = await new LibrarySettingsRepository(context).load();
      this.preferredColumns = settings.gridColumns;
    } catch (error) {
      // Fall back to the width-based column count.
    }
    if (this.preferredColumns > 0) {
      // A fixed column count needs no measurement.
      this.gridColumns = this.preferredColumns;
    }
    this.configReady = true;
  }

  private effectiveGridColumns(widthVp: number): number {
    if (this.preferredColumns > 0) {
      return this.preferredColumns;
    }
    const estimated: number = Math.floor((widthVp + CARD_GAP_VP) /
      (MINIMUM_CARD_WIDTH_VP + CARD_GAP_VP));
    return Math.min(Math.max(estimated, 2), 6);
  }

  private columnsTemplate(): string {
    const columns: number = this.gridColumns > 0 ? this.gridColumns : 3;
    return `${'1fr '.repeat(columns)}`.trim();
  }

  /** Re-filters and re-sorts the list against the current archive state. */
  private rebuild(): void {
    const all: Array<ArchiveItem> = this.archivesProvider();
    const selected: Array<ArchiveItem> = all.filter((archive: ArchiveItem) => {
      if (archive.lastReadTime <= 0) {
        return false;
      }
      // "In progress" means started but not finished; a fully read archive is
      // still part of the full history.
      return !this.onlyReading || archive.readingState === 1;
    });
    selected.sort((left: ArchiveItem, right: ArchiveItem) => {
      return right.lastReadTime - left.lastReadTime;
    });
    this.entries = selected;
    this.dataSource.replace(selected);
  }

  private openReader(archive: ArchiveItem): void {
    this.pathStack.pushPath({
      name: 'ArchiveReader',
      param: new ReaderRouteParams(archive, false)
    });
  }
}
