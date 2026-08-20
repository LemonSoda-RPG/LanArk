import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
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
  ArchiveItem,
  CategoryItem,
  ReaderRouteParams,
  ServerConfig
} from '../domain/model/LanraragiModels';
import { ArchiveDetailPage } from '../features/archive/ArchiveDetailPage';
import { ArchiveInfoPage } from '../features/archive/ArchiveInfoPage';
import { ArchiveReaderPage } from '../features/reader/ArchiveReaderPage';
import { SettingsPage } from '../features/settings/SettingsPage';
import { DownloadedArchivesPage } from '../features/download/DownloadedArchivesPage';
import { DownloadManagerPage } from '../features/download/DownloadManagerPage';
import { localized } from '../common/Localization';

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

@Component
export struct ArchiveCoverView {
  archiveId: string = '';
  fileExtension: string = '';
  serverUrl: string = '';
  apiKey: string = '';
  coverWidth: number | string = 68;
  coverHeight: number | string = 92;
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
    .width(this.coverWidth)
    .height(this.coverHeight)
    .backgroundColor($r('app.color.surface_muted'))
    .borderRadius(10)
    .clip(true)
  }

  private async loadCover(): Promise<void> {
    if (this.isLoading || this.archiveId.length === 0 || this.serverUrl.length === 0) {
      return;
    }
    this.isLoading = true;
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const cache: ImageDiskCache = new ImageDiskCache(context, this.serverUrl);
      let buffer: ArrayBuffer | undefined = cache.readCover(this.archiveId);
      let shouldCache: boolean = false;
      const client: LanraragiApiClient =
        new LanraragiApiClient(this.serverUrl, this.apiKey);
      if (buffer === undefined) {
        buffer = await client.fetchArchiveThumbnail(this.archiveId);
        shouldCache = buffer !== undefined;
      }
      if (buffer === undefined) {
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
          this.cover = await source.createPixelMap({
            desiredSize: { width: Math.max(targetWidth, 1), height: targetHeight }
          });
        } else {
          this.cover = await source.createPixelMap();
        }
        if (shouldCache) {
          await cache.writeCover(this.archiveId, this.cover);
        }
      } finally {
        await source.release();
      }
    } catch (error) {
      // The extension placeholder remains available when a cover cannot be loaded.
    } finally {
      this.isLoading = false;
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
  @State private isConnected: boolean = false;
  @State private errorMessage: string = '';
  @State private isLibraryLoading: boolean = false;
  @State private libraryError: string = '';
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
  @State private gridLayout: boolean = false;
  @State private gridColumns: number = 0;
  @State private libraryContentWidth: number = 0;
  private allArchives: Array<ArchiveItem> = [];
  private completeArchiveIndex: Array<ArchiveItem> = [];
  private archiveDataSource: ArchiveDataSource = new ArchiveDataSource();
  private progressPersistTimer: number = -1;
  private libraryLandscape: boolean = false;
  private readerFullscreenActive: boolean = false;
  private libraryWindowRequestId: number = 0;

  aboutToAppear(): void {
    this.restoreLibrarySettings();
    this.restoreConfig();
    this.refreshLibraryWindowSize();
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
    if (name === 'ArchiveDetail') {
      ArchiveDetailPage({ archive: param as ArchiveItem })
    } else if (name === 'ArchiveReader') {
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
        archive: param as ArchiveItem,
        onTagSelected: (tag: string): void => {
          this.openSearchForTag(tag);
        },
        onArchiveDeleted: (archiveId: string): void => {
          this.removeDeletedArchive(archiveId);
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
    } else if (name === 'DownloadManager') {
      DownloadManagerPage()
    }
  }

  @Builder
  private setupPage() {
    Scroll() {
      Column({ space: 20 }) {
        Column({ space: 8 }) {
          Text('LanArk')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.setup_subtitle'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .margin({ bottom: 12 })

        Column({ space: 8 }) {
          Text($r('app.string.server_url_label'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          TextInput({
            placeholder: $r('app.string.server_url_placeholder'),
            text: this.serverUrl
          })
            .type(InputType.Normal)
            .height(52)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .backgroundColor($r('app.color.surface'))
            .borderRadius(12)
            .onChange((value: string) => {
              this.serverUrl = value;
              this.errorMessage = '';
            })
        }
        .width('100%')

        Column({ space: 8 }) {
          Text($r('app.string.api_key_label'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          TextInput({
            placeholder: $r('app.string.api_key_placeholder'),
            text: this.apiKey
          })
            .type(InputType.Password)
            .showPasswordIcon(true)
            .height(52)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_tertiary'))
            .backgroundColor($r('app.color.surface'))
            .borderRadius(12)
            .onChange((value: string) => {
              this.apiKey = value;
              this.errorMessage = '';
            })
          Text($r('app.string.api_key_storage_hint'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
        .width('100%')

        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(14)
            .fontColor($r('app.color.error'))
            .width('100%')
            .padding(12)
            .backgroundColor($r('app.color.error_soft'))
            .borderRadius(10)
        }

        Button(this.isLoading ? $r('app.string.connecting') : $r('app.string.connect'))
          .width('100%')
          .height(52)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .enabled(!this.isLoading)
          .backgroundColor($r('app.color.accent'))
          .onClick(() => {
            this.connectAndSave();
          })

        if (this.serverUrl.length > 0) {
          Button(localized('清除保存的服务器配置'))
            .width('100%')
            .height(48)
            .fontSize(15)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.error'))
            .onClick(() => {
              this.clearConfig();
            })
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 560 })
      .padding({ left: 24, right: 24, top: 72, bottom: 48 })
    }
    .width('100%')
    .height('100%')
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
                this.applyArchiveFilter();
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
            .enabled(!this.isLibraryLoading)
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
    .onClick(() => {
      this.sortModeIndex = index;
      this.sortAscending = index === 1 || index >= 6;
      this.isSortPopupVisible = false;
      this.applyArchiveFilter();
      this.saveLibrarySettings();
    })
  }

  @Builder
  private archiveRow(archive: ArchiveItem) {
    Row({ space: 14 }) {
      ArchiveCoverView({
        archiveId: archive.id,
        fileExtension: archive.fileExtension,
        serverUrl: this.serverUrl,
        apiKey: this.apiKey
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
          coverHeight: '100%'
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
        this.isConnected = true;
        this.restoreCachedLibrary(config.serverUrl);
      } else {
        this.isConnected = false;
        this.libraryError = localized('请先在设置中配置服务器，然后点击刷新获取档案索引');
      }
    } catch (error) {
      this.isConnected = false;
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
      this.isConnected = true;
      await this.loadLibrary(client);
    } catch (error) {
      this.errorMessage = this.describeError(error);
      this.isConnected = false;
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
      await this.loadLibrary(client);
    } catch (error) {
      this.libraryError = this.describeError(error);
    }
  }

  private async loadLibrary(client: LanraragiApiClient): Promise<void> {
    this.isLibraryLoading = true;
    this.libraryError = '';
    try {
      const loadedArchives: Array<ArchiveItem> = await client.fetchArchiveIndex();
      let loadedCategories: Array<CategoryItem> = this.categories;
      try {
        loadedCategories = await client.fetchCategories();
      } catch (error) {
        // Keep the last local category list if only the category request fails.
      }
      this.completeArchiveIndex = loadedArchives;
      this.allArchives = loadedArchives;
      this.categories = loadedCategories;
      this.selectedCategoryId = '';
      this.selectedCategoryName = '全部';
      this.searchText = '';
      try {
        this.indexCacheRepository(this.serverUrl).save(
          loadedArchives,
          loadedCategories
        );
      } catch (error) {
        // A successful refresh remains usable if local index persistence fails.
      }
      this.applyArchiveFilter();
    } catch (error) {
      this.libraryError = this.describeError(error);
    } finally {
      this.isLibraryLoading = false;
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
    this.applyArchiveFilter();
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
        const archiveIds: Array<string> = selectedCategory.archiveIds;
        this.allArchives = this.completeArchiveIndex.filter((archive: ArchiveItem) => {
          return archiveIds.indexOf(archive.id) >= 0;
        });
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

  private applyArchiveFilter(): void {
    const query: string = this.searchText.trim().toLowerCase();
    let filtered: Array<ArchiveItem> = this.allArchives.slice();
    if (query.length > 0) {
      filtered = this.allArchives.filter((archive: ArchiveItem) => {
        return archive.title.toLowerCase().includes(query) ||
          archive.tags.toLowerCase().includes(query);
      });
    }
    if (this.hideCompleted) {
      filtered = filtered.filter((archive: ArchiveItem) => {
        return archive.readingState !== 2;
      });
    }
    filtered.sort((left: ArchiveItem, right: ArchiveItem) => {
      return this.compareArchives(left, right);
    });
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

  private compareArchives(left: ArchiveItem, right: ArchiveItem): number {
    let result: number = 0;
    switch (this.sortModeIndex) {
      case 0:
        result = left.dateAdded - right.dateAdded;
        break;
      case 1:
        result = left.title.localeCompare(right.title);
        break;
      case 2:
        result = left.pageCount - right.pageCount;
        break;
      case 3:
        result = left.progressRatio - right.progressRatio;
        break;
      case 4:
        result = left.readingState - right.readingState;
        break;
      case 5:
        result = Number(left.displayAsNew) - Number(right.displayAsNew);
        break;
      case 6:
        result = left.tagValue('artist').localeCompare(right.tagValue('artist'));
        break;
      case 7:
        result = left.tagValue('group').localeCompare(right.tagValue('group'));
        break;
      case 8:
        result = left.tagValue('event').localeCompare(right.tagValue('event'));
        break;
      case 9:
        result = left.tagValue('series').localeCompare(right.tagValue('series'));
        break;
      case 10:
        result = left.tagValue('character').localeCompare(right.tagValue('character'));
        break;
      case 11:
        result = left.tagValue('parody').localeCompare(right.tagValue('parody'));
        break;
      default:
        result = left.title.localeCompare(right.title);
        break;
    }
    if (result === 0) {
      result = left.title.localeCompare(right.title);
    }
    return this.sortAscending ? result : -result;
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
      localized('原作')
    ];
  }

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
    console.info(`[ProgressDebug] library receive archive=${archiveId} page=${pageNumber}`);
    let updatedArchive: ArchiveItem | undefined = undefined;
    for (let index = 0; index < this.completeArchiveIndex.length; index += 1) {
      if (this.completeArchiveIndex[index].id === archiveId) {
        updatedArchive = this.completeArchiveIndex[index];
        updatedArchive.setProgress(pageNumber);
        break;
      }
    }
    for (let index = 0; index < this.allArchives.length; index += 1) {
      if (this.allArchives[index].id === archiveId) {
        if (this.allArchives[index] !== updatedArchive) {
          this.allArchives[index].setProgress(pageNumber);
        }
        break;
      }
    }
    const visibleArchive: ArchiveItem | undefined =
      this.archiveDataSource.updateProgress(archiveId, pageNumber);
    if (this.hideCompleted && visibleArchive !== undefined &&
      visibleArchive.readingState === 2) {
      this.applyArchiveFilter();
    }
    this.scheduleProgressPersistence();
  }

  private removeDeletedArchive(archiveId: string): void {
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
      cache.clearArchivePages(archiveId);
      this.indexCacheRepository(this.serverUrl).save(
        this.completeArchiveIndex,
        this.categories
      );
    } catch (error) {
      // The server deletion succeeded; local cleanup failure must not restore the card.
    }
    this.pathStack.clear();
    try {
      this.getUIContext().getPromptAction().showToast({
        message: localized('档案已删除')
      });
    } catch (error) {
      // The card has already been removed even if a toast cannot be displayed.
    }
  }

  private scheduleProgressPersistence(): void {
    if (this.progressPersistTimer >= 0) {
      clearTimeout(this.progressPersistTimer);
    }
    this.progressPersistTimer = setTimeout(() => {
      this.progressPersistTimer = -1;
      try {
        this.indexCacheRepository(this.serverUrl).save(
          this.completeArchiveIndex,
          this.categories
        );
      } catch (error) {
        // UI progress remains updated if local persistence is unavailable.
      }
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
        this.gridColumns
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
      this.isConnected = false;
    }
  }

  private applyServerConfig(config: ServerConfig): void {
    this.serverUrl = config.serverUrl;
    this.apiKey = config.apiKey;
    this.isConnected = true;
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
    this.isConnected = false;
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
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return localized('连接失败，请检查服务器地址、API Key 和网络状态');
  }
}
