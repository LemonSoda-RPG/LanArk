import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { ImageDiskCache } from '../../data/cache/ImageDiskCache';
import {
  ReaderSettings,
  ReaderSettingsRepository
} from '../../data/config/ReaderSettingsRepository';
import { ServerConfigRepository } from '../../data/config/ServerConfigRepository';
import { LanraragiApiClient } from '../../data/network/LanraragiApiClient';
import {
  ArchiveIndexPayload,
  ArchiveItem,
  ReaderPage,
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

function emptyRouteParams(): ReaderRouteParams {
  return new ReaderRouteParams(emptyArchive(), true);
}

class ReaderPageDataSource implements IDataSource {
  private pages: Array<ReaderPage> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.pages.length;
  }

  getData(index: number): ReaderPage {
    return this.pages[index];
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

  replace(pages: Array<ReaderPage>): void {
    this.pages = pages;
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }
}

class ReaderSpread {
  readonly earlierPage: ReaderPage;
  readonly laterPage: ReaderPage | undefined;
  readonly startIndex: number;
  readonly endIndex: number;

  constructor(
    earlierPage: ReaderPage,
    laterPage: ReaderPage | undefined,
    startIndex: number,
    endIndex: number
  ) {
    this.earlierPage = earlierPage;
    this.laterPage = laterPage;
    this.startIndex = startIndex;
    this.endIndex = endIndex;
  }
}

class ReaderSpreadDataSource implements IDataSource {
  private spreads: Array<ReaderSpread> = [];
  private listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.spreads.length;
  }

  getData(index: number): ReaderSpread {
    return this.spreads[index];
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

  replace(spreads: Array<ReaderSpread>): void {
    this.spreads = spreads;
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }
}

@Component
struct ReaderImageView {
  page: ReaderPage = new ReaderPage('', 1);
  archiveId: string = '';
  serverUrl: string = '';
  apiKey: string = '';
  continuous: boolean = false;
  // This is a one-way input so an active waterfall page is relaid out when
  // the parent changes the reading width. Keeping it on the page component
  // avoids scaling the List viewport itself.
  @Prop contentWidthPercent: number = 100;
  onZoomChanged: (scale: number) => void = (scale: number): void => {};
  @State private pixelMap: image.PixelMap | undefined = undefined;
  @State private isLoading: boolean = false;
  @State private errorMessage: string = '';
  @State private imageAspectRatio: number = 0.707;
  @State private zoomScale: number = 1;

  aboutToAppear(): void {
    this.loadImage();
  }

  aboutToBeDeleted(): void {
    if (this.pixelMap !== undefined) {
      this.pixelMap.release();
    }
  }

  build() {
    if (this.continuous) {
      Stack() {
        this.imageContent()
      }
      .width(`${this.contentWidthPercent}%`)
      .aspectRatio(this.imageAspectRatio)
      .backgroundColor(Color.Black)
    } else {
      Scroll() {
        Stack() {
          this.imageContent()
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.FREE)
      .minZoomScale(0.5)
      .maxZoomScale(5)
      .zoomScale(this.zoomScale)
      .enableBouncesZoom(true)
      .scrollBar(BarState.Off)
      .onDidZoom((scale: number) => {
        this.zoomScale = scale;
        this.onZoomChanged(scale);
      })
      .backgroundColor(Color.Black)
    }
  }

  @Builder
  private imageContent() {
    Stack() {
      if (this.pixelMap !== undefined) {
        Image(this.pixelMap as image.PixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
      } else if (this.isLoading) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(42)
            .height(42)
            .color(Color.White)
          Text(`正在加载第 ${this.page.pageNumber} 页`)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(14)
            .fontColor('#D9FFFFFF')
        }
      } else {
        Column({ space: 12 }) {
          Text(this.errorMessage.length > 0 ? this.errorMessage : '页面加载失败')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(15)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
          Button('重试')
            .height(44)
            .onClick(() => {
              this.loadImage();
            })
        }
        .padding(24)
      }
    }
    .width('100%')
    .height('100%')
  }

  private async loadImage(): Promise<void> {
    if (this.isLoading || this.page.path.length === 0) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const cache: ImageDiskCache = new ImageDiskCache(context, this.serverUrl);
      let buffer: ArrayBuffer | undefined =
        cache.readPage(this.archiveId, this.page.pageNumber);
      let shouldCache: boolean = false;
      const client: LanraragiApiClient =
        new LanraragiApiClient(this.serverUrl, this.apiKey);
      if (buffer === undefined) {
        buffer = await client.fetchArchivePage(this.page, this.archiveId);
        shouldCache = buffer !== undefined;
      }
      if (buffer === undefined) {
        throw new Error('服务器暂未生成该页面');
      }
      const source: image.ImageSource = image.createImageSource(buffer);
      try {
        const imageInfo: image.ImageInfo = await source.getImageInfo();
        if (imageInfo.size.width > 0 && imageInfo.size.height > 0) {
          this.imageAspectRatio = imageInfo.size.width / imageInfo.size.height;
        }
        this.pixelMap = await source.createPixelMap();
        if (shouldCache) {
          cache.writePage(this.archiveId, this.page.pageNumber, buffer);
        }
      } finally {
        await source.release();
      }
    } catch (error) {
      this.errorMessage = this.describeError(error);
    } finally {
      this.isLoading = false;
    }
  }

  private describeError(error: Object): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return '页面加载失败';
  }
}

