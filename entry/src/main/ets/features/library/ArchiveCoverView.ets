import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { ImageDiskCache } from '../../data/cache/ImageDiskCache';
import { LanraragiApiClient } from '../../data/network/LanraragiApiClient';

/**
 * Thumbnail for one archive, decoded from the disk cache or the server.
 *
 * Shared by the library grid/list and the history list: both show the same
 * covers for the same archive, so the decode, downscale and release rules live
 * in one place instead of being copied per screen.
 */
@Component
export struct ArchiveCoverView {
  archiveId: string = '';
  fileExtension: string = '';
  serverUrl: string = '';
  apiKey: string = '';
  coverWidth: number | string = 68;
  coverHeight: number | string = 92;
  /**
   * Whether a cover may be cropped, decided per image by its shape.
   *
   * Portrait covers fill the card and are trimmed: they are roughly the card's
   * own proportions, so little is lost. Landscape ones are shown whole, since
   * trimming a wide image to a tall card throws away most of the artwork.
   */
  @Prop cropCover: boolean = true;
  @State private cover: image.PixelMap | undefined = undefined;
  @State private isLoading: boolean = false;
  /** False once a decoded cover has been measured and found to be wide. */
  @State private coverIsPortrait: boolean = true;
  // Set when the component is destroyed. A cover decode that is still awaiting
  // when that happens would otherwise assign `cover` after the only release ran.
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
          // A portrait cover fills the card and trims the overflow, which is
          // close to its own shape. A landscape one is kept whole: fitting it to
          // a tall card would discard most of the artwork. `cropCover` is the
          // user's switch for whether any of this happens at all.
          .objectFit(this.cropCover && this.coverIsPortrait ?
            ImageFit.Cover : ImageFit.Contain)
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

  /**
   * Records whether the decoded cover is portrait or landscape.
   *
   * Defaults to portrait on failure, so a cover that cannot be measured keeps
   * the filling behaviour rather than suddenly showing as a small centred image.
   */
  private async measureCover(decoded: image.PixelMap): Promise<void> {
    try {
      const info: image.ImageInfo = await decoded.getImageInfo();
      const width: number = info.size.width;
      const height: number = info.size.height;
      if (width > 0 && height > 0) {
        this.coverIsPortrait = height >= width;
      }
    } catch (error) {
      // Leave the default in place.
    }
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
        let decoded: image.PixelMap | undefined = undefined;
        if (shouldCache) {
          const info: image.ImageInfo = await source.getImageInfo();
          let targetWidth: number = Math.min(info.size.width, 480);
          let targetHeight: number = info.size.width > 0 ?
            Math.max(Math.round(info.size.height * targetWidth / info.size.width), 1) : 720;
          if (targetHeight > 720) {
            targetWidth = Math.max(Math.round(targetWidth * 720 / targetHeight), 1);
            targetHeight = 720;
          }
          decoded = await source.createPixelMap({
            desiredSize: { width: Math.max(targetWidth, 1), height: targetHeight }
          });
        } else {
          decoded = await source.createPixelMap();
        }
        if (this.destroyed) {
          // aboutToBeDeleted already ran, so this decode holds the only
          // reference left; releasing here is the last chance to free it.
          decoded.release().catch(() => {});
          return;
        }
        // Written before the state takes ownership: publishing the PixelMap
        // first would let aboutToBeDeleted release it while the encoder is still
        // reading it, and a shortened encode would be cached for good.
        if (shouldCache) {
          await cache.writeCover(this.archiveId, decoded);
        }
        if (this.destroyed) {
          // Destroyed during the encode; the cache is written, so only the
          // decode result is left to drop.
          decoded.release().catch(() => {});
          return;
        }
        // Measured on the decoded cover, so the cached path is measured too —
        // it never reads the ImageInfo that the encoding path needed.
        await this.measureCover(decoded);
        this.cover = decoded;
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
