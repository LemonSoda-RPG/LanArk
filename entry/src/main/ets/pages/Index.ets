import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { ImageDiskCache } from '../data/cache/ImageDiskCache';
import {
  CachedLibraryIndex,
  LibraryIndexCacheRepository
} from '../data/cache/LibraryIndexCacheRepository';
import {
  LibrarySettings,
  LibrarySettingsRepository
} from '../data/config/LibrarySettingsRepository';
import { ServerConfigRepository } from '../data/config/ServerConfigRepository';
import { LanraragiApiClient } from '../data/network/LanraragiApiClient';
import {
  ArchiveIndexPageResult,
  ArchiveInfoRouteParams,
  ArchiveItem,
  CategoryItem,
  ReaderRouteParams,
  ServerConfig,
  ServerInfo
} from '../domain/model/LanraragiModels';
import { ArchiveReaderPage } from '../features/reader/ArchiveReaderPage';
import { ArchiveInfoPage } from '../features/archive/ArchiveInfoPage';
import { SettingsPage } from '../features/settings/SettingsPage';
import { LogPage } from '../features/settings/LogPage';
import { DownloadedArchivesPage } from '../features/download/DownloadedArchivesPage';
import { DownloadManagerPage } from '../features/download/DownloadManagerPage';
import { HistoryPage } from '../features/history/HistoryPage';
import { LibraryProgressOverlayRepository } from '../data/cache/LibraryProgressOverlayRepository';
import { ArchiveCoverView } from '../features/library/ArchiveCoverView';
import { RandomArchivesPage } from '../features/library/RandomArchivesPage';
import { AppLog } from '../data/log/AppLog';
import { describeUserFacingError, localized } from '../common/Localization';

class ArchiveDataSource implements IDataSource {
  private items: Array<ArchiveItem> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ArchiveItem {
    return this.items[index];
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

  replace(items: Array<ArchiveItem>): void {
    this.items = items;
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }

  /**
   * Adds a page without rebuilding the list.
   *
   * Lazy loading appends one page at a time; reloading per page would discard
   * and recreate every visible row, and the list would jump back to the top
   * while the user is reading it.
   */
  append(more: Array<ArchiveItem>): void {
    if (more.length === 0) {
      return;
    }
    const first: number = this.items.length;
    for (let index: number = 0; index < more.length; index += 1) {
      this.items.push(more[index]);
    }
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataAdded(first);
    });
  }

  updateProgress(archiveId: string, pageNumber: number): ArchiveItem | undefined {
    const index: number = this.items.findIndex((archive: ArchiveItem) => {
      return archive.id === archiveId;
    });
    if (index < 0) {
      return undefined;
    }
    const updated: ArchiveItem = this.items[index];
    updated.setProgress(pageNumber);
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataChange(index);
    });
    return updated;
  }
}

@Component
struct ArchiveProgressText {
  @ObjectLink archive: ArchiveItem;
  fontSize: number = 11;

  build() {
    Text(`${this.archive.pageCount} ${localized('页', 'pages')} · ${this.archive.progressText}`)
      .copyOption(CopyOptions.LocalDevice)
      .fontSize(this.fontSize)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .hitTestBehavior(HitTestMode.None)
  }
}

@Component
struct ArchiveNewBadge {
  @ObjectLink archive: ArchiveItem;
  marginTop: number = 0;
  marginRight: number = 0;

  build() {
    if (this.archive.displayAsNew) {
      Text('NEW')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .padding({ left: 6, right: 6, top: 3, bottom: 3 })
        .backgroundColor($r('app.color.new_badge'))
        .borderRadius(6)
        .margin({ top: this.marginTop, right: this.marginRight })
        .hitTestBehavior(HitTestMode.None)
    }
  }
}

@Entry
@Component
struct Index {
  @Provide('pathStack') private pathStack: NavPathStack = new NavPathStack();
  @State private serverUrl: string = '';
  @State private apiKey: string = '';
  @State private isLoading: boolean = false;
  @State private errorMessage: string = '';
  @State private isLibraryLoading: boolean = false;
  // A startup refresh runs without hiding the cached library, so it needs its
  // own flag: the page keeps showing content while this is true.
  @State private isLibraryRefreshing: boolean = false;
  @State private libraryError: string = '';
  // Non-blocking hint shown above the grid, e.g. when a background refresh
  // failed and the library on screen is the cached one.
  @State private libraryNotice: string = '';
  @State private searchText: string = '';
  @State private isSearchMode: boolean = false;
  @State private isCategoryPopupVisible: boolean = false;
  @State private isSortPopupVisible: boolean = false;
  @State private visibleArchiveCount: number = 0;
  @State private categories: Array<CategoryItem> = [];
  @State private selectedCategoryId: string = '';
  @State private selectedCategoryName: string = '全部';
  @State private sortModeIndex: number = 0;
  @State private sortAscending: boolean = false;
  @State private hideCompleted: boolean = false;
  @State private gridLayout: boolean = true;
  @State private gridColumns: number = 0;
  // Whether covers fill their card or are shown whole (library setting).
  @State private coverCrop: boolean = true;
  @State private libraryContentWidth: number = 0;
  private allArchives: Array<ArchiveItem> = [];
  private completeArchiveIndex: Array<ArchiveItem> = [];
  private archiveDataSource: ArchiveDataSource = new ArchiveDataSource();
  private progressPersistTimer: number = -1;
  private searchDebounceTimer: number = -1;
  // Progress changed since the index was last written in full. Kept small on
  // purpose: rewriting the whole index per page turn serialised every archive
  // (tags included) and wrote it synchronously on the UI thread.
  private pendingProgress: Record<string, number> = {};
  // Read times bumped locally since the index was last written in full, kept in
  // the same overlay as `pendingProgress` so the history order survives a
  // restart before the next refresh reports the server's own `lastreadtime`.
  private pendingReadTimes: Record<string, number> = {};
  // Lazy loading: the client holds only the pages fetched so far, and asks for
  // the next one when the user reaches the end. Ordering, filtering and search
  // are server-side, so a partial list is still a correct answer.
  private loadedCount: number = 0;
  private totalCount: number = 0;
  private isLoadingMore: boolean = false;
  // The server pages by its own `archives_per_page`, so the client asks for that
  // many instead of trying to override it.
  private serverPageSize: number = 0;
  private pendingSortRefresh: number = -1;
  // O(1) progress lookup instead of scanning the library on every page turn.
  private archiveById: Map<string, ArchiveItem> = new Map<string, ArchiveItem>();
  private libraryLandscape: boolean = false;
  private readerFullscreenActive: boolean = false;
  private libraryWindowRequestId: number = 0;

  aboutToAppear(): void {
    this.beginReaderCacheSession();
    this.restoreLibrarySettings();
    this.restoreConfig();
    this.refreshLibraryWindowSize();
  }