@Component
export struct ArchiveReaderPage {
  @Consume('pathStack') private pathStack: NavPathStack = new NavPathStack();
  params: ReaderRouteParams = emptyRouteParams();
  onProgressChanged: (archiveId: string, pageNumber: number) => void =
    (archiveId: string, pageNumber: number): void => {};
  @State private pages: Array<ReaderPage> = [];
  @State private currentPageIndex: number = 0;
  @State private isLoading: boolean = false;
  @State private errorMessage: string = '';
  @State private serverUrl: string = '';
  @State private apiKey: string = '';
  @State private controlsVisible: boolean = true;
  @State private readDirectionIndex: number = 0;
  @State private readerModeIndex: number = 0;
  @State private doublePageOffset: number = 0;
  @State private tapPagingEnabled: boolean = true;
  @State private initialControlsVisible: boolean = true;
  @State private preloadPageCount: number = 3;
  @State private readerViewportWidth: number = 1;
  @State private waterfallScale: number = 1;
  @State private pageZoomScale: number = 1;
  private waterfallScaleStart: number = 1;
  private swiperController: SwiperController = new SwiperController();
  private verticalScroller: Scroller = new Scroller();
  private pageDataSource: ReaderPageDataSource = new ReaderPageDataSource();
  private spreadDataSource: ReaderSpreadDataSource = new ReaderSpreadDataSource();

  aboutToAppear(): void {
    this.loadPages();
  }

