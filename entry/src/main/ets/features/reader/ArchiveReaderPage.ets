import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { ImageDiskCache } from '../../data/cache/ImageDiskCache';
import { OfflineArchiveCache, OfflineArchiveRecord } from '../../data/cache/OfflineArchiveCache';
import { OfflineProgressRepository } from '../../data/download/OfflineProgressRepository';
import {
  ReaderSettings,
  ReaderSettingsRepository
} from '../../data/config/ReaderSettingsRepository';
import { ServerConfigRepository } from '../../data/config/ServerConfigRepository';
import {
  ImageProgressCallback,
  LanraragiApiClient
} from '../../data/network/LanraragiApiClient';
import {
  ArchiveIndexPayload,
  ArchiveInfoRouteParams,
  ArchiveItem,
  ArchivePagesResult,
  ReaderPage,
  ReaderRouteParams,
  ServerConfig
} from '../../domain/model/LanraragiModels';
import { describeUserFacingError, localized } from '../../common/Localization';
import { AppLog } from '../../data/log/AppLog';

// Keep the decoded page at a useful reading resolution instead of decoding an
// arbitrarily large source image and asking the renderer to shrink it later.
// These limits mirror LANreader's ImageService policy and leave enough detail
// for page zoom while avoiding the worst aliasing/memory cases.
const MAX_READER_DECODE_LONG_EDGE: number = 4096;
const MAX_READER_DECODE_BYTES: number = 64 * 1024 * 1024;
const RGBA_BYTES_PER_PIXEL: number = 4;

// Every paged image is wrapped in a zoomable Scroll, and Scroll only supports
// pinch zoom while scrollable is ScrollDirection.FREE. ArkUI arbitrates nested
// scrollable gestures child-first, so that Scroll claims the horizontal pan and
// the Swiper never sees it. The reader therefore recognizes the horizontal
// swipe itself, in parallel with the page content, and turns the page through
// the Swiper controller.
const READER_SWIPE_TRIGGER_DISTANCE: number = 12;
const READER_SWIPE_TURN_MIN_DISTANCE: number = 36;
const READER_SWIPE_TURN_VIEWPORT_RATIO: number = 0.12;
const READER_ZOOM_ACTIVE_SCALE: number = 1.01;
// The controls overlay lets touches through to the page below it so that tapping
// the margins still works, so a scrub on the progress bar would otherwise also
// register as a page-turn swipe. This reserves the bar at the bottom of the page.
const READER_CONTROLS_BAR_HEIGHT: number = 100;
// A swipe slides to the next page over this duration (the Swiper's own
// transition timing); taps and slider moves stay instantaneous.
const READER_PAGE_TURN_DURATION_MS: number = 300;
// A cached page still has to be decoded, so it announces a loading state before
// the decode completes even though nothing is downloaded.
const READER_CACHED_PAGE_BYTES: number = 1;
// A page the reader is only preloading waits this long, times its distance from
// the current page, before it starts downloading. Every page of a document used
// to start at once, so the page the user was actually looking at competed for
// the connection with three to five pages behind it. The delay is invisible for
// a page that is off screen, and the current page never waits.
const READER_PRELOAD_STAGGER_MS: number = 150;
// Waiting for an on-demand extraction: how long between polls, and how many.
// Two minutes of patience covers a large archive on slow hardware without
// holding the reader on a spinner forever.
const READER_EXTRACT_RETRY_DELAY_MS: number = 2500;
const READER_EXTRACT_RETRY_LIMIT: number = 48;

/** How far a page has got towards being displayed. */
export enum ReaderPageLoadState {
  Loading = 0,
  Loaded = 1,
  Failed = 2
}

/**
 * Encoding of an image buffer, read from its magic bytes.
 *
 * This is what separates "the server sent WebP" from "the server sent an HTML
 * error page" in a log: both fail to decode, and without the container format a
 * bug report cannot be acted on.
 */
function describeImageFormat(buffer: ArrayBuffer): string {
  const head: Uint8Array = new Uint8Array(buffer.slice(0, 16));
  if (head.length >= 12 && head[0] === 0x52 && head[1] === 0x49 && head[2] === 0x46 &&
    head[3] === 0x46 && head[8] === 0x57 && head[9] === 0x45 && head[10] === 0x42) {
    return head[12] === 0x56 && head[13] === 0x50 && head[14] === 0x38 &&
      head[15] === 0x58 ? 'webp(lossless)' : 'webp';
  }
  if (head.length >= 3 && head[0] === 0xFF && head[1] === 0xD8 && head[2] === 0xFF) {
    return 'jpeg';
  }
  if (head.length >= 8 && head[0] === 0x89 && head[1] === 0x50 && head[2] === 0x4E &&
    head[3] === 0x47) {
    return 'png';
  }
  if (head.length >= 4 && head[0] === 0x47 && head[1] === 0x49 && head[2] === 0x46) {
    return 'gif';
  }
  if (head.length >= 2 && head[0] === 0x42 && head[1] === 0x4D) {
    return 'bmp';
  }
  // A document served in place of an image is a common failure, and naming it
  // saves a round trip.
  if (head.length >= 15 && head[0] === 0x3C) {
    return 'html-or-xml';
  }
  return `unknown(${Array.from(head.slice(0, 4)).map((b: number) => b.toString(16).padStart(2, '0')).join(' ')})`;
}