  /**
   * Starts this process' reading session and sweeps left-over reader pages.
   *
   * The reader drops the pages of a document when it is closed, so a stale
   * folder only survives a process that was killed while reading, or a build
   * that did not clean up at all. Nothing can be reading this early, and the
   * session identifier makes this run write into a folder of its own, so the
   * sweep can never delete pages of a document opened afterwards.
   */
  private beginReaderCacheSession(): void {
    AppLog.info('index', 'library page appeared');
    try {
      AppStorage.setOrCreate(
        'lanarkReaderCacheSession',
        ImageDiskCache.newSessionToken()
      );
    } catch (error) {
      // Without an identifier a reader falls back to the shared folder; the
      // mtime guard in the cache still keeps a cleanup away from new pages.
    }
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      new ImageDiskCache(context, this.serverUrl).clearReaderRootAsync().catch(() => {});
    } catch (error) {
      // Stale pages only cost disk space; reading must not wait for them.
    }
  }

  onBackPress(): boolean {
    if (this.isSearchMode) {
      this.exitSearchMode();
      return true;
    }
    return false;
  }

  build() {
    Navigation(this.pathStack) {
      Stack() {
        this.connectedPage()
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .mode(NavigationMode.Stack)
    .title('LanArk')
    .titleMode(NavigationTitleMode.Mini)
    .hideTitleBar(true)
    .hideBackButton(true)
    .navDestination(this.pageRouter)
    .width('100%')
    .height('100%')
    .onAreaChange((oldValue: Area, newValue: Area) => {
      if (typeof newValue.width === 'number' && newValue.width > 0 &&
        typeof newValue.height === 'number' && newValue.height > 0) {
        this.libraryLandscape = newValue.width > newValue.height;
        this.applyLibraryWindowBars();
      }
    })
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private pageRouter(name: string, param: Object) {
    if (name === 'ArchiveReader') {
      ArchiveReaderPage({
        params: param as ReaderRouteParams,
        onProgressChanged: (archiveId: string, pageNumber: number): void => {
          this.updateArchiveProgress(archiveId, pageNumber);
        },
        onReaderFullscreenChanged: (active: boolean): void => {
          this.readerFullscreenActive = active;
          if (!active) {
            this.applyLibraryWindowBars();
          }
        }
      })
    } else if (name === 'ArchiveInfo') {
      ArchiveInfoPage({
        archive: this.archiveInfoParams(param).archive,
        offline: this.archiveInfoParams(param).offline,
        offlineServerUrl: this.archiveInfoParams(param).offlineServerUrl,
        onTagSelected: (tag: string): void => {
          this.openSearchForTag(tag);
        },
        onArchiveDeleted: (archiveId: string): void => {
          this.removeDeletedArchive(archiveId);
        },
        onLocalDownloadDeleted: (archiveId: string): void => {
          this.pathStack.clear();
          this.pathStack.pushPath({
            name: 'DownloadedArchives',
            param: new Object()
          });
        }
      })
    } else if (name === 'Settings') {
      SettingsPage({
        onServerSaved: (config: ServerConfig): void => {
          this.applyServerConfig(config);
        },
        onServerCleared: (): void => {
          this.applyClearedServerConfig();
        },
        onLibrarySettingsSaved: (settings: LibrarySettings): void => {
          this.applyLibrarySettings(settings);
        }
      })
    } else if (name === 'DownloadedArchives') {
      DownloadedArchivesPage()
    } else if (name === 'RandomArchives') {
      RandomArchivesPage()
    } else if (name === 'DownloadManager') {
      DownloadManagerPage()
    } else if (name === 'DiagnosticLog') {
      LogPage()
    } else if (name === 'History') {
      HistoryPage({
        // A provider rather than a snapshot: the page re-reads the list every
        // time it is shown, so it never renders archives removed meanwhile.
        archivesProvider: (): Array<ArchiveItem> => {
          return this.completeArchiveIndex;
        }
      })
    } else {
      // An unregistered route name would otherwise render an empty destination
      // with no indication of what went wrong.
      Column() {
        Text(localized('无法打开该页面'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.page_background'))
    }
  }

  private archiveInfoParams(param: Object): ArchiveInfoRouteParams {
    return param instanceof ArchiveInfoRouteParams ?
      param : new ArchiveInfoRouteParams(param as ArchiveItem);
  }

  @Builder
  private connectedPage() {
    Column({ space: 8 }) {
      if (this.isSearchMode) {
        Row({ space: 8 }) {
          Button() {
            Image($r('app.media.icon_chevron_left'))
              .width(20)
              .height(20)
              .renderMode(ImageRenderMode.Template)
              .fillColor($r('app.color.text_primary'))
          }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor($r('app.color.surface'))
            .border({ width: 1, color: $r('app.color.divider') })
            .accessibilityText(localized('退出搜索'))
            .onClick(() => {
              this.exitSearchMode();
            })

          Row({ space: 6 }) {
            Image($r('app.media.icon_search'))
              .width(18)
              .height(18)
              .renderMode(ImageRenderMode.Template)
              .fillColor($r('app.color.text_tertiary'))

            TextInput({
              placeholder: $r('app.string.search_placeholder'),
              text: this.searchText
            })
              .defaultFocus(true)
              .type(InputType.Normal)
              .enterKeyType(EnterKeyType.Search)
              .fontColor($r('app.color.text_primary'))
              .placeholderColor($r('app.color.text_tertiary'))
              .backgroundColor(Color.Transparent)
              .layoutWeight(1)
              .onChange((value: string) => {
                this.searchText = value;
                this.scheduleArchiveFilter();
              })
          }
          .height(40)
          .padding({ left: 12, right: 8 })
          .layoutWeight(1)
          .backgroundColor($r('app.color.surface'))
          .border({ width: 1, color: $r('app.color.divider') })
          .borderRadius(20)
        }
        .width('100%')
      } else {
        Row({ space: 8 }) {
          Text(`${this.selectedCategoryId.length === 0 ? localized('全部') : this.selectedCategoryName} · ${this.visibleArchiveCount}`)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (this.isLibraryRefreshing) {
            LoadingProgress()
              .width(18)
              .height(18)
              .accessibilityText(localized('正在刷新档案库'))
          }

          Button() {
            Image($r('app.media.icon_search'))
              .width(19)
              .height(19)
              .renderMode(ImageRenderMode.Template)
              .fillColor($r('app.color.text_secondary'))
          }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor($r('app.color.surface'))
            .border({ width: 1, color: $r('app.color.divider') })
            .accessibilityText(localized('搜索档案'))
            .onClick(() => {
              this.enterSearchMode();
            })

          Button() {
            Image($r('app.media.icon_history'))
              .width(19)
              .height(19)
              .renderMode(ImageRenderMode.Template)
              .fillColor($r('app.color.text_secondary'))
          }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor($r('app.color.surface'))
            .border({ width: 1, color: $r('app.color.divider') })
            .accessibilityText(localized('观看历史'))
            .onClick(() => {
              this.pathStack.pushPath({
                name: 'History',
                param: new Object()
              });
            })

          Button() {
            Image($r('app.media.icon_category'))
              .width(19)
              .height(19)
              .renderMode(ImageRenderMode.Template)
              .fillColor(this.selectedCategoryId.length > 0 ?
                $r('app.color.accent_text') : $r('app.color.text_secondary'))
          }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor(this.selectedCategoryId.length > 0 ?
              $r('app.color.accent_soft') : $r('app.color.surface'))
            .border({ width: 1, color: $r('app.color.divider') })
            .accessibilityText(`${localized('选择分类')}，${localized('当前为', 'current')}: ${this.selectedCategoryName}`)
            .onClick(() => {
              this.isSortPopupVisible = false;
              this.isCategoryPopupVisible = !this.isCategoryPopupVisible;
            })
            .bindPopup(this.isCategoryPopupVisible, {
              builder: this.categoryPopup,
              placement: Placement.BottomRight,
              popupColor: $r('app.color.surface'),
              enableArrow: true,
              autoCancel: true,
              onStateChange: (event: PopupStateChangeParam) => {
                this.isCategoryPopupVisible = event.isVisible;
              }
            })

          Button() {
            Image($r('app.media.icon_random'))
              .width(19)
              .height(19)
              .renderMode(ImageRenderMode.Template)
              .fillColor($r('app.color.accent_text'))
          }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor($r('app.color.accent_soft'))
            .accessibilityText(localized('随机档案'))
            .onClick(() => {
              this.pathStack.pushPath({
                name: 'RandomArchives',
                param: new Object()
              });
            })

          Button() {
            Image($r('app.media.icon_sort'))
              .width(19)
              .height(19)
              .renderMode(ImageRenderMode.Template)
              .fillColor($r('app.color.accent_text'))
          }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor($r('app.color.accent_soft'))
            .accessibilityText(`${localized('排序')}，${localized('当前为', 'current')}: ${this.sortModeLabel()}, ${localized(this.sortAscending ? '升序' : '降序')}`)
            .onClick(() => {
              this.isCategoryPopupVisible = false;
              this.isSortPopupVisible = !this.isSortPopupVisible;
            })
            .bindPopup(this.isSortPopupVisible, {
              builder: this.sortPopup,
              placement: Placement.BottomRight,
              popupColor: $r('app.color.surface'),
              enableArrow: true,
              autoCancel: true,
              onStateChange: (event: PopupStateChangeParam) => {
                this.isSortPopupVisible = event.isVisible;
              }
            })

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
            .enabled(!this.isLibraryLoading && !this.isLibraryRefreshing)
            .backgroundColor($r('app.color.accent_soft'))
            .accessibilityText(localized('刷新档案库'))
            .onClick(() => {
              this.reloadLibrary();
            })

          Button() {
            Image($r('app.media.icon_settings'))
              .width(19)
              .height(19)
              .renderMode(ImageRenderMode.Template)
              .fillColor($r('app.color.text_secondary'))
          }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor($r('app.color.surface'))
            .border({ width: 1, color: $r('app.color.divider') })
            .accessibilityText(localized('应用设置'))
            .onClick(() => {
              this.pathStack.pushPath({
                name: 'Settings',
                param: new Object()
              });
            })

          Button() {
            Image($r('app.media.icon_download'))
              .width(19)
              .height(19)
              .renderMode(ImageRenderMode.Template)
              .fillColor($r('app.color.text_secondary'))
          }
            .width(40)
            .height(40)
            .borderRadius(20)
            .backgroundColor($r('app.color.surface'))
            .border({ width: 1, color: $r('app.color.divider') })
            .accessibilityText(localized('已下载'))
            .onClick(() => {
              this.pathStack.pushPath({
                name: 'DownloadedArchives',
                param: new Object()
              });
            })
        }
        .width('100%')
      }

      if (this.libraryNotice.length > 0) {
        Text(this.libraryNotice)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius(10)
      }

      if (this.isLibraryLoading) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(32)
            .height(32)
          Text($r('app.string.loading_library'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .layoutWeight(1)
      } else if (this.libraryError.length > 0) {
        Text(this.libraryError)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(14)
          .fontColor($r('app.color.error'))
          .width('100%')
          .padding(14)
          .backgroundColor($r('app.color.error_soft'))
          .borderRadius(12)
          .layoutWeight(1)
      } else if (this.visibleArchiveCount === 0) {
        Text($r('app.string.empty_library'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(15)
          .fontColor($r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .layoutWeight(1)
      } else {
        if (this.gridLayout) {
          Grid() {
            LazyForEach(this.archiveDataSource, (archive: ArchiveItem) => {
              GridItem() {
                this.archiveGridCard(archive)
              }
              .onClick(() => {
                this.openArchiveReader(archive);
              })
            }, (archive: ArchiveItem) => `grid-${archive.id}`)
          }
          .columnsTemplate(this.gridColumnsTemplate())
          .columnsGap(10)
          .rowsGap(10)
          .width('100%')
          .layoutWeight(1)
          .cachedCount(6)
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Auto)
          .onReachEnd(() => {
            this.loadNextPage();
          })
          .onAreaChange((oldValue: Area, newValue: Area) => {
            if (typeof newValue.width === 'number' && newValue.width > 0) {
              this.updateLibraryContentWidthVp(newValue.width);
            }
          })
        } else {
          List({ space: 10 }) {
            LazyForEach(this.archiveDataSource, (archive: ArchiveItem) => {
              ListItem() {
                this.archiveRow(archive)
              }
              .onClick(() => {
                this.openArchiveReader(archive);
              })
            }, (archive: ArchiveItem) => archive.id)
          }
          .width('100%')
          .layoutWeight(1)
          .cachedCount(8)
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Auto)
          .onReachEnd(() => {
            this.loadNextPage();
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: 1400 })
    .padding({ left: 16, right: 16, top: 8, bottom: 12 })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private categoryPopup() {
    Column({ space: 4 }) {
      Text(localized('分类'))
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })

      List({ space: 2 }) {
        ListItem() {
          this.categoryPopupOption(localized('全部'), '')
        }
        ForEach(this.categories, (category: CategoryItem) => {
          ListItem() {
            this.categoryPopupOption(category.name, category.id)
          }
        }, (category: CategoryItem) => `category-popup-${category.id}`)
      }
      .width('100%')
      .height(Math.min((this.categories.length + 1) * 44, 352))
      .scrollBar(BarState.Auto)
    }
    .width(248)
    .padding(8)
  }

  @Builder
  private categoryPopupOption(label: string, categoryId: string) {
    Row({ space: 8 }) {
      Text(label)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(15)
        .fontColor(this.selectedCategoryId === categoryId ?
          $r('app.color.accent_text') : $r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .hitTestBehavior(HitTestMode.None)
      if (this.selectedCategoryId === categoryId) {
        Text('✓')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.accent'))
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height(42)
    .padding({ left: 10, right: 10 })
    .borderRadius(10)
    .backgroundColor(this.selectedCategoryId === categoryId ?
      $r('app.color.accent_soft') : Color.Transparent)
    .accessibilityText(label)
    .accessibilityChecked(this.selectedCategoryId === categoryId)
    .onClick(() => {
      this.isCategoryPopupVisible = false;
      this.selectCategory(categoryId, label);
    })
  }

  @Builder
  private sortPopup() {
    Column({ space: 6 }) {
      Row() {
        Text(localized('排序方式'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(localized(this.sortAscending ? '升序' : '降序'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 6, bottom: 4 })

      List({ space: 2 }) {
        ForEach(this.sortModeLabels(), (label: string, index: number) => {
          ListItem() {
            this.sortPopupOption(label, index)
          }
        }, (label: string, index: number) => `sort-popup-${index}-${label}`)
      }
      .width('100%')
      .height(308)
      .scrollBar(BarState.Auto)

      Row({ space: 8 }) {
        Button(`${localized('升序')} ↑`)
          .height(38)
          .fontSize(14)
          .fontColor(this.sortAscending ? Color.White : $r('app.color.accent_text'))
          .backgroundColor(this.sortAscending ?
            $r('app.color.accent') : $r('app.color.accent_soft'))
          .layoutWeight(1)
          .onClick(() => {
            this.applySortDirection(true);
          })
        Button(`${localized('降序')} ↓`)
          .height(38)
          .fontSize(14)
          .fontColor(this.sortAscending ? $r('app.color.accent_text') : Color.White)
          .backgroundColor(this.sortAscending ?
            $r('app.color.accent_soft') : $r('app.color.accent'))
          .layoutWeight(1)
          .onClick(() => {
            this.applySortDirection(false);
          })
      }
      .width('100%')
    }
    .width(248)
    .padding(8)
  }

  @Builder
  private sortPopupOption(label: string, index: number) {
    Row({ space: 8 }) {
      Text(label)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(15)
        .fontColor(this.sortModeIndex === index ?
          $r('app.color.accent_text') : $r('app.color.text_primary'))
        .layoutWeight(1)
        .hitTestBehavior(HitTestMode.None)
      if (this.sortModeIndex === index) {
        Text('✓')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.accent'))
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height(42)
    .padding({ left: 10, right: 10 })
    .borderRadius(10)
    .backgroundColor(this.sortModeIndex === index ?
      $r('app.color.accent_soft') : Color.Transparent)
    .accessibilityText(label)
    .accessibilityChecked(this.sortModeIndex === index)
    .onClick(() => {
      this.sortModeIndex = index;
      // Newest first for the date sort, A-Z for the rest; the user can flip it.
      this.sortAscending = index !== 0;
      this.isSortPopupVisible = false;
      this.saveLibrarySettings();
      // The order is the server's, so changing it means fetching again from the
      // first page rather than reordering what happens to be loaded.
      this.reloadLibrary();
    })
  }

  @Builder
  private archiveRow(archive: ArchiveItem) {
    Row({ space: 14 }) {
      ArchiveCoverView({
        archiveId: archive.id,
        fileExtension: archive.fileExtension,
        serverUrl: this.serverUrl,
        apiKey: this.apiKey,
        cropCover: this.coverCrop
      })

      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(archive.title)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .onClick(() => {
              this.openArchiveReader(archive);
            })
          ArchiveNewBadge({ archive: archive })
        }
        .width('100%')

        Text(archive.displayTags.length > 0 ?
          archive.displayTags : $r('app.string.no_tags'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .onClick(() => {
            this.openArchiveReader(archive);
          })

        ArchiveProgressText({ archive: archive, fontSize: 12 })

        if (archive.progress > 0 && archive.pageCount > 0) {
          Stack({ alignContent: Alignment.Start }) {
            Row()
              .width('100%')
              .height(4)
              .backgroundColor($r('app.color.surface_muted'))
              .borderRadius(2)
            Row()
              .width(`${Math.min(archive.progressRatio * 100, 100)}%`)
              .height(4)
              .backgroundColor($r('app.color.accent'))
              .borderRadius(2)
          }
          .width('100%')
          .height(4)
        }
      }
      .layoutWeight(1)

      Image($r('app.media.icon_chevron_right'))
        .width(18)
        .height(18)
        .renderMode(ImageRenderMode.Template)
        .fillColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  private archiveGridCard(archive: ArchiveItem) {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        ArchiveCoverView({
          archiveId: archive.id,
          fileExtension: archive.fileExtension,
          serverUrl: this.serverUrl,
          apiKey: this.apiKey,
          coverWidth: '100%',
          coverHeight: '100%',
          cropCover: this.coverCrop
        })
        ArchiveNewBadge({
          archive: archive,
          marginTop: 7,
          marginRight: 7
        })
      }
      .width('100%')
      .aspectRatio(0.75)
      .margin({ bottom: 8 })

      Text(archive.title)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .onClick(() => {
          this.openArchiveReader(archive);
        })

      ArchiveProgressText({ archive: archive, fontSize: 11 })

    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding(10)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  private async restoreConfig(): Promise<void> {
    try {
      const config: ServerConfig = await this.repository().load();
      this.serverUrl = config.serverUrl;
      this.apiKey = config.apiKey;
      if (config.serverUrl.length > 0) {
        this.restoreCachedLibrary(config.serverUrl);
        // The cached index is already usable, so the up-to-date one is fetched
        // in the background instead of making the user wait for the network.
        this.refreshLibraryOnStartup();
      } else {
        this.libraryError = localized('请先在设置中配置服务器，然后点击刷新获取档案索引');
      }
    } catch (error) {
      this.libraryError = localized('请先在设置中配置服务器，然后点击刷新获取档案索引');
    }
  }

  private async connectAndSave(): Promise<void> {
    await this.connect(true);
  }

  private async connect(saveAfterSuccess: boolean): Promise<void> {
    if (this.isLoading) {
      return;
    }
    if (this.serverUrl.trim().length === 0) {
      this.errorMessage = localized('请输入 LANraragi 服务器地址');
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';
    try {
      const normalizedUrl: string =
        LanraragiApiClient.normalizeServerUrl(this.serverUrl);
      const client: LanraragiApiClient =
        new LanraragiApiClient(normalizedUrl, this.apiKey);
      await client.fetchServerInfo();
      if (saveAfterSuccess) {
        await this.repository().save(new ServerConfig(normalizedUrl, this.apiKey));
      }
      this.serverUrl = normalizedUrl;
      await this.loadLibrary(client);
    } catch (error) {
      this.errorMessage = this.describeError(error);
    } finally {
      this.isLoading = false;
    }
  }

  private async reloadLibrary(): Promise<void> {
    if (this.serverUrl.length === 0) {
      this.libraryError = localized('请先在设置中配置服务器');
      return;
    }
    try {
      const client: LanraragiApiClient =
        new LanraragiApiClient(this.serverUrl, this.apiKey);
      await this.loadLibrary(client, false);
    } catch (error) {
      this.libraryError = this.describeError(error);
    }
  }

  /**
   * Fetches the index right after startup, keeping the cached one on screen.
   *
   * The cached index is shown first so the library is usable immediately; the
   * server's copy then replaces it in place. Nothing here waits for the user.
   */
  private async refreshLibraryOnStartup(): Promise<void> {
    if (this.isLibraryRefreshing || this.isLibraryLoading) {
      return;
    }
    this.isLibraryRefreshing = true;
    try {
      const client: LanraragiApiClient =
        new LanraragiApiClient(this.serverUrl, this.apiKey);
      await this.loadLibrary(client, true);
    } finally {
      this.isLibraryRefreshing = false;
    }
  }

  /**
   * Loads the full index.
   *
   * `silent` marks a refresh that runs while the user is already looking at a
   * library: it must not swap the page for the loading state, and a failure must
   * leave the cached content alone instead of replacing it with an error.
   *
   * It also must not clear what is on screen. An explicit refresh used to empty
   * the grid and show the loading screen for the whole request — tens of seconds
   * on a large library — even though a usable list was already there from the
   * cache. Now the list stays readable and clickable throughout: only an empty
   * library shows the loading state, and the new listing is installed in one step
   * when it arrives.
   *
   * The listing is fetched in one request rather than in pages, because the
   * search endpoint caps every page at the server's `archives_per_page` setting
   * and ignores the requested length; on this server that would mean ~90 requests
   * to rebuild the library, which is slower in total than asking once.
   */
  private async loadLibrary(client: LanraragiApiClient, silent: boolean = false,
    resetView: boolean = true): Promise<void> {
    this.libraryNotice = '';
    // A refresh starts the listing over, so the filter state goes back to
    // "everything" here, once, rather than on every page that follows.
    if (resetView) {
      this.selectedCategoryId = '';
      this.selectedCategoryName = '全部';
      this.searchText = '';
    }
    // A new listing always starts from the first page.
    this.loadedCount = 0;
    this.totalCount = 0;
    const hadContent: boolean = this.completeArchiveIndex.length > 0;
    if (!silent) {
      this.libraryError = '';
      // Only an empty library gets the loading screen: with content on screen,
      // hiding it is exactly the regression this avoids.
      this.isLibraryLoading = !hadContent;
      if (hadContent) {
        this.libraryNotice = localized('正在刷新档案库…');
      }
    }
    let failure: string = '';
    let firstPage: ArchiveIndexPageResult = new ArchiveIndexPageResult([], 0);
    let loadedCategories: Array<CategoryItem> = this.categories;
    const sortBy: string = this.serverSortKey();
    const descending: boolean = !this.sortAscending;
    const filter: string = this.searchText.trim();
    const categoryId: string = this.selectedCategoryId;
    try {
      await this.ensureServerPageSize(client);
      firstPage = await client.fetchArchiveIndexPage(
        0, this.pageSize(), sortBy, descending, filter, categoryId);
      try {
        loadedCategories = await client.fetchCategories();
      } catch (error) {
        // Keep the last local category list if only the category request fails.
      }
      await this.installLibrary(firstPage, loadedCategories, silent, sortBy, descending, filter,
        categoryId);
    } catch (error) {
      failure = this.describeError(error);
      AppLog.error('library', `load failed: ${AppLog.describe(error)}`);
    } finally {
      if (!silent) {
        this.isLibraryLoading = false;
      }
    }
    if (failure.length === 0) {
      this.libraryNotice = '';
      return;
    }
    if (silent && this.completeArchiveIndex.length > 0) {
      // There is something to read on screen, so the failure is reported as a
      // hint line rather than by hiding the library. A toast cannot be used
      // here: during startup the window is not focusable yet and the system
      // silently drops it.
      this.libraryNotice = localized('无法刷新档案库，正在显示本地缓存');
    } else {
      this.libraryError = failure;
    }
  }

  /** How many entries a page holds, as the server defines it. */
  private pageSize(): number {
    // The server caps a page at its own `archives_per_page` and ignores anything
    // larger, so asking for more only wastes the parameter.
    return this.serverPageSize > 0 ? this.serverPageSize : 100;
  }

  /**
   * Reads the server's page size once.
   *
   * Asking for a number the server will not honor just makes the client's idea
   * of a page disagree with what arrives, so the size comes from the server.
   * Failure is not fatal: the fallback keeps paging working.
   */
  private async ensureServerPageSize(client: LanraragiApiClient): Promise<void> {
    if (this.serverPageSize > 0) {
      return;
    }
    try {
      const info: ServerInfo = await client.fetchServerInfo();
      if (info.archivesPerPage > 0) {
        this.serverPageSize = info.archivesPerPage;
      }
    } catch (error) {
      AppLog.warn('library', `page size unknown: ${AppLog.describe(error)}`);
    }
  }

  /** The `sortby` value the search endpoint expects for the selected sort. */
  private serverSortKey(): string {
    switch (this.sortModeIndex) {
      case 1:
        return 'title';
      case 2:
        return 'pages';
      case 3:
        return 'artist';
      case 4:
        return 'group';
      case 5:
        return 'event';
      case 6:
        return 'series';
      case 7:
        return 'character';
      case 8:
        return 'parody';
      default:
        // Also the default the server itself uses.
        return 'date_added';
    }
  }

  /**
   * Fetches the next page and appends it.
   *
   * Called when the user reaches the end of the list. Ordering, filtering and
   * searching are all server-side, so appending keeps the list in the order the
   * server returned instead of one the client has to recompute.
   */
  private async loadNextPage(): Promise<void> {
    if (this.isLoadingMore || this.loadedCount >= this.totalCount ||
      this.serverUrl.length === 0) {
      return;
    }
    this.isLoadingMore = true;
    try {
      const client: LanraragiApiClient = new LanraragiApiClient(this.serverUrl, this.apiKey);
      const page: ArchiveIndexPageResult = await client.fetchArchiveIndexPage(
        this.loadedCount, this.pageSize(), this.serverSortKey(),
        !this.sortAscending, this.searchText.trim(), this.selectedCategoryId);
      this.appendPage(page);
    } catch (error) {
      AppLog.warn('library', `page at ${this.loadedCount} failed: ${AppLog.describe(error)}`);
      this.libraryNotice = localized('加载更多档案失败');
    } finally {
      this.isLoadingMore = false;
    }
  }

  /**
   * Adds a page to the list and to the local lookup.
   *
   * The lookup is what progress updates and the reader resolve archives through,
   * so a page that only reached the data source would be unopenable.
   */
  private appendPage(page: ArchiveIndexPageResult): void {
    if (page.archives.length === 0) {
      this.totalCount = this.loadedCount;
      return;
    }
    // Progress recorded while this page was in flight is newer than the server's
    // copy, so it is applied before the rows become visible.
    this.mergePendingProgress(page.archives);
    for (let index: number = 0; index < page.archives.length; index += 1) {
      const archive: ArchiveItem = page.archives[index];
      this.completeArchiveIndex.push(archive);
      this.archiveById.set(archive.id, archive);
    }
    this.loadedCount = this.completeArchiveIndex.length;
    this.totalCount = page.total > 0 ? page.total : this.loadedCount;
    this.archiveDataSource.append(page.archives);
    this.visibleArchiveCount = this.archiveDataSource.totalCount();
    AppLog.detail('library', `page appended: ${this.loadedCount}/${this.totalCount}`);
  }

  /**
   * Publishes a freshly fetched library.
   *
   * The filter state is reset here and only here: a background refresh that
   * happens to land while someone is browsing must not throw away what they
   * selected.
   */
  private async installLibrary(firstPage: ArchiveIndexPageResult,
    categories: Array<CategoryItem>, silent: boolean, sortBy: string, descending: boolean,
    filter: string, categoryId: string): Promise<void> {
    const archives: Array<ArchiveItem> = firstPage.archives;
    this.completeArchiveIndex = archives;
    this.allArchives = archives;
    this.categories = categories;
    this.loadedCount = archives.length;
    this.totalCount = firstPage.total;
    this.reindexArchiveLookup(archives);
    // Positions recorded while this refresh was in flight are newer than what
    // the server just reported, so they are folded into the new instances
    // before the overlay is dropped. The refresh takes up to four minutes to
    // time out, so a page turn during it is an ordinary event, and a server
    // that keeps progress on the client reports zero here.
    this.mergePendingProgress(archives);
    try {
      this.indexCacheRepository(this.serverUrl).save(archives, categories);
      // The rows above are in the index that was just written, so the overlay
      // no longer holds anything the index does not.
      this.pendingProgress = {};
      this.pendingReadTimes = {};
      await this.progressOverlayRepository().clear();
    } catch (error) {
      // A successful refresh remains usable if local index persistence fails.
    }
    this.applyArchiveFilter();
    this.libraryError = '';
    AppLog.info('library',
      `first page ${archives.length}/${this.totalCount}, sort=${sortBy} desc=${descending}` +
      ` filter="${filter}" category="${categoryId}"` +
      `${silent ? ' (background refresh)' : ''}`);
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      // A message that cannot be displayed must not affect the library.
    }
  }

  private restoreCachedLibrary(serverUrl: string): void {
    const cached: CachedLibraryIndex | undefined =
      this.indexCacheRepository(serverUrl).load();
    if (cached === undefined || cached.archives.length === 0) {
      this.completeArchiveIndex = [];
      this.allArchives = [];
      this.categories = [];
      this.archiveDataSource.replace([]);
      this.visibleArchiveCount = 0;
      this.libraryError = localized('暂无本地档案索引，请点击右上角刷新');
      return;
    }
    this.completeArchiveIndex = cached.archives;
    this.allArchives = cached.archives;
    this.categories = cached.categories;
    this.selectedCategoryId = '';
    this.selectedCategoryName = '全部';
    this.searchText = '';
    this.libraryError = '';
    this.reindexArchiveLookup(cached.archives);
    this.applyArchiveFilter();
    // Positions written after the index snapshot are applied on top of it.
    this.applyProgressOverlay().catch(() => {});
  }

  private reindexArchiveLookup(archives: Array<ArchiveItem>): void {
    this.archiveById = new Map<string, ArchiveItem>();
    for (let index: number = 0; index < archives.length; index += 1) {
      this.archiveById.set(archives[index].id, archives[index]);
    }
  }

  /**
   * Folds locally recorded progress into freshly loaded archives.
   *
   * The overlay only covers the window between a page turn and the next full
   * refresh, so every entry in it is newer than the server's own numbers: page
   * positions are taken as a maximum and read times only ever move forward.
   */
  private mergePendingProgress(archives: Array<ArchiveItem>): void {
    for (let index: number = 0; index < archives.length; index += 1) {
      const archive: ArchiveItem = archives[index];
      const page: number | undefined = this.pendingProgress[archive.id];
      if (page !== undefined && Number.isFinite(page) && page > archive.progress) {
        archive.setProgress(page);
      }
      const readAt: number | undefined = this.pendingReadTimes[archive.id];
      if (readAt !== undefined && Number.isFinite(readAt) && readAt > 0) {
        archive.markReadAt(readAt);
      }
    }
  }

  /** Re-applies page positions recorded after the cached index was written. */
  private async applyProgressOverlay(): Promise<void> {
    const repository: LibraryProgressOverlayRepository = this.progressOverlayRepository();
    const overlay: Record<string, number> = await repository.load();
    const readTimes: Record<string, number> = await repository.loadReadTimes();
    this.pendingProgress = overlay;
    this.pendingReadTimes = readTimes;
    let applied: boolean = false;
    this.archiveById.forEach((archive: ArchiveItem, archiveId: string) => {
      const page: number | undefined = overlay[archiveId];
      if (page !== undefined && Number.isFinite(page) && page > 0) {
        archive.setProgress(page);
        applied = true;
      }
      const readAt: number | undefined = readTimes[archiveId];
      if (readAt !== undefined && Number.isFinite(readAt) && readAt > 0) {
        // Only raises the stored value, so a newer server timestamp wins.
        archive.markReadAt(readAt);
      }
    });
    // The badges read their archive through @ObjectLink, so a full re-filter is
    // only needed when the completed-filtered set can actually change.
    if (applied && this.hideCompleted) {
      this.applyArchiveFilter();
    }
  }

  /**
   * Archives belonging to one category.
   *
   * The category list only carries archive IDs for static categories: LANraragi
   * matches a dynamic category (one with a `search` rule) on the server, so its
   * `archives` field comes back empty and filtering the local index by it would
   * show nothing at all. Dynamic categories are therefore resolved through
   * `/api/search`, which returns the full archive objects.
   */
  private async archivesOfCategory(
    categoryId: string,
    category: CategoryItem
  ): Promise<Array<ArchiveItem>> {
    if (category.search.length === 0) {
      const archiveIds: Array<string> = category.archiveIds;
      return this.completeArchiveIndex.filter((archive: ArchiveItem) => {
        return archiveIds.indexOf(archive.id) >= 0;
      });
    }
    const client: LanraragiApiClient =
      new LanraragiApiClient(this.serverUrl, this.apiKey);
    AppLog.info('library', `dynamic category ${categoryId} "${category.search}" via /api/search`);
    return client.fetchArchivesForCategory(categoryId);
  }

  private progressOverlayRepository(): LibraryProgressOverlayRepository {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    return new LibraryProgressOverlayRepository(context);
  }

  private async selectCategory(categoryId: string, categoryName: string): Promise<void> {
    if (this.isLibraryLoading || categoryId === this.selectedCategoryId) {
      return;
    }
    this.isLibraryLoading = true;
    this.libraryError = '';
    this.searchText = '';
    try {
      if (categoryId.length === 0) {
        this.allArchives = this.completeArchiveIndex;
      } else {
        let selectedCategory: CategoryItem | undefined = undefined;
        for (let index: number = 0; index < this.categories.length; index += 1) {
          if (this.categories[index].id === categoryId) {
            selectedCategory = this.categories[index];
            break;
          }
        }
        if (selectedCategory === undefined) {
          throw new Error(localized('本地分类信息不存在，请手动刷新书库'));
        }
        this.allArchives = await this.archivesOfCategory(categoryId, selectedCategory);
      }
      this.selectedCategoryId = categoryId;
      this.selectedCategoryName = categoryName;
      this.applyArchiveFilter();
    } catch (error) {
      this.libraryError = this.describeError(error);
    } finally {
      this.isLibraryLoading = false;
    }
  }

  /**
   * Re-runs the search after a short pause in typing.
   *
   * The search itself is a server request, so it is debounced rather than fired
   * per keystroke. It is also silent: the previous results stay on screen while
   * it runs, so the grid does not blink on every character.
   */
  private scheduleArchiveFilter(): void {
    if (this.searchDebounceTimer >= 0) {
      clearTimeout(this.searchDebounceTimer);
    }
    this.searchDebounceTimer = setTimeout(() => {
      this.searchDebounceTimer = -1;
      this.runServerSearch();
    }, 250);
  }

  /**
   * Searches the whole library through the server.
   *
   * The client only holds the pages it has loaded, so a local search would
   * quietly miss everything below the fold. The endpoint matches both tags and
   * titles, which is what the search box has always promised.
   */
  private async runServerSearch(): Promise<void> {
    if (this.serverUrl.length === 0) {
      return;
    }
    try {
      const client: LanraragiApiClient = new LanraragiApiClient(this.serverUrl, this.apiKey);
      this.libraryNotice = localized('正在搜索…');
      // resetView stays off: it would clear the query that was just typed.
      await this.loadLibrary(client, true, false);
    } catch (error) {
      AppLog.warn('library', `search failed: ${AppLog.describe(error)}`);
    }
  }

  /**
   * Applies the parts of the view the client still owns.
   *
   * Searching, ordering and category selection are all server-side now, so this
   * only re-applies the local "hide read" filter and republishes the rows. The
   * order of the list is the order the pages arrived in.
   */
  private applyArchiveFilter(): void {
    let filtered: Array<ArchiveItem> = this.allArchives.slice();
    if (this.hideCompleted) {
      filtered = filtered.filter((archive: ArchiveItem) => {
        return archive.readingState !== 2;
      });
    }
    this.archiveDataSource.replace(filtered);
    this.visibleArchiveCount = filtered.length;
  }

  private enterSearchMode(): void {
    this.isCategoryPopupVisible = false;
    this.isSortPopupVisible = false;
    this.searchText = '';
    this.isSearchMode = true;
    this.applyArchiveFilter();
  }

  private openSearchForTag(tag: string): void {
    this.isCategoryPopupVisible = false;
    this.isSortPopupVisible = false;
    this.selectedCategoryId = '';
    this.selectedCategoryName = '全部';
    this.allArchives = this.completeArchiveIndex.slice();
    this.searchText = tag;
    this.isSearchMode = true;
    this.applyArchiveFilter();
    this.pathStack.clear();
  }

  private exitSearchMode(): void {
    this.searchText = '';
    this.isSearchMode = false;
    this.applyArchiveFilter();
  }

  private applySortDirection(ascending: boolean): void {
    this.sortAscending = ascending;
    this.isSortPopupVisible = false;
    this.applyArchiveFilter();
    this.saveLibrarySettings();
  }

  private sortModeLabels(): Array<string> {
    return [
      localized('添加时间'),
      localized('标题'),
      localized('页数'),
      localized('阅读进度'),
      localized('阅读状态'),
      localized('NEW 状态'),
      localized('艺术家'),
      localized('团体'),
      localized('活动'),
      localized('系列'),
      localized('角色'),
      localized('原作'),
      localized('随机')
    ];
  }

  /**
   * Stable random rank for one archive.
   *
   * The server only sorts by title or last read time, so "Random" is a local
   * shuffle. Ranks are drawn on first use and cached, which keeps the ordering
   * stable while searching or switching category instead of reshuffling on
   * every redraw.
   */


  private sortModeLabel(): string {
    const labels: Array<string> = this.sortModeLabels();
    return labels[this.sortModeIndex] ?? labels[0];
  }

  private async refreshLibraryWindowSize(): Promise<void> {
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const mainWindow: window.Window = await window.getLastWindow(context);
      const rect = mainWindow.getWindowProperties().windowRect;
      if (rect.width > 0 && rect.height > 0) {
        this.libraryLandscape = rect.width > rect.height;
        this.updateLibraryContentWidth(rect.width);
        this.applyLibraryWindowBars();
      }
    } catch (error) {
      // The initial window size will be picked up by onAreaChange.
    }
  }

  private applyLibraryWindowBars(): void {
    if (this.readerFullscreenActive || AppStorage.get<boolean>('lanarkReaderFullscreen') === true) {
      return;
    }
    const requestId: number = ++this.libraryWindowRequestId;
    this.applyLibraryWindowBarsAsync(requestId);
  }

  private async applyLibraryWindowBarsAsync(requestId: number): Promise<void> {
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const mainWindow: window.Window = await window.getLastWindow(context);
      if (requestId !== this.libraryWindowRequestId ||
        this.readerFullscreenActive || AppStorage.get<boolean>('lanarkReaderFullscreen') === true) {
        return;
      }
      await mainWindow.setWindowLayoutFullScreen(this.libraryLandscape);
      if (requestId !== this.libraryWindowRequestId ||
        this.readerFullscreenActive || AppStorage.get<boolean>('lanarkReaderFullscreen') === true) {
        return;
      }
        await mainWindow.setSpecificSystemBarEnabled('status', !this.libraryLandscape, false);
        await mainWindow.setSpecificSystemBarEnabled('navigation', false, false);
        await mainWindow.setSpecificSystemBarEnabled('navigationIndicator', false, false);
        // The system applies bar visibility asynchronously; repeat after the transition
        // so returning from an immersive reader cannot bring the gesture pill back.
        setTimeout(() => {
          mainWindow.setSpecificSystemBarEnabled('navigationIndicator', false, false)
            .catch(() => {});
        }, 400);
      } catch (error) {
      // System bar visibility must not interrupt library browsing.
    }
  }

  private openArchiveReader(archive: ArchiveItem): void {
    this.pathStack.pushPath({
      name: 'ArchiveReader',
      param: new ReaderRouteParams(archive, false)
    });
  }

  private updateArchiveProgress(archiveId: string, pageNumber: number): void {
    // `allArchives` and `completeArchiveIndex` hold the same instances, so one
    // map lookup updates every view that observes the archive.
    const archive: ArchiveItem | undefined = this.archiveById.get(archiveId);
    if (archive !== undefined) {
      archive.setProgress(pageNumber);
      archive.markReadAt(Math.floor(Date.now() / 1000));
      this.pendingReadTimes[archiveId] = archive.lastReadTime;
    } else {
      // The archive is not in the library (deleted or a fresh index); keep the
      // history entry for it rather than dropping the read time.
      this.pendingReadTimes[archiveId] = Math.floor(Date.now() / 1000);
    }
    this.pendingProgress[archiveId] = pageNumber;
    const visibleArchive: ArchiveItem | undefined =
      this.archiveDataSource.updateProgress(archiveId, pageNumber);
    if (this.hideCompleted && visibleArchive !== undefined &&
      visibleArchive.readingState === 2) {
      this.applyArchiveFilter();
    }
    this.scheduleProgressPersistence();
  }

  private removeDeletedArchive(archiveId: string): void {
    this.archiveById.delete(archiveId);
    this.completeArchiveIndex = this.completeArchiveIndex.filter((archive: ArchiveItem) => {
      return archive.id !== archiveId;
    });
    this.allArchives = this.allArchives.filter((archive: ArchiveItem) => {
      return archive.id !== archiveId;
    });
    this.categories.forEach((category: CategoryItem) => {
      let index: number = category.archiveIds.indexOf(archiveId);
      while (index >= 0) {
        category.archiveIds.splice(index, 1);
        index = category.archiveIds.indexOf(archiveId);
      }
    });
    this.applyArchiveFilter();
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const cache: ImageDiskCache = new ImageDiskCache(context, this.serverUrl);
      cache.clearArchiveCover(archiveId);
      // A long document holds hundreds of files, which is why this does not run
      // on the UI thread; the card is already gone either way.
      cache.clearArchivePagesAsync(archiveId).catch((error: Object) => {
        AppLog.warn('library', `page cache cleanup failed for ${archiveId}: ` +
          `${AppLog.describe(error)}`);
      });
      this.indexCacheRepository(this.serverUrl).save(
        this.completeArchiveIndex,
        this.categories
      );
      // The local side of a delete: recorded because it is where leftovers come
      // from. A card that reappears after a refresh, or disk that never shrinks,
      // is answered by whether these three steps ran.
      AppLog.warn('library',
        `archive ${archiveId} removed locally: index=${this.completeArchiveIndex.length} ` +
        `categories=${this.categories.length} cover+pages cleared`);
    } catch (error) {
      AppLog.error('library',
        `local cleanup after deleting ${archiveId} failed: ${AppLog.describe(error)}`);
      // The server deletion succeeded; local cleanup failure must not restore the card.
    }
    this.pathStack.clear();
    this.showToast(localized('档案已删除'));
  }

  private scheduleProgressPersistence(): void {
    if (this.progressPersistTimer >= 0) {
      clearTimeout(this.progressPersistTimer);
    }
    this.progressPersistTimer = setTimeout(() => {
      this.progressPersistTimer = -1;
      // Only the changed page positions are written here. The full index is
      // rewritten when the library is refreshed, not on every page turn.
      this.progressOverlayRepository().save(this.pendingProgress, this.pendingReadTimes)
        .catch(() => {});
    }, 500);
  }

  private async restoreLibrarySettings(): Promise<void> {
    try {
      const settings: LibrarySettings = await this.libraryRepository().load();
      this.applyLibrarySettings(settings);
    } catch (error) {
      // Library defaults remain available if preferences cannot be read.
    }
  }

  private applyLibrarySettings(settings: LibrarySettings): void {
    this.sortModeIndex = settings.sortModeIndex;
    this.sortAscending = settings.sortAscending;
    this.hideCompleted = settings.hideCompleted;
    this.gridLayout = settings.gridLayout;
    this.gridColumns = settings.gridColumns;
    this.coverCrop = settings.coverCrop;
    if (this.allArchives.length > 0) {
      this.applyArchiveFilter();
    }
  }

  private async saveLibrarySettings(): Promise<void> {
    try {
      await this.libraryRepository().save(new LibrarySettings(
        this.sortModeIndex,
        this.sortAscending,
        this.hideCompleted,
        this.gridLayout,
        this.gridColumns,
        this.coverCrop
      ));
    } catch (error) {
      // A sort action remains usable even when its preference cannot be saved.
    }
  }

  private effectiveGridColumns(): number {
    if (this.gridColumns > 0) {
      return this.gridColumns;
    }
    const minimumCardWidth: number = 160;
    const gap: number = 10;
    const estimated: number = Math.floor((this.libraryContentWidth + gap) /
      (minimumCardWidth + gap));
    return Math.min(Math.max(estimated, 2), 6);
  }

  private gridColumnsTemplate(): string {
    const columns: number = this.effectiveGridColumns();
    return `${'1fr '.repeat(columns)}`.trim();
  }

  private updateLibraryContentWidth(widthPx: number): void {
    const widthVp: number = this.getUIContext().px2vp(widthPx);
    this.updateLibraryContentWidthVp(widthVp);
  }

  private updateLibraryContentWidthVp(widthVp: number): void {
    if (widthVp > 0 && Math.abs(widthVp - this.libraryContentWidth) > 0.5) {
      this.libraryContentWidth = widthVp;
    }
  }

  private async clearConfig(): Promise<void> {
    try {
      await this.repository().clear();
      this.applyClearedServerConfig();
      this.errorMessage = '';
    } catch (error) {
      this.errorMessage = this.describeError(error);
    }
  }

  private applyServerConfig(config: ServerConfig): void {
    this.serverUrl = config.serverUrl;
    this.apiKey = config.apiKey;
    this.errorMessage = '';
    this.restoreCachedLibrary(config.serverUrl);
  }

  private applyClearedServerConfig(): void {
    this.serverUrl = '';
    this.apiKey = '';
    this.completeArchiveIndex = [];
    this.allArchives = [];
    this.categories = [];
    this.selectedCategoryId = '';
    this.selectedCategoryName = '全部';
    this.archiveDataSource.replace([]);
    this.visibleArchiveCount = 0;
    this.searchText = '';
  }

  private repository(): ServerConfigRepository {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    return new ServerConfigRepository(context);
  }

  private libraryRepository(): LibrarySettingsRepository {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    return new LibrarySettingsRepository(context);
  }

  private indexCacheRepository(serverUrl: string): LibraryIndexCacheRepository {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    return new LibraryIndexCacheRepository(context, serverUrl);
  }

  private describeError(error: Object): string {
    return describeUserFacingError(error, localized('连接失败，请检查服务器地址、API Key 和网络状态'));
  }
}