  aboutToBeDeleted(): void {
    if (this.params.archive.id.length === 0) {
      return;
    }
    try {
      this.imageCache().clearArchivePages(this.params.archive.id);
    } catch (error) {
      // Reader cache cleanup must never block leaving the document.
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Center }) {
        if (this.isLoading) {
          Column({ space: 14 }) {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(Color.White)
            Text('正在准备档案…')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(16)
              .fontColor(Color.White)
          }
        } else if (this.errorMessage.length > 0) {
          Column({ space: 16 }) {
            Text(this.errorMessage)
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(16)
              .fontColor(Color.White)
              .textAlign(TextAlign.Center)
            Button('重试')
              .onClick(() => {
                this.loadPages();
              })
          }
          .padding(28)
        } else if (this.pages.length > 0) {
          if (this.readerModeIndex === 2) {
            List({
              space: 0,
              scroller: this.verticalScroller,
              initialIndex: this.currentPageIndex
            }) {
              LazyForEach(this.pageDataSource, (page: ReaderPage) => {
                ListItem() {
                  Row() {
                    ReaderImageView({
                      page: page,
                      archiveId: this.params.archive.id,
                      serverUrl: this.serverUrl,
                      apiKey: this.apiKey,
                      continuous: true,
                      contentWidthPercent: this.waterfallScale * 100
                    })
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.Center)
                }
              }, (page: ReaderPage) => `vertical-${page.pageNumber}`)
            }
            .width('100%')
            .height('100%')
            .cachedCount(this.preloadPageCount)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .onScrollIndex((start: number, end: number, center: number) => {
              this.onVisiblePageChanged(center);
            })
            .onClick(() => {
              this.controlsVisible = !this.controlsVisible;
            })
            .gesture(
              PinchGesture({ fingers: 2 })
                .onActionStart(() => {
                  this.waterfallScaleStart = this.waterfallScale;
                })
                .onActionUpdate((event: GestureEvent) => {
                  this.waterfallScale = this.clampScale(
                    this.waterfallScaleStart * event.scale,
                    0.5,
                    2.5
                  );
                })
            )
          } else if (this.readerModeIndex === 1) {
            Swiper(this.swiperController) {
              LazyForEach(this.spreadDataSource, (spread: ReaderSpread) => {
                this.doublePageSpread(spread)
              }, (spread: ReaderSpread) =>
                `spread-${spread.startIndex}-${spread.endIndex}-${this.doublePageOffset}`)
            }
            .index(this.currentSpreadIndex())
            .loop(false)
            .indicator(false)
            .duration(0)
            .direction(this.readDirectionIndex === 1 ? Direction.Rtl : Direction.Ltr)
            .cachedCount(this.preloadPageCount)
            .disableSwipe(this.pageZoomScale > 1.01)
            .onChange((index: number) => {
              this.pageZoomScale = 1;
              this.onVisibleSpreadChanged(index);
            })
            .width('100%')
            .height('100%')
            .onAreaChange((oldValue: Area, newValue: Area) => {
              if (typeof newValue.width === 'number' && newValue.width > 0) {
                this.readerViewportWidth = newValue.width;
              }
            })
            .onClick((event: ClickEvent) => {
              this.handleHorizontalTap(event.x);
            })
          } else {
            Swiper(this.swiperController) {
              LazyForEach(this.pageDataSource, (page: ReaderPage) => {
                ReaderImageView({
                  page: page,
                  archiveId: this.params.archive.id,
                  serverUrl: this.serverUrl,
                  apiKey: this.apiKey,
                  continuous: false,
                  onZoomChanged: (scale: number): void => {
                    this.pageZoomScale = scale;
                  }
                })
              }, (page: ReaderPage) => `horizontal-${page.pageNumber}`)
            }
            .index(this.currentPageIndex)
            .loop(false)
            .indicator(false)
            .duration(0)
            .direction(this.readDirectionIndex === 1 ? Direction.Rtl : Direction.Ltr)
            .cachedCount(this.preloadPageCount)
            .disableSwipe(this.pageZoomScale > 1.01)
            .onChange((index: number) => {
              this.pageZoomScale = 1;
              this.onVisiblePageChanged(index);
            })
            .width('100%')
            .height('100%')
            .onAreaChange((oldValue: Area, newValue: Area) => {
              if (typeof newValue.width === 'number' && newValue.width > 0) {
                this.readerViewportWidth = newValue.width;
              }
            })
            .onClick((event: ClickEvent) => {
              this.handleHorizontalTap(event.x);
            })
          }
        }

        if (this.controlsVisible) {
          Row() {
            Button() {
              Image($r('app.media.icon_chevron_left'))
                .width(24)
                .height(24)
                .renderMode(ImageRenderMode.Template)
                .fillColor(Color.White)
            }
              .width(44)
              .height(44)
              .backgroundColor('#99000000')
              .accessibilityText('返回档案库')
              .onClick(() => {
                this.exitReader();
              })

            Blank()

            if (this.readerModeIndex === 1) {
              Button(this.doublePageOffset === 0 ? '1+2' : '2+3')
                .height(40)
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .backgroundColor('#99000000')
                .accessibilityText(this.doublePageOffset === 0 ?
                  '当前从第一页开始双页配对，点击改为第二页开始' :
                  '当前从第二页开始双页配对，点击改为第一页开始')
                .onClick(() => {
                  this.toggleDoublePageOffset();
                })
            } else if (this.readerModeIndex === 2 &&
              Math.abs(this.waterfallScale - 1) > 0.01) {
              Button(`${Math.round(this.waterfallScale * 100)}%`)
                .height(40)
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .backgroundColor('#99000000')
                .accessibilityText('重置瀑布页面宽度')
                .onClick(() => {
                  this.waterfallScale = 1;
                })
            }

            Button() {
              Image($r('app.media.icon_info'))
                .width(23)
                .height(23)
                .renderMode(ImageRenderMode.Template)
                .fillColor(Color.White)
            }
              .width(44)
              .height(44)
              .backgroundColor('#99000000')
              .accessibilityText('查看档案标签和操作')
              .onClick(() => {
                this.openArchiveInfo();
              })
          }
          .width('100%')
          .padding({ left: 10, right: 10 })
          .position({ x: 0, y: 10 })

          Stack({ alignContent: Alignment.Bottom }) {
            Row({ space: 12 }) {
              Text(this.readerProgressLabel())
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
                .width(62)
                .textAlign(TextAlign.Center)

              Slider({
                value: this.currentPageIndex + 1,
                min: 1,
                max: Math.max(this.pages.length, 1),
                step: 1,
                style: SliderStyle.OutSet
              })
                .selectedColor('#FF3F7CFF')
                .trackColor('#66FFFFFF')
                .blockColor(Color.White)
                .layoutWeight(1)
                .onChange((value: number, mode: SliderChangeMode) => {
                  const targetIndex: number =
                    Math.min(Math.max(Math.round(value) - 1, 0), this.pages.length - 1);
                  this.currentPageIndex = targetIndex;
                  this.moveReaderToIndex(targetIndex);
                  if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                    this.syncProgress(this.pages[targetIndex]);
                  }
                })
            }
            .width('100%')
            .padding({ left: 14, right: 18, top: 12, bottom: 18 })
            .backgroundColor('#CC000000')
            .borderRadius({ topLeft: 20, topRight: 20 })
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
    }
    .hideTitleBar(true)
  }