/** Compact byte count for the loading readout, e.g. `1.2 MB`. */
function formatBytes(bytes: number): string {  if (!Number.isFinite(bytes) || bytes <= 0) {
    return '0 B';
  }
  if (bytes < 1024) {
    return `${Math.round(bytes)} B`;
  }
  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KB`;
  }
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function readerDecodeSize(info: image.ImageInfo): image.Size | undefined {
  const sourceWidth: number = Math.max(Math.floor(info.size.width), 1);
  const sourceHeight: number = Math.max(Math.floor(info.size.height), 1);
  const sourceLongEdge: number = Math.max(sourceWidth, sourceHeight);
  const sourceBytes: number = sourceWidth * sourceHeight * RGBA_BYTES_PER_PIXEL;
  const edgeScale: number = MAX_READER_DECODE_LONG_EDGE / sourceLongEdge;
  const byteScale: number = Math.sqrt(MAX_READER_DECODE_BYTES / sourceBytes);
  const scale: number = Math.min(1, edgeScale, byteScale);

  if (scale >= 1) {
    return undefined;
  }
  return {
    width: Math.max(Math.floor(sourceWidth * scale), 1),
    height: Math.max(Math.floor(sourceHeight * scale), 1)
  };
}

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
  @Prop doublePage: boolean = false;
  @Prop imageAlignment: Alignment = Alignment.Center;
  // This is a one-way input so an active waterfall page is relaid out when
  // the parent changes the reading width. Keeping it on the page component
  // avoids scaling the List viewport itself.
  @Prop contentWidthPercent: number = 100;
  @Prop interpolationIndex: number = 3;
  // Pages outside this window are neither waiting nor preloading, so they never
  // report: a waterfall list keeps hundreds of children alive and a rebuild per
  // finished page would be pure noise. The window moves as the reader turns
  // pages, so a page decoded while it was outside reports again when it enters.
  @Prop @Watch('onReportWindowChanged') reportWindowStart: number = 1;
  @Prop @Watch('onReportWindowChanged') reportWindowEnd: number = 1;
  // Set by the parent for the page being displayed. Decides whether this page
  // skips the download queue, so it is read before the report window settles.
  @Prop pageIsCurrent: boolean = false;
  onZoomChanged: (scale: number) => void = (scale: number): void => {};
  onLoadStateChanged: (pageNumber: number, state: ReaderPageLoadState) => void =
    (pageNumber: number, state: ReaderPageLoadState): void => {};
  @State private pixelMap: image.PixelMap | undefined = undefined;
  @State private isLoading: boolean = false;
  @State private errorMessage: string = '';
  @State private imageAspectRatio: number = 0.707;
  @State private zoomScale: number = 1;
  @State private viewportWidth: number = 1;
  @State private viewportHeight: number = 1;
  @State private progressReceived: number = 0;
  @State private progressTotal: number = 0;
  // Set when the component is destroyed; a decode still awaiting at that point
  // would otherwise assign `pixelMap` after the only release ran.
  private destroyed: boolean = false;
  // Pending preload delay, or -1. Cleared with the component so a page that is
  // scrolled away never starts a download it no longer needs.
  private preloadTimer: number = -1;

  aboutToAppear(): void {
    this.scheduleLoad();
  }

  /**
   * Starts this page's download, unless it is only being preloaded.
   *
   * A preloaded page gives the current one a head start: it waits a moment that
   * grows with its distance from the current page, so the reader's own requests
   * are sent and answered first. Opening the page while it waits loads it
   * immediately, and the pending timer is cancelled with the component.
   */
  private scheduleLoad(): void {
    if (!this.isPreloadedPage()) {
      this.loadImage();
      return;
    }
    const distance: number = Math.max(this.page.pageNumber - this.reportWindowStart, 1);
    try {
      this.preloadTimer = setTimeout(() => {
        this.preloadTimer = -1;
        this.loadImage();
      }, READER_PRELOAD_STAGGER_MS * distance);
    } catch (error) {
      // Without a timer the page waits for its turn in the list instead.
    }
  }

  /** True for a page that is only fetched ahead of the current one. */
  private isPreloadedPage(): boolean {
    return this.reportWindowStart > 0 && this.page.pageNumber > this.reportWindowStart;
  }

  aboutToBeDeleted(): void {
    this.destroyed = true;
    if (this.preloadTimer >= 0) {
      clearTimeout(this.preloadTimer);
      this.preloadTimer = -1;
    }
    this.releasePageImage();
  }

  private releasePageImage(): void {
    if (this.pixelMap !== undefined) {
      this.pixelMap.release().catch(() => {});
      this.pixelMap = undefined;
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
        .onAreaChange((oldValue: Area, newValue: Area) => {
          if (typeof newValue.width === 'number' && newValue.width > 0) {
            this.viewportWidth = newValue.width;
          }
          if (typeof newValue.height === 'number' && newValue.height > 0) {
            this.viewportHeight = newValue.height;
          }
        })
        .backgroundColor(Color.Black)
      }
  }

  @Builder
  private imageContent() {
    Stack({
      alignContent: this.doublePage ? this.imageAlignment : Alignment.Center
    }) {
      if (this.pixelMap !== undefined) {
        if (this.doublePage) {
          if (this.shouldFitDoublePageByWidth()) {
            Image(this.pixelMap as image.PixelMap)
              .width('100%')
              .aspectRatio(this.imageAspectRatio)
              .objectFit(ImageFit.Fill)
              .interpolation(this.imageInterpolation())
          } else {
            Image(this.pixelMap as image.PixelMap)
              .height('100%')
              .aspectRatio(this.imageAspectRatio)
              .objectFit(ImageFit.Fill)
              .interpolation(this.imageInterpolation())
          }
        } else {
          Image(this.pixelMap as image.PixelMap)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .interpolation(this.imageInterpolation())
        }
      } else if (this.isLoading) {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(42)
            .height(42)
            .color(Color.White)
          Text(localized(`正在加载第 ${this.page.pageNumber} 页`,
            `Loading page ${this.page.pageNumber}`))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(14)
            .fontColor('#D9FFFFFF')
          // A cached page reports a byte count too, so the decode phase of a
          // large page shows a readout instead of only a spinner.
          if (this.progressReceived > 0) {
            this.percentProgress()
          }
        }
      } else {
        Column({ space: 12 }) {
          Text(this.errorMessage.length > 0 ? this.errorMessage : localized('页面加载失败'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(15)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
          Button(localized('重试'))
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

  @Builder
  private percentProgress() {
    Column({ space: 7 }) {
      Row() {
        Text(this.progressPercent() >= 100 ?
          localized('正在解码…') : localized('正在下载…'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .fontColor('#B3FFFFFF')
          .layoutWeight(1)

        Text(`${this.progressPercent()}%`)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
      }
      .width('100%')

      Progress({
        value: this.progressReceived,
        total: this.progressTotal,
        type: ProgressType.Linear
      })
        .width('100%')
        .height(4)
        .color('#FF3F7CFF')
        .backgroundColor('#40FFFFFF')

      Text(`${formatBytes(this.progressReceived)} / ${formatBytes(this.progressTotal)}`)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#99FFFFFF')
        .width('100%')
        .textAlign(TextAlign.End)
    }
    .width(230)
  }

  private progressPercent(): number {
    if (this.progressTotal <= 0) {
      // Bytes are already here — the page came from the cache — so nothing is
      // left but the decode. `READER_CACHED_PAGE_BYTES` is what marks that.
      return this.progressReceived > 0 ? 100 : 0;
    }
    return Math.min(Math.round(this.progressReceived / this.progressTotal * 100), 100);
  }

  private shouldFitDoublePageByWidth(): boolean {
    if (this.viewportWidth <= 0 || this.viewportHeight <= 0) {
      return true;
    }
    return this.imageAspectRatio >= this.viewportWidth / this.viewportHeight;
  }

  private imageInterpolation(): ImageInterpolation {
    switch (this.interpolationIndex) {
      case 0:
        return ImageInterpolation.None;
      case 1:
        return ImageInterpolation.Low;
      case 2:
        return ImageInterpolation.Medium;
      default:
        return ImageInterpolation.High;
    }
  }

  private async loadImage(): Promise<void> {
    // Reached either right away for the current page, or after the preload
    // delay. Either way the wait is over now.
    if (this.preloadTimer >= 0) {
      clearTimeout(this.preloadTimer);
      this.preloadTimer = -1;
    }
    if (this.isLoading || this.destroyed || this.page.path.length === 0) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';
    this.progressReceived = 0;
    this.progressTotal = 0;
    this.reportLoadState(ReaderPageLoadState.Loading);
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const cache: ImageDiskCache = new ImageDiskCache(context, this.serverUrl);
      const offlineCache: OfflineArchiveCache =
        new OfflineArchiveCache(context, this.serverUrl);
      let buffer: ArrayBuffer | undefined = offlineCache.readPage(
        this.archiveId,
        this.page.pageNumber
      );
      if (buffer === undefined) {
        buffer = cache.readPage(this.archiveId, this.page.pageNumber);
      }
      let shouldCache: boolean = false;
      if (buffer === undefined) {
        if (this.serverUrl.length === 0) {
          throw new Error(localized('离线页面不存在，请重新下载档案'));
        }
        const client: LanraragiApiClient =
          new LanraragiApiClient(this.serverUrl, this.apiKey);
        buffer = await client.fetchArchivePage(
          this.page,
          this.archiveId,
          (receivedBytes: number, totalBytes: number): void => {
            // The request outlives this component: the progress callback can
            // fire after the page was scrolled away, and writing @State then
            // would wake a destroyed component for the rest of the download.
            if (this.destroyed) {
              return;
            }
            this.progressReceived = receivedBytes;
            this.progressTotal = totalBytes;
          },
          // `priority` means "this is the page being read": it skips the queue.
          // Taken from the parent rather than from the report window, which can
          // still hold its initial value during the first `aboutToAppear`.
          this.pageIsCurrent
        );
        shouldCache = buffer !== undefined;
      } else {
        // A cached page is still decoded, which is the whole wait for a large
        // one on a slow device. Its bytes count as complete, so the readout says
        // the remaining wait is the decode.
        this.progressReceived = READER_CACHED_PAGE_BYTES;
        this.progressTotal = 0;
      }
      if (buffer === undefined) {
        throw new Error(localized('服务器暂未生成该页面'));
      }
      const source: image.ImageSource = image.createImageSource(buffer);
      try {
        const imageInfo: image.ImageInfo = await source.getImageInfo();
        // Checked after the await: the page may have been scrolled away while
        // the header was being read.
        if (this.destroyed) {
          return;
        }
        if (imageInfo.size.width > 0 && imageInfo.size.height > 0) {
          this.imageAspectRatio = imageInfo.size.width / imageInfo.size.height;
        }
        // Written before the decode is attempted: a page that fails to load is
        // exactly when the format and dimensions matter.
        AppLog.detail('reader',
          `page ${this.page.pageNumber} "${this.page.path}" ${buffer.byteLength} bytes ` +
          `format=${describeImageFormat(buffer)} ${imageInfo.size.width}x${imageInfo.size.height}`);
        const decodeSize: image.Size | undefined = readerDecodeSize(imageInfo);
        let decoded: image.PixelMap | undefined = undefined;
        if (decodeSize === undefined) {
          decoded = await source.createPixelMap();
        } else {
          decoded = await source.createPixelMap({
            desiredSize: decodeSize
          });
        }
        if (shouldCache) {
          cache.writePage(this.archiveId, this.page.pageNumber, buffer);
        }
        if (this.destroyed) {
          // The page was scrolled away or left while decoding, so this decode
          // holds the only reference and must be released here.
          decoded.release().catch(() => {});
          return;
        }
        this.pixelMap = decoded;
        this.reportLoadState(ReaderPageLoadState.Loaded);
      } finally {
        await source.release();
      }
    } catch (error) {
      // The message and the load state are only meaningful while the tile is
      // still on screen; a destroyed one must not be written to.
      if (!this.destroyed) {
        this.errorMessage = this.describeError(error);
        AppLog.error('reader',
          `page ${this.page.pageNumber} "${this.page.path}" failed: ` +
          `${AppLog.describe(error)}`);
        this.reportLoadState(ReaderPageLoadState.Failed);
      }
    } finally {
      // Runs even when the early return above skipped the rest: `isLoading` is
      // this component's own flag, and leaving it set would block a retry if the
      // same instance is ever reused.
      this.isLoading = false;
    }
  }

  /**
   * Forwards load state for the pages the reader is showing or is about to show.
   * A waterfall list keeps far-away children alive and silent.
   */
  private reportLoadState(state: ReaderPageLoadState): void {
    if (this.destroyed || !this.isReportedPage()) {
      return;
    }
    this.onLoadStateChanged(this.page.pageNumber, state);
  }

  private isReportedPage(): boolean {
    return this.page.pageNumber >= this.reportWindowStart &&
      this.page.pageNumber <= this.reportWindowEnd;
  }

  /**
   * Re-reports a page whose decode finished before it was in the window.
   *
   * The initial report happens once, when the decode completes; a page that was
   * preloaded off-window at that moment never reported at all, so the reader
   * counted it as missing even though it was ready. Waiting for the window to
   * arrive is what fixes the count, and it also covers a retry that succeeded
   * while the page was not being looked at.
   */
  private onReportWindowChanged(): void {
    if (this.destroyed || this.pixelMap === undefined) {
      return;
    }
    this.reportLoadState(ReaderPageLoadState.Loaded);
  }

  private describeError(error: Object): string {
    return describeUserFacingError(error, localized('页面加载失败'));
  }
}

@Component
export struct ArchiveReaderPage {
  @Consume('pathStack') private pathStack: NavPathStack = new NavPathStack();
  params: ReaderRouteParams = emptyRouteParams();
  onProgressChanged: (archiveId: string, pageNumber: number) => void =
    (archiveId: string, pageNumber: number): void => {};
  onReaderFullscreenChanged: (active: boolean) => void = (active: boolean): void => {};
  @State private pages: Array<ReaderPage> = [];
  @State private currentPageIndex: number = 0;
  @State private isLoading: boolean = false;
  /**
   * Set when the reader is destroyed, so work started for it can stop.
   *
   * Only `aboutToBeDeleted` sets this: `aboutToDisappear` also fires when archive
   * information is pushed on top, and the reader is still there afterwards.
   */
  private disposed: boolean = false;
  /** The pending extraction poll, so it can be cancelled on destroy. */
  private extractionTimer: number = -1;
  @State private errorMessage: string = '';
  @State private serverUrl: string = '';
  @State private apiKey: string = '';
  @State private controlsVisible: boolean = false;
  @State private readerSettingsVisible: boolean = false;
  @State private readDirectionIndex: number = 0;
  @State private readerModeIndex: number = 0;
  @State private doublePageOffset: number = 0;
  @State private preloadPageCount: number = 3;
  @State private interpolationIndex: number = 3;
  // How many of the pages after the current one are ready to display.
  @State private preloadedAheadCount: number = 0;
  @State private preloadedAheadTotal: number = 0;
  // Loading state per page number; only pages near the current one are tracked.
  private pageLoadStates: Map<number, ReaderPageLoadState> =
    new Map<number, ReaderPageLoadState>();
  @State private offlineProgress: number = 0;
  @State private readerViewportWidth: number = 1;
  @State private readerViewportHeight: number = 1;
  @State private waterfallScale: number = 1;
  @State private pageZoomScale: number = 1;
  private waterfallScaleStart: number = 1;
  private horizontalSwipeOffset: number = 0;
  private horizontalSwipeSuppressed: boolean = false;
  private swiperController: SwiperController = new SwiperController();
  private verticalScroller: Scroller = new Scroller();
  private pageDataSource: ReaderPageDataSource = new ReaderPageDataSource();
  private spreadDataSource: ReaderSpreadDataSource = new ReaderSpreadDataSource();
  private readerFullscreenEnabled: boolean = false;
  private readerWindowRequestId: number = 0;

  aboutToAppear(): void {
    this.enterReaderFullscreen();
    this.loadPages();
  }

  aboutToDisappear(): void {
    this.restoreReaderWindow();
  }

  aboutToBeDeleted(): void {
    // Before anything else: work started for this reader checks this flag after
    // every await, so setting it first keeps later writes off a dead component.
    this.disposed = true;
    if (this.extractionTimer >= 0) {
      clearTimeout(this.extractionTimer);
      this.extractionTimer = -1;
    }
    this.restoreReaderWindow();
    // The reader cache exists so a page is not downloaded twice while reading
    // one document, so it is dropped as soon as that document is closed. It is
    // not dropped from `aboutToDisappear`: pushing archive information on top of
    // the reader also triggers that, and the reader is still on the stack.
    // Explicit downloads are unaffected; they live in OfflineArchiveCache. The
    // cover cache is not touched either.
    this.clearReaderPageCache();
  }

  private clearReaderPageCache(): void {
    if (this.params.archive.id.length === 0) {
      return;
    }
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const cache: ImageDiskCache = new ImageDiskCache(context, this.serverUrl);
      cache.clearArchivePagesAsync(this.params.archive.id).catch(() => {});
    } catch (error) {
      // A document that cannot be cleaned up just frees its space later.
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
            Text(localized('正在准备档案…'))
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
            Button(localized('重试'))
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
                      contentWidthPercent: this.waterfallScale * 100,
                      interpolationIndex: this.interpolationIndex,
                      reportWindowStart: this.pageNumberAt(this.currentPageIndex),
                      reportWindowEnd: this.preloadWindowEndPageNumber(),
                      pageIsCurrent: page.pageNumber === this.pageNumberAt(this.currentPageIndex),
                      onLoadStateChanged: (pageNumber: number, state: ReaderPageLoadState): void => {
                        this.handlePageLoadState(pageNumber, state);
                      }
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
            .onAreaChange((oldValue: Area, newValue: Area) => {
              if (typeof newValue.width === 'number' && newValue.width > 0) {
                this.readerViewportWidth = newValue.width;
              }
            })
            .onClick((event: ClickEvent) => {
              this.toggleControlsFromCenter(event.x);
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
            .duration(READER_PAGE_TURN_DURATION_MS)
            .direction(this.readDirectionIndex === 1 ? Direction.Rtl : Direction.Ltr)
            .cachedCount(this.preloadPageCount)
            .disableSwipe(true)
            .onChange((index: number) => {
              this.pageZoomScale = 1;
              this.onVisibleSpreadChanged(index);
            })
            .parallelGesture(
              PanGesture({
                fingers: 1,
                direction: PanDirection.Horizontal,
                distance: READER_SWIPE_TRIGGER_DISTANCE
              })
                .onActionStart((event: GestureEvent) => {
                  this.handleReaderSwipeStart(event);
                })
                .onActionUpdate((event: GestureEvent) => {
                  this.handleReaderSwipeUpdate(event);
                })
                .onActionEnd(() => {
                  this.handleReaderSwipeEnd();
                })
                .onActionCancel(() => {
                  this.handleReaderSwipeCancel();
                })
            )
            .width('100%')
            .height('100%')
            .onAreaChange((oldValue: Area, newValue: Area) => {
              if (typeof newValue.width === 'number' && newValue.width > 0) {
                this.readerViewportWidth = newValue.width;
              }
              if (typeof newValue.height === 'number' && newValue.height > 0) {
                this.readerViewportHeight = newValue.height;
              }
            })
            .onClick((event: ClickEvent) => {
              this.handleHorizontalTap(event.x, event.y);
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
                  interpolationIndex: this.interpolationIndex,
                  reportWindowStart: this.pageNumberAt(this.currentPageIndex),
                  reportWindowEnd: this.preloadWindowEndPageNumber(),
                  pageIsCurrent: page.pageNumber === this.pageNumberAt(this.currentPageIndex),
                  onZoomChanged: (scale: number): void => {
                    this.pageZoomScale = scale;
                  },
                  onLoadStateChanged: (pageNumber: number, state: ReaderPageLoadState): void => {
                    this.handlePageLoadState(pageNumber, state);
                  }
                })
              }, (page: ReaderPage) => `horizontal-${page.pageNumber}`)
            }
            .index(this.currentPageIndex)
            .loop(false)
            .indicator(false)
            .duration(READER_PAGE_TURN_DURATION_MS)
            .direction(this.readDirectionIndex === 1 ? Direction.Rtl : Direction.Ltr)
            .cachedCount(this.preloadPageCount)
            .disableSwipe(true)
            .onChange((index: number) => {
              this.pageZoomScale = 1;
              this.onVisiblePageChanged(index);
            })
            .parallelGesture(
              PanGesture({
                fingers: 1,
                direction: PanDirection.Horizontal,
                distance: READER_SWIPE_TRIGGER_DISTANCE
              })
                .onActionStart((event: GestureEvent) => {
                  this.handleReaderSwipeStart(event);
                })
                .onActionUpdate((event: GestureEvent) => {
                  this.handleReaderSwipeUpdate(event);
                })
                .onActionEnd(() => {
                  this.handleReaderSwipeEnd();
                })
                .onActionCancel(() => {
                  this.handleReaderSwipeCancel();
                })
            )
            .width('100%')
            .height('100%')
            .onAreaChange((oldValue: Area, newValue: Area) => {
              if (typeof newValue.width === 'number' && newValue.width > 0) {
                this.readerViewportWidth = newValue.width;
              }
              if (typeof newValue.height === 'number' && newValue.height > 0) {
                this.readerViewportHeight = newValue.height;
              }
            })
            .onClick((event: ClickEvent) => {
              this.handleHorizontalTap(event.x, event.y);
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
              .accessibilityText(localized('返回档案库'))
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
                  localized('当前从第一页开始双页配对，点击改为第二页开始', 'Currently pairing from page 1; tap to start from page 2') :
                  localized('当前从第二页开始双页配对，点击改为第一页开始', 'Currently pairing from page 2; tap to start from page 1'))
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
                .accessibilityText(localized('重置瀑布页面宽度'))
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
              .accessibilityText(localized('查看档案标签和操作'))
              .onClick(() => {
                this.openArchiveInfo();
              })

            Button() {
              Image($r('app.media.icon_settings'))
                .width(23)
                .height(23)
                .renderMode(ImageRenderMode.Template)
                .fillColor(Color.White)
            }
              .width(44)
              .height(44)
              .backgroundColor('#99000000')
              .accessibilityText(localized('当前文档阅读设置'))
              .onClick(() => {
                this.readerSettingsVisible = true;
              })
          }
          .width('100%')
          .padding({ left: 10, right: 10 })
          .position({ x: 0, y: 10 })

          Stack({ alignContent: Alignment.Bottom }) {
            Column({ space: 10 }) {
              this.preloadedAheadRow()

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

        if (this.readerSettingsVisible) {
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('#66000000')
              .onClick(() => {
                this.readerSettingsVisible = false;
              })

            Column({ space: 18 }) {
              Row() {
                Text(localized('当前文档阅读设置'))
                  .copyOption(CopyOptions.LocalDevice)
                  .fontSize(19)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .layoutWeight(1)

              }
              .width('100%')

              Text(localized('阅读方式'))
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(14)
                .fontColor('#CCFFFFFF')
                .width('100%')

              Row({ space: 8 }) {
                ForEach([localized('单页阅读'), localized('双页阅读'), localized('瀑布连续阅读')],
                  (label: string, index: number) => {
                    Button() {
                      Text(label)
                        .copyOption(CopyOptions.LocalDevice)
                        .fontSize(14)
                        .fontColor(Color.White)
                        .maxLines(1)
                        .hitTestBehavior(HitTestMode.None)
                    }
                      .layoutWeight(1)
                      .height(44)
                      .backgroundColor(this.readerModeIndex === index ?
                        '#CC3F7CFF' : '#664A5068')
                      .borderRadius(12)
                      .onClick(() => {
                        this.applyCurrentReaderMode(index);
                      });
                  },
                  (label: string) => `reader-mode-${label}`)
              }
              .width('100%')

              Divider()
                .color('#33FFFFFF')

              Text(localized('阅读方向'))
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(14)
                .fontColor('#CCFFFFFF')
                .width('100%')

              Row({ space: 8 }) {
                ForEach([localized('从左向右'), localized('从右向左')],
                  (label: string, index: number) => {
                    Button() {
                      Text(label)
                        .copyOption(CopyOptions.LocalDevice)
                        .fontSize(14)
                        .fontColor(Color.White)
                        .hitTestBehavior(HitTestMode.None)
                    }
                      .layoutWeight(1)
                      .height(44)
                      .backgroundColor(this.readDirectionIndex === index ?
                        '#CC3F7CFF' : '#664A5068')
                      .borderRadius(12)
                      .onClick(() => {
                        this.applyCurrentReaderDirection(index);
                      });
                  },
                  (label: string) => `reader-direction-${label}`)
              }
              .width('100%')

              Text(localized('仅对当前文档生效，不会修改设置页中的全局默认值'))
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(12)
                .fontColor('#99FFFFFF')
                .width('100%')
            }
            .width('88%')
            .padding(20)
            .backgroundColor('#E61C2434')
            .borderRadius(24)
            .border({ width: 1, color: '#55FFFFFF' })
            .shadow({ radius: 24, color: '#99000000', offsetX: 0, offsetY: 8 })
          }
          .width('100%')
          .height('100%')
          .position({ x: 0, y: 0 })
          .zIndex(20)
        }
      }
      .width('100%')
      .height(LayoutPolicy.matchParent)
      .ignoreLayoutSafeArea()
      .backgroundColor(Color.Black)
    }
    .hideTitleBar(true)
    .onActive(() => {
      this.enterReaderFullscreen();
    })
    .onInactive(() => {
      this.restoreReaderWindow();
    })
  }

  @Builder
  private doublePageSpread(spread: ReaderSpread) {
    Row({ space: 0 }) {
      if (this.readDirectionIndex === 1) {
        this.doublePageSlot(spread.laterPage, Alignment.End)
        this.doublePageSlot(spread.earlierPage, Alignment.Start)
      } else {
        this.doublePageSlot(spread.earlierPage, Alignment.End)
        this.doublePageSlot(spread.laterPage, Alignment.Start)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FF101010')
  }

  @Builder
  private doublePageSlot(page: ReaderPage | undefined, alignment: Alignment) {
    Stack() {
      if (page !== undefined) {
        ReaderImageView({
          page: page as ReaderPage,
          archiveId: this.params.archive.id,
          serverUrl: this.serverUrl,
          apiKey: this.apiKey,
          continuous: false,
          doublePage: true,
          imageAlignment: alignment,
          interpolationIndex: this.interpolationIndex,
          reportWindowStart: this.pageNumberAt(this.currentPageIndex),
          reportWindowEnd: this.preloadWindowEndPageNumber(),
          pageIsCurrent: page.pageNumber === this.pageNumberAt(this.currentPageIndex),
          onZoomChanged: (scale: number): void => {
            this.pageZoomScale = scale;
          },
          onLoadStateChanged: (pageNumber: number, state: ReaderPageLoadState): void => {
            this.handlePageLoadState(pageNumber, state);
          }
        })
      }
    }
    .layoutWeight(1)
    .height('100%')
    .backgroundColor(Color.Black)
  }

  /**
   * How many pages after the current one are ready.
   *
   * A ratio rather than one mark per page: pages finish out of order, so a row
   * of dots would suggest an order that does not exist. The download itself is
   * reported on the page in the middle, not here.
   */
  @Builder
  private preloadedAheadRow() {
    Row({ space: 10 }) {
      Text(this.preloadedAheadLabel())
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(12)
        .fontColor('#CCFFFFFF')
        .hitTestBehavior(HitTestMode.None)

      Progress({
        value: this.preloadedAheadCount,
        total: Math.max(this.preloadedAheadTotal, 1),
        type: ProgressType.Linear
      })
        .width(84)
        .height(4)
        .color('#FF3F7CFF')
        .backgroundColor('#40FFFFFF')
    }
    .width('100%')
  }

  private preloadedAheadLabel(): string {
    if (this.preloadedAheadTotal === 0) {
      return localized('未预载后续页');
    }
    return `${localized('已预载')} ${this.preloadedAheadCount}/${this.preloadedAheadTotal} ${localized('页', 'pages')}`;
  }

  /**
   * Fetches the page list, waiting out an on-demand extraction.
   *
   * LANraragi extracts an archive the first time it is read: that request comes
   * back empty with a Minion job, and the pages only appear once the job has
   * run. Treating the empty answer as a failure sent the reader to an error page
   * for an archive that was merely being prepared.
   */
  /**
   * Polls until the server has finished preparing the archive.
   *
   * Stops as soon as the reader is gone: the server keeps extracting either way,
   * but here the requests and the wait would outlive the screen that asked for
   * them — up to the retry limit, roughly two minutes.
   */
  private async loadPagesFromServer(client: LanraragiApiClient): Promise<Array<ReaderPage>> {
    let attempts: number = 0;
    while (true) {
      if (this.disposed) {
        return [];
      }
      const result: ArchivePagesResult =
        await client.fetchArchivePagesResult(this.params.archive.id);
      // Checked again after the request: the reader may have been closed while
      // it was in flight.
      if (this.disposed) {
        return [];
      }
      if (result.pages.length > 0 || !result.isPreparing) {
        return result.pages;
      }
      attempts += 1;
      if (attempts > READER_EXTRACT_RETRY_LIMIT) {
        throw new Error(localized('服务器仍在解压该档案，请稍后重试'));
      }
      // The job is already running on the server; this is only the wait for it.
      await this.waitForExtraction();
    }
  }

  /**
   * Waits between extraction polls.
   *
   * The timer is tracked so it can be cleared when the reader closes, rather
   * than leaving a pending callback holding the wait open.
   */
  private waitForExtraction(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      if (this.disposed) {
        resolve();
        return;
      }
      this.extractionTimer = setTimeout(() => {
        this.extractionTimer = -1;
        resolve();
      }, READER_EXTRACT_RETRY_DELAY_MS);
    });
  }

  private async loadPages(): Promise<void> {
    if (this.isLoading || this.disposed || this.params.archive.id.length === 0) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';
    try {
      try {
        const settings: ReaderSettings =
          await this.readerSettingsRepository().load();
        // The reader may have been closed while the settings were loading.
        if (this.disposed) {
          return;
        }
        this.readDirectionIndex = settings.directionIndex;
        this.readerModeIndex = settings.modeIndex;
        this.doublePageOffset = settings.doublePageOffset;
        this.controlsVisible = false;
        this.preloadPageCount = settings.preloadPageCount;
        this.interpolationIndex = settings.interpolationIndex;
      } catch (settingsError) {
        // Reader defaults remain available if local preferences cannot be read.
      }
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      let config: ServerConfig = new ServerConfig();
      try {
        config = await this.repository().load();
      } catch (configError) {
        if (!this.params.offline) {
          throw configError instanceof Error ? configError :
            new Error(localized('请先在设置中配置服务器'));
        }
      }
      if (this.disposed) {
        return;
      }
      this.serverUrl = this.params.offlineServerUrl.length > 0 ?
        this.params.offlineServerUrl : config.serverUrl;
      this.apiKey = config.apiKey;
      const offlineCache: OfflineArchiveCache =
        new OfflineArchiveCache(context, this.serverUrl);
      const offlineRecord: OfflineArchiveRecord | undefined =
        offlineCache.readRecord(this.params.archive.id);
      let loadedPages: Array<ReaderPage> = offlineRecord?.pages ?? [];
      if (loadedPages.length === 0) {
        if (config.serverUrl.length === 0) {
          throw new Error(localized('请先在设置中配置服务器'));
        }
        const client: LanraragiApiClient =
          new LanraragiApiClient(config.serverUrl, config.apiKey);
        loadedPages = await this.loadPagesFromServer(client);
      }
      if (this.disposed) {
        // The polling loop returns an empty list when the reader is gone, so
        // this is also what stops a closed reader from reporting an error.
        return;
      }
      if (loadedPages.length === 0) {
        throw new Error(localized('服务器返回的页面列表为空'));
      }
      this.pages = loadedPages;
      this.pageDataSource.replace(loadedPages);
      this.rebuildSpreads();
      if (this.params.offline) {
        this.offlineProgress = await new OfflineProgressRepository(context)
          .load(this.params.archive.id);
      }
      if (this.disposed) {
        return;
      }
      const initialIndex: number = this.initialPageIndex(loadedPages.length);
      this.currentPageIndex = this.readerModeIndex === 1 ?
        this.spreadEndIndexForPage(initialIndex) : initialIndex;
      this.pageLoadStates.clear();
      this.refreshPreloadedAheadCount();
      AppLog.info('reader',
        `opened ${this.params.archive.id} mode=${this.readerModeIndex} ` +
        `pages=${loadedPages.length} start=${this.currentPageIndex + 1} ` +
        `preload=${this.preloadPageCount} offline=${this.params.offline}`);
    } catch (error) {
      if (!this.disposed) {
        this.errorMessage = this.describeError(error);
        this.pages = [];
        this.pageDataSource.replace([]);
        this.spreadDataSource.replace([]);
      }
    } finally {
      if (!this.disposed) {
        this.isLoading = false;
      }
    }
  }

  private initialPageIndex(pageCount: number): number {
    if (this.params.offline) {
      if (this.params.fromStart || this.offlineProgress <= 0) {
        return 0;
      }
      return Math.min(Math.max(this.offlineProgress - 1, 0), pageCount - 1);
    }
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
    this.refreshPreloadedAheadCount();
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
    this.refreshPreloadedAheadCount();
    this.syncProgress(this.pages[spread.endIndex]);
  }

  /** The one-based page number of a zero-based registry index, or 0 if invalid. */
  private pageNumberAt(index: number): number {
    if (index < 0 || index >= this.pages.length) {
      return 0;
    }
    return this.pages[index].pageNumber;
  }

  /**
   * Last page the reader preloads past the current one.
   *
   * `Swiper.cachedCount(n)` keeps `n` pages alive beyond the current one in
   * single-page mode, and `n` spreads — two pages each — in two-page mode, so
   * that is exactly how many can ever be reported ready: the window has to match
   * it or the count can never fill up. With preloading off the window is empty,
   * which is also all the cache holds.
   */
  private preloadWindowEndPageNumber(): number {
    const start: number = this.pageNumberAt(this.currentPageIndex);
    if (start === 0) {
      return 0;
    }
    const pagesPerTurn: number = this.readerModeIndex === 1 ? 2 : 1;
    return start + Math.max(this.preloadPageCount, 0) * pagesPerTurn;
  }

  private handlePageLoadState(pageNumber: number, state: ReaderPageLoadState): void {
    this.pageLoadStates.set(pageNumber, state);
    this.refreshPreloadedAheadCount();
  }

  /**
   * Counts how many of the next pages are ready to display.
   *
   * Only the pages preloading is configured to fetch are counted, from the one
   * right after the current page up to that window, so the number answers
   * "how many pages can I turn to without waiting".
   */
  private refreshPreloadedAheadCount(): void {
    let total: number = 0;
    let loaded: number = 0;
    const startIndex: number = this.currentPageIndex + 1;
    const endPageNumber: number = this.preloadWindowEndPageNumber();
    for (let index: number = startIndex; index < this.pages.length; index += 1) {
      const pageNumber: number = this.pages[index].pageNumber;
      if (pageNumber > endPageNumber) {
        break;
      }
      total += 1;
      if (this.pageLoadStates.get(pageNumber) === ReaderPageLoadState.Loaded) {
        loaded += 1;
      }
    }
    this.preloadedAheadTotal = total;
    this.preloadedAheadCount = loaded;
  }

  private goToPage(targetIndex: number, animated: boolean = false): void {
    if (targetIndex < 0 || targetIndex >= this.pages.length) {
      return;
    }
    if (animated) {
      // Let the Swiper own the transition. Publishing the index here would make
      // the bound Swiper index jump to the target and cancel the slide, so the
      // settled index is published from onChange instead.
      this.moveReaderToIndex(targetIndex, true);
      return;
    }
    this.currentPageIndex = targetIndex;
    this.refreshPreloadedAheadCount();
    this.moveReaderToIndex(targetIndex, false);
    this.syncProgress(this.pages[targetIndex]);
  }

  private handleHorizontalTap(localX: number, localY: number): void {
    if (this.isInsideControlsBar(localY)) {
      // The controls own this band; turning a page here would fight the slider.
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
    this.toggleControlsFromCenter(localX);
  }

  private handleReaderSwipeStart(event: GestureEvent): void {
    this.horizontalSwipeOffset = 0;
    this.horizontalSwipeSuppressed = this.isReaderSwipeSuppressed(event);
  }

  private handleReaderSwipeUpdate(event: GestureEvent): void {
    if (event.fingerList.length > 1) {
      // A second finger means the reader is pinching to zoom, not turning a page.
      this.horizontalSwipeSuppressed = true;
    }
    this.horizontalSwipeOffset = event.offsetX;
  }

  private handleReaderSwipeEnd(): void {
    const offsetX: number = this.horizontalSwipeOffset;
    const suppressed: boolean = this.horizontalSwipeSuppressed;
    this.resetReaderSwipe();
    if (!suppressed) {
      this.turnPageBySwipe(offsetX);
    }
  }

  private handleReaderSwipeCancel(): void {
    this.resetReaderSwipe();
  }

  private resetReaderSwipe(): void {
    this.horizontalSwipeOffset = 0;
    this.horizontalSwipeSuppressed = false;
  }

  private isReaderSwipeSuppressed(event: GestureEvent): boolean {
    if (event.fingerList.length > 1) {
      return true;
    }
    if (event.fingerList.length === 0) {
      return false;
    }
    return this.isInsideControlsBar(event.fingerList[0].localY);
  }

  /**
   * True when a touch is on the controls bar rather than on the page.
   *
   * The overlay lets touches through to the page below it (`HitTestMode.
   * Transparent`), so the page-turn gesture has to exclude this band itself:
   * otherwise a tap on the page number or the left end of the slider also turns
   * a page. The swipe path has always done this; the tap path did not.
   */
  private isInsideControlsBar(localY: number): boolean {
    if (!this.controlsVisible || this.readerViewportHeight <= 0) {
      return false;
    }
    return localY >= this.readerViewportHeight - READER_CONTROLS_BAR_HEIGHT;
  }

  private turnPageBySwipe(offsetX: number): void {
    // While a page is zoomed in, a horizontal drag pans the image instead.
    if (this.pageZoomScale > READER_ZOOM_ACTIVE_SCALE) {
      return;
    }
    const threshold: number = Math.max(
      this.readerViewportWidth * READER_SWIPE_TURN_VIEWPORT_RATIO,
      READER_SWIPE_TURN_MIN_DISTANCE
    );
    if (Math.abs(offsetX) < threshold) {
      return;
    }
    // Dragging the page to the left advances a left-to-right document, while a
    // right-to-left document advances when the page is dragged to the right.
    const swipedForward: boolean = this.readDirectionIndex === 1 ?
      offsetX > 0 : offsetX < 0;
    this.goToReadingStep(swipedForward ? 1 : -1, true);
  }

  private toggleControlsFromCenter(localX: number): void {
    const centerBoundary: number = this.readerViewportWidth * 0.35;
    const rightBoundary: number = this.readerViewportWidth * 0.65;
    if (localX >= centerBoundary && localX <= rightBoundary) {
      this.controlsVisible = !this.controlsVisible;
    }
  }

  private moveReaderToIndex(targetIndex: number, animated: boolean = false): void {
    if (this.readerModeIndex === 2) {
      this.verticalScroller.scrollToIndex(targetIndex, animated, ScrollAlign.START);
    } else if (this.readerModeIndex === 1) {
      this.swiperController.changeIndex(this.spreadIndexForPage(targetIndex), animated);
    } else {
      this.swiperController.changeIndex(targetIndex, animated);
    }
  }

  private goToReadingStep(delta: number, animated: boolean = false): void {
    if (this.readerModeIndex !== 1) {
      this.goToPage(this.currentPageIndex + delta, animated);
      return;
    }
    const targetSpreadIndex: number = this.currentSpreadIndex() + delta;
    if (targetSpreadIndex < 0 ||
      targetSpreadIndex >= this.spreadDataSource.totalCount()) {
      return;
    }
    const target: ReaderSpread = this.spreadDataSource.getData(targetSpreadIndex);
    if (animated) {
      // As in goToPage: onChange publishes the settled spread index.
      this.swiperController.changeIndex(targetSpreadIndex, true);
      return;
    }
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

  private applyCurrentReaderMode(modeIndex: number): void {
    const normalizedMode: number = Math.min(Math.max(modeIndex, 0), 2);
    if (normalizedMode === this.readerModeIndex) {
      return;
    }
    const currentPage: number = this.currentPageIndex;
    this.readerModeIndex = normalizedMode;
    this.pageZoomScale = 1;
    this.waterfallScale = 1;
    if (normalizedMode === 1) {
      this.rebuildSpreads();
      this.currentPageIndex = this.spreadEndIndexForPage(currentPage);
    } else {
      this.currentPageIndex = Math.min(
        Math.max(currentPage, 0),
        Math.max(this.pages.length - 1, 0)
      );
    }
    this.refreshPreloadedAheadCount();
  }

  private applyCurrentReaderDirection(directionIndex: number): void {
    this.readDirectionIndex = directionIndex === 1 ? 1 : 0;
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
    this.refreshPreloadedAheadCount();
    this.swiperController.changeIndex(this.currentSpreadIndex(), false);
    this.saveCurrentReaderSettings();
  }

  private async saveCurrentReaderSettings(): Promise<void> {
    try {
      await this.readerSettingsRepository().save(new ReaderSettings(
        this.readDirectionIndex,
        this.readerModeIndex,
        this.doublePageOffset,
        this.preloadPageCount,
        this.interpolationIndex
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
    if (this.params.offline) {
      this.offlineProgress = page.pageNumber;
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      await new OfflineProgressRepository(context).save(
        this.params.archive.id,
        page.pageNumber
      );
      return;
    }
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
      // Update the local library before popping the destination. The callback
      // is synchronous, so the library card is refreshed immediately.
      this.syncProgress(this.pages[this.currentPageIndex]);
    }
    this.restoreReaderWindow();
    this.pathStack.pop();
  }

  private enterReaderFullscreen(): void {
    if (this.readerFullscreenEnabled) {
      return;
    }
    this.readerFullscreenEnabled = true;
    AppStorage.setOrCreate('lanarkReaderFullscreen', true);
    this.onReaderFullscreenChanged(true);
    this.updateReaderWindow(true);
  }

  private restoreReaderWindow(): void {
    if (!this.readerFullscreenEnabled) {
      return;
    }
    this.readerFullscreenEnabled = false;
    this.updateReaderWindow(false);
  }

  private updateReaderWindow(fullscreen: boolean): void {
    const requestId: number = ++this.readerWindowRequestId;
    this.applyReaderWindow(fullscreen, requestId);
  }

  private async applyReaderWindow(fullscreen: boolean, requestId: number): Promise<void> {
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const mainWindow: window.Window = await window.getLastWindow(context);
      if (requestId !== this.readerWindowRequestId) {
        return;
      }
        await mainWindow.setWindowLayoutFullScreen(fullscreen);
      if (requestId !== this.readerWindowRequestId) {
        return;
      }
        // Keep the window immersive and explicitly control each system bar. This avoids
        // the platform re-enabling the navigation indicator after leaving the reader.
        await mainWindow.setSpecificSystemBarEnabled('status', !fullscreen, false);
        await mainWindow.setSpecificSystemBarEnabled('navigation', false, false);
        await mainWindow.setSpecificSystemBarEnabled('navigationIndicator', false, false);
        setTimeout(() => {
          mainWindow.setSpecificSystemBarEnabled('navigationIndicator', false, false)
            .catch(() => {});
        }, 400);
      } catch (error) {
      // Full-screen chrome is optional and must not interrupt reading.
    } finally {
      if (!fullscreen && requestId === this.readerWindowRequestId) {
        AppStorage.setOrCreate('lanarkReaderFullscreen', false);
        this.onReaderFullscreenChanged(false);
      }
    }
  }

  private openArchiveInfo(): void {
    if (this.pages.length > 0 && this.currentPageIndex >= 0 &&
      this.currentPageIndex < this.pages.length) {
      this.syncProgress(this.pages[this.currentPageIndex]);
    }
    this.pathStack.pushPath({
      name: 'ArchiveInfo',
      param: new ArchiveInfoRouteParams(
        this.params.archive,
        this.params.offline,
        this.params.offlineServerUrl
      )
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
    return describeUserFacingError(error, localized('档案加载失败'));
  }
}