  @Builder
  private doublePageSpread(spread: ReaderSpread) {
    Row({ space: 1 }) {
      if (this.readDirectionIndex === 1) {
        this.doublePageSlot(spread.laterPage)
        this.doublePageSlot(spread.earlierPage)
      } else {
        this.doublePageSlot(spread.earlierPage)
        this.doublePageSlot(spread.laterPage)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FF101010')
  }

  @Builder
  private doublePageSlot(page: ReaderPage | undefined) {
    Stack() {
      if (page !== undefined) {
        ReaderImageView({
          page: page as ReaderPage,
          archiveId: this.params.archive.id,
          serverUrl: this.serverUrl,
          apiKey: this.apiKey,
          continuous: false,
          onZoomChanged: (scale: number): void => {
            this.pageZoomScale = scale;
          }
        })
      }
    }
    .layoutWeight(1)
    .height('100%')
    .backgroundColor(Color.Black)
  }

  private async loadPages(): Promise<void> {
    if (this.isLoading || this.params.archive.id.length === 0) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';
    try {
      try {
        const settings: ReaderSettings =
          await this.readerSettingsRepository().load();
        this.readDirectionIndex = settings.directionIndex;
        this.readerModeIndex = settings.modeIndex;
        this.doublePageOffset = settings.doublePageOffset;
        this.tapPagingEnabled = settings.tapPagingEnabled;
        this.initialControlsVisible = settings.initialControlsVisible;
        this.controlsVisible = settings.initialControlsVisible;
        this.preloadPageCount = settings.preloadPageCount;
      } catch (settingsError) {
        // Reader defaults remain available if local preferences cannot be read.
      }
      const config: ServerConfig = await this.repository().load();
      this.serverUrl = config.serverUrl;
      this.apiKey = config.apiKey;
      const client: LanraragiApiClient =
        new LanraragiApiClient(config.serverUrl, config.apiKey);
      const loadedPages: Array<ReaderPage> =
        await client.fetchArchivePages(this.params.archive.id);
      if (loadedPages.length === 0) {
        throw new Error('服务器返回的页面列表为空');
      }
      this.pages = loadedPages;
      this.pageDataSource.replace(loadedPages);
      this.rebuildSpreads();
      const initialIndex: number = this.initialPageIndex(loadedPages.length);
      this.currentPageIndex = this.readerModeIndex === 1 ?
        this.spreadEndIndexForPage(initialIndex) : initialIndex;
    } catch (error) {
      this.errorMessage = this.describeError(error);
      this.pages = [];
      this.pageDataSource.replace([]);
      this.spreadDataSource.replace([]);
    } finally {
      this.isLoading = false;
    }
  }

  private initialPageIndex(pageCount: number): number {
    if (this.params.fromStart || this.params.archive.progress <= 0) {
      return 0;
    }
    // Convert LANraragi's one-based progress to ArkUI's zero-based Swiper index.
    return Math.min(Math.max(this.params.archive.progress - 1, 0), pageCount - 1);
  }

  private onVisiblePageChanged(index: number): void {
    if (index < 0 || index >= this.pages.length) {
      return;
    }
    if (index === this.currentPageIndex) {
      return;
    }
    this.currentPageIndex = index;
    this.syncProgress(this.pages[index]);
  }

  private onVisibleSpreadChanged(index: number): void {
    if (index < 0 || index >= this.spreadDataSource.totalCount()) {
      return;
    }
    const spread: ReaderSpread = this.spreadDataSource.getData(index);
    if (spread.endIndex === this.currentPageIndex) {
      return;
    }
    this.currentPageIndex = spread.endIndex;
    this.syncProgress(this.pages[spread.endIndex]);
  }

  private goToPage(targetIndex: number): void {
    if (targetIndex < 0 || targetIndex >= this.pages.length) {
      return;
    }
    this.currentPageIndex = targetIndex;
    this.moveReaderToIndex(targetIndex);
    this.syncProgress(this.pages[targetIndex]);
  }

  private handleHorizontalTap(localX: number): void {
    if (!this.tapPagingEnabled) {
      this.controlsVisible = !this.controlsVisible;
      return;
    }
    const leftBoundary: number = this.readerViewportWidth * 0.3;
    const rightBoundary: number = this.readerViewportWidth * 0.7;
    if (localX < leftBoundary) {
      this.goToReadingStep(this.readDirectionIndex === 1 ? 1 : -1);
      return;
    }
    if (localX > rightBoundary) {
      this.goToReadingStep(this.readDirectionIndex === 1 ? -1 : 1);
      return;
    }
    this.controlsVisible = !this.controlsVisible;
  }

  private moveReaderToIndex(targetIndex: number): void {
    if (this.readerModeIndex === 2) {
      this.verticalScroller.scrollToIndex(targetIndex, false, ScrollAlign.START);
    } else if (this.readerModeIndex === 1) {
      this.swiperController.changeIndex(this.spreadIndexForPage(targetIndex), false);
    } else {
      this.swiperController.changeIndex(targetIndex, false);
    }
  }

  private goToReadingStep(delta: number): void {
    if (this.readerModeIndex !== 1) {
      this.goToPage(this.currentPageIndex + delta);
      return;
    }
    const targetSpreadIndex: number = this.currentSpreadIndex() + delta;
    if (targetSpreadIndex < 0 ||
      targetSpreadIndex >= this.spreadDataSource.totalCount()) {
      return;
    }
    const target: ReaderSpread = this.spreadDataSource.getData(targetSpreadIndex);
    this.currentPageIndex = target.endIndex;
    this.swiperController.changeIndex(targetSpreadIndex, false);
    this.syncProgress(this.pages[target.endIndex]);
  }

  private rebuildSpreads(): void {
    const spreads: Array<ReaderSpread> = [];
    if (this.pages.length === 0) {
      this.spreadDataSource.replace(spreads);
      return;
    }
    let startIndex: number = 0;
    if (this.doublePageOffset === 1) {
      spreads.push(new ReaderSpread(this.pages[0], undefined, 0, 0));
      startIndex = 1;
    }
    for (let index: number = startIndex; index < this.pages.length; index += 2) {
      const laterIndex: number = index + 1;
      const laterPage: ReaderPage | undefined = laterIndex < this.pages.length ?
        this.pages[laterIndex] : undefined;
      spreads.push(new ReaderSpread(
        this.pages[index],
        laterPage,
        index,
        laterPage === undefined ? index : laterIndex
      ));
    }
    this.spreadDataSource.replace(spreads);
  }

  private spreadIndexForPage(pageIndex: number): number {
    if (this.doublePageOffset === 1) {
      return pageIndex <= 0 ? 0 : 1 + Math.floor((pageIndex - 1) / 2);
    }
    return Math.floor(Math.max(pageIndex, 0) / 2);
  }

  private currentSpreadIndex(): number {
    if (this.spreadDataSource.totalCount() === 0) {
      return 0;
    }
    return Math.min(
      this.spreadIndexForPage(this.currentPageIndex),
      this.spreadDataSource.totalCount() - 1
    );
  }

  private spreadEndIndexForPage(pageIndex: number): number {
    if (this.spreadDataSource.totalCount() === 0) {
      return Math.min(Math.max(pageIndex, 0), Math.max(this.pages.length - 1, 0));
    }
    return this.spreadDataSource.getData(this.spreadIndexForPage(pageIndex)).endIndex;
  }

  private toggleDoublePageOffset(): void {
    if (this.readerModeIndex !== 1 || this.pages.length === 0) {
      return;
    }
    const anchorPageIndex: number = this.currentPageIndex;
    this.doublePageOffset = this.doublePageOffset === 0 ? 1 : 0;
    this.rebuildSpreads();
    this.currentPageIndex = this.spreadEndIndexForPage(anchorPageIndex);
    this.pageZoomScale = 1;
    this.swiperController.changeIndex(this.currentSpreadIndex(), false);
    this.saveCurrentReaderSettings();
  }

  private async saveCurrentReaderSettings(): Promise<void> {
    try {
      await this.readerSettingsRepository().save(new ReaderSettings(
        this.readDirectionIndex,
        this.readerModeIndex,
        this.doublePageOffset,
        this.tapPagingEnabled,
        this.initialControlsVisible,
        this.preloadPageCount
      ));
    } catch (error) {
      // A temporary preference failure must not interrupt reading.
    }
  }

  private readerProgressLabel(): string {
    if (this.pages.length === 0) {
      return '';
    }
    if (this.readerModeIndex !== 1 || this.spreadDataSource.totalCount() === 0) {
      return `${this.currentPageIndex + 1}/${this.pages.length}`;
    }
    const spread: ReaderSpread = this.spreadDataSource.getData(this.currentSpreadIndex());
    if (spread.startIndex === spread.endIndex) {
      return `${spread.startIndex + 1}/${this.pages.length}`;
    }
    return `${spread.startIndex + 1}-${spread.endIndex + 1}/${this.pages.length}`;
  }

  private clampScale(value: number, minimum: number, maximum: number): number {
    return Math.min(Math.max(value, minimum), maximum);
  }

  private async syncProgress(page: ReaderPage): Promise<void> {
    console.info(`[ProgressDebug] reader progress archive=${this.params.archive.id} page=${page.pageNumber}`);
    this.onProgressChanged(this.params.archive.id, page.pageNumber);
    if (this.serverUrl.length === 0 || this.params.archive.id.length === 0) {
      return;
    }
    try {
      const client: LanraragiApiClient =
        new LanraragiApiClient(this.serverUrl, this.apiKey);
      await client.updateArchiveProgress(this.params.archive.id, page.pageNumber);
    } catch (error) {
      // Reading must remain uninterrupted when optional progress synchronization fails.
    }
  }

  private exitReader(): void {
    if (this.pages.length > 0 && this.currentPageIndex >= 0 &&
      this.currentPageIndex < this.pages.length) {
      console.info(`[ProgressDebug] exit archive=${this.params.archive.id} ` +
        `page=${this.pages[this.currentPageIndex].pageNumber}`);
      // Update the local library before popping the destination. The callback
      // is synchronous, so the library card is refreshed immediately.
      this.syncProgress(this.pages[this.currentPageIndex]);
    }
    this.pathStack.pop();
  }

  private openArchiveInfo(): void {
    if (this.pages.length > 0 && this.currentPageIndex >= 0 &&
      this.currentPageIndex < this.pages.length) {
      this.syncProgress(this.pages[this.currentPageIndex]);
    }
    this.pathStack.pushPath({
      name: 'ArchiveInfo',
      param: this.params.archive
    });
  }

  private repository(): ServerConfigRepository {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    return new ServerConfigRepository(context);
  }

  private readerSettingsRepository(): ReaderSettingsRepository {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    return new ReaderSettingsRepository(context);
  }

  private imageCache(): ImageDiskCache {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    return new ImageDiskCache(context, this.serverUrl);
  }

  private describeError(error: Object): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return '档案加载失败';
  }
}
