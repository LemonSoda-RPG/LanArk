import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppLog } from '../log/AppLog';
import {
  ArchiveIndexPageResult,
  ArchiveItem,
  ArchivePagesPayload,
  ArchivePagesResult,
  ArchiveSearchPayload,
  CategoryItem,
  ReaderPage,
  ServerInfo
} from '../../domain/model/LanraragiModels';
import { localized } from '../../common/Localization';

const REQUEST_TIMEOUT_MS: number = 15_000;
const ARCHIVE_INDEX_TIMEOUT_MS: number = 240_000;
// A single page image should not hold a reader tile for four minutes.
const IMAGE_TIMEOUT_MS: number = 60_000;
// Ceiling for one streamed image, checked as it arrives. The non-stream path is
// capped by the platform, but a stream accumulates until it is told to stop, so
// a wrong URL or a pathological page could otherwise grow without limit.
const MAX_STREAMED_IMAGE_BYTES: number = 64 * 1024 * 1024;

/** Download progress of one image, in bytes. */
export type ImageProgressCallback = (receivedBytes: number, totalBytes: number) => void;

/**
 * Serialises page-image downloads, with the page being read going first.
 *
 * Every page of a document used to start downloading at once, so the reader
 * shared the connection with three to eight pages behind it and the page on
 * screen took as long as any of them. Staggering the starts did not help: a page
 * takes seconds, so a delay of milliseconds left them all in flight together.
 *
 * So the downloads are queued. A page the user is looking at never queues — the
 * bandwidth belongs to it — and a preloading page waits its turn, one at a time.
 * The queue is ordered by distance from the current page, and a queued page that
 * wakes up while the current page is fetching steps aside again.
 */
class PageImageQueue {
  private waiting: Array<number> = [];
  private sequence: number = 0;
  private busy: boolean = false;
  private index: number = -1;
  private priority: number = 0;

  /** Resolves with the ticket to hand back to `release`. */
  async acquire(highPriority: boolean): Promise<number> {
    this.sequence += 1;
    const ticket: number = this.sequence;
    if (highPriority) {
      this.priority += 1;
      AppLog.detail('queue',
        `page image ${this.sequence} runs immediately (page being read, active=${this.priority})`);
      return ticket;
    }
    const position: number = this.waiting.length + 1;
    this.waiting.push(ticket);
    AppLog.detail('queue', `page image ${ticket} queued at position ${position}`);
    while (!this.mayRun(ticket)) {
      await this.pause();
    }
    this.waiting = this.waiting.filter((item: number) => item !== ticket);
    this.busy = true;
    AppLog.detail('queue', `page image ${ticket} started (${this.waiting.length} still waiting)`);
    return ticket;
  }

  release(ticket: number, highPriority: boolean): void {
    if (highPriority) {
      // The page on screen is done; a queued preload may take the bandwidth.
      this.priority = Math.max(this.priority - 1, 0);
      AppLog.detail('queue', `page image ${ticket} finished (page being read)`);
      return;
    }
    this.busy = false;
    AppLog.detail('queue', `page image ${ticket} finished`);
  }

  /** A preloading page defers to the page on screen whenever it is fetching. */
  private isCurrentPageFetching(): boolean {
    return this.priority > 0;
  }

  private mayRun(ticket: number): boolean {
    if (this.isCurrentPageFetching() || this.busy) {
      return false;
    }
    return this.waiting.length > 0 && this.waiting[0] === ticket;
  }

  private pause(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, PAGE_QUEUE_POLL_MS);
    });
  }
}

// How long a queued preload waits before checking its turn again. Short enough
// to start the next page promptly, long enough not to spin.
const PAGE_QUEUE_POLL_MS: number = 50;

export class LanraragiApiClient {
  /**
   * Shared by every client instance: the limit is the network, not one reader.
   * A `Swiper` keeps several pages alive, each with its own client, so a
   * per-instance queue would serialise nothing.
   */
  private static readonly pageQueue: PageImageQueue = new PageImageQueue();
  private readonly baseUrl: string;
  private readonly apiKey: string;

  constructor(serverUrl: string, apiKey: string) {
    this.baseUrl = LanraragiApiClient.normalizeServerUrl(serverUrl);
    this.apiKey = apiKey;
  }

  static normalizeServerUrl(serverUrl: string): string {
    let normalized: string = serverUrl.trim();
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      throw new Error(localized('服务器地址必须以 http:// 或 https:// 开头'));
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.length <= 'http://'.length) {
      throw new Error(localized('请输入完整的服务器地址'));
    }
    return normalized;
  }

  async fetchServerInfo(): Promise<ServerInfo> {
    AppLog.detail('http', `GET ${this.baseUrl}/api/info`);
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(`${this.baseUrl}/api/info`, {
        method: http.RequestMethod.GET,
        header: this.requestHeaders('application/json'),
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: REQUEST_TIMEOUT_MS
      });

      if (response.responseCode !== 200) {
        throw new Error(`${localized('服务器返回 HTTP')} ${response.responseCode}`);
      }
      if (typeof response.result !== 'string') {
        throw new Error(localized('服务器返回了无法识别的数据'));
      }
      const info: ServerInfo = ServerInfo.fromJson(response.result);
      AppLog.info('http', `info ok name="${info.name}" version=${info.version} ` +
        `tracksProgress=${info.serverTracksProgress}`);
      return info;
    } catch (error) {
      AppLog.error('http', `info failed: ${AppLog.describe(error)}`);
      if (error instanceof Error && error.message.length > 0) {
        throw error;
      }
      throw new Error(localized('网络请求失败，请检查服务器地址和网络状态'));
    } finally {
      request.destroy();
    }
  }

  async fetchArchiveIndex(): Promise<Array<ArchiveItem>> {
    AppLog.detail('http', `GET ${this.baseUrl}/api/archives`);
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(`${this.baseUrl}/api/archives`, {
        method: http.RequestMethod.GET,
        header: this.requestHeaders('application/json'),
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: ARCHIVE_INDEX_TIMEOUT_MS
      });

      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`${localized('档案索引请求返回 HTTP')} ${response.responseCode}`);
      }
      if (typeof response.result !== 'string') {
        throw new Error(localized('档案索引格式无法识别'));
      }
      const archives: Array<ArchiveItem> = ArchiveItem.listFromJson(response.result);
      AppLog.detail('http', `index ok: ${archives.length} archives, ` +
        `${response.result.length} bytes`);
      return archives;
    } catch (error) {
      AppLog.error('http', `index failed: ${AppLog.describe(error)}`);
      if (error instanceof Error && error.message.length > 0) {
        throw error;
      }
      throw new Error(localized('档案索引加载失败'));
    } finally {
      request.destroy();
    }
  }

  /**
   * One page of the library listing, driven entirely by server-side parameters.
   *
   * The server pages by its own `archives_per_page` setting and ignores a larger
   * `length`, so a batch arrives with whatever it decides to send; the caller
   * asks again from the new offset until `total` is reached.
   *
   * Ordering, filtering and text search all happen on the server, which is what
   * lets the client hold only the pages it has loaded: a local sort or search
   * over a partial list would give answers that depend on how far the user has
   * scrolled.
   */
  async fetchArchiveIndexPage(start: number, length: number, sortBy: string,
    descending: boolean, filter: string, categoryId: string): Promise<ArchiveIndexPageResult> {
    let path: string =
      `/api/search?start=${start}&length=${length}&sortby=${encodeURIComponent(sortBy)}` +
      `&order=${descending ? 'desc' : 'asc'}`;
    if (filter.length > 0) {
      path += `&filter=${encodeURIComponent(filter)}`;
    }
    if (categoryId.length > 0) {
      path += `&category=${encodeURIComponent(categoryId)}`;
    }
    AppLog.detail('http', `GET ${path}`);
    const responseText: string = await this.fetchJsonText(path, localized('档案索引'));
    const payload: ArchiveSearchPayload = JSON.parse(responseText) as ArchiveSearchPayload;
    const archives: Array<ArchiveItem> = ArchiveItem.listFromPayloads(payload.data);
    AppLog.detail('http',
      `index page: ${archives.length} at ${start}, total ${payload.recordsTotal}`);
    return new ArchiveIndexPageResult(archives, payload.recordsTotal);
  }

  /**
   * A random sample of the library.
   *
   * The server picks these out of the full result of the same search engine, so
   * the sample covers everything the filter matches rather than a page of it.
   * Each call returns a fresh draw.
   */
  async fetchRandomArchives(count: number, categoryId: string,
    filter: string): Promise<Array<ArchiveItem>> {
    let path: string = `/api/search/random?count=${count}`;
    if (categoryId.length > 0) {
      path += `&category=${encodeURIComponent(categoryId)}`;
    }
    if (filter.length > 0) {
      path += `&filter=${encodeURIComponent(filter)}`;
    }
    AppLog.detail('http', `GET ${path}`);
    const responseText: string = await this.fetchJsonText(path, localized('随机档案'));
    const payload: ArchiveSearchPayload = JSON.parse(responseText) as ArchiveSearchPayload;
    return ArchiveItem.listFromPayloads(payload.data);
  }

  async fetchArchiveThumbnail(archiveId: string, page: number = 0): Promise<ArrayBuffer | undefined> {
    const path: string =
      `/api/archives/${archiveId}/thumbnail?no_fallback=true&page=${page}`;
    return this.fetchImage(this.baseUrl + path);
  }

  async fetchCategories(): Promise<Array<CategoryItem>> {
    const responseText: string = await this.fetchJsonText('/api/categories', localized('分类列表'));
    return CategoryItem.listFromJson(responseText);
  }

  async fetchArchivesForCategory(categoryId: string): Promise<Array<ArchiveItem>> {
    const category: string = encodeURIComponent(categoryId);
    const path: string =
      `/api/search?category=${category}&start=-1&sortby=title&order=asc`;
    const responseText: string = await this.fetchJsonText(path, localized('分类档案'));
    const payload: ArchiveSearchPayload =
      JSON.parse(responseText) as ArchiveSearchPayload;
    return ArchiveItem.listFromPayloads(payload.data);
  }

  async fetchArchivePages(archiveId: string): Promise<Array<ReaderPage>> {
    const result: ArchivePagesResult = await this.fetchArchivePagesResult(archiveId);
    return result.pages;
  }

  /**
   * Asks for an archive's page list, keeping the extraction job.
   *
   * LANraragi extracts an archive on demand: the first request for one that is
   * not ready returns an empty list plus a Minion job. Callers that want to wait
   * for it need that job id, which the plain `fetchArchivePages` drops.
   */
  async fetchArchivePagesResult(archiveId: string): Promise<ArchivePagesResult> {
    AppLog.detail('http', `GET /api/archives/${archiveId}/files`);
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse =
        await request.request(`${this.baseUrl}/api/archives/${archiveId}/files`, {
          method: http.RequestMethod.GET,
          header: this.requestHeaders('application/json'),
          expectDataType: http.HttpDataType.STRING,
          usingCache: false,
          connectTimeout: REQUEST_TIMEOUT_MS,
          readTimeout: ARCHIVE_INDEX_TIMEOUT_MS
        });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`${localized('页面列表请求返回 HTTP')} ${response.responseCode}`);
      }
      if (typeof response.result !== 'string') {
        throw new Error(localized('页面列表格式无法识别'));
      }
      const payload: ArchivePagesPayload =
        JSON.parse(response.result) as ArchivePagesPayload;
      const pages: Array<ReaderPage> = (payload.pages ?? []).map(
        (path: string, index: number) => {
          return new ReaderPage(path, index + 1);
        });
      const jobId: number = typeof payload.job === 'number' ? payload.job : 0;
      AppLog.detail('http', `pages ok: ${pages.length} pages, job=${jobId}`);
      return new ArchivePagesResult(pages, jobId);
    } catch (error) {
      AppLog.error('http', `pages failed for ${archiveId}: ${AppLog.describe(error)}`);
      if (error instanceof Error && error.message.length > 0) {
        throw error;
      }
      throw new Error(localized('获取档案页面失败'));
    } finally {
      request.destroy();
    }
  }

  async fetchArchivePage(
    page: ReaderPage,
    archiveId: string,
    onProgress?: ImageProgressCallback,
    priority: boolean = false
  ): Promise<ArrayBuffer | undefined> {
    return this.fetchImage(
      this.resolveArchivePageUrl(page.path),
      archiveId,
      page.pageNumber,
      onProgress,
      priority
    );
  }

  async updateArchiveProgress(archiveId: string, oneBasedPageNumber: number): Promise<void> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(
        `${this.baseUrl}/api/archives/${archiveId}/progress/${oneBasedPageNumber}`,
        {
          method: http.RequestMethod.PUT,
          header: this.requestHeaders(''),
          expectDataType: http.HttpDataType.STRING,
          usingCache: false,
          connectTimeout: REQUEST_TIMEOUT_MS,
          readTimeout: REQUEST_TIMEOUT_MS
        }
      );
      if (response.responseCode < 200 || response.responseCode >= 300) {
        AppLog.warn('http', `progress PUT ${archiveId}/${oneBasedPageNumber} -> HTTP ${response.responseCode}`);
        throw new Error(`${localized('阅读进度同步返回 HTTP')} ${response.responseCode}`);
      }
      AppLog.detail('http', `progress PUT ${archiveId}/${oneBasedPageNumber} ok`);
    } catch (error) {
      if (error instanceof Error && error.message.length > 0) {
        throw error;
      }
      throw new Error(localized('同步阅读进度失败'));
    } finally {
      request.destroy();
    }
  }

  async deleteArchive(archiveId: string): Promise<void> {
    if (archiveId.length === 0) {
      throw new Error(localized('缺少要删除的档案 ID'));
    }
    // Deleting from the server cannot be undone, so the attempt, the outcome and
    // the status are all recorded: a report of "it deleted the wrong thing" or
    // "it said deleted but the archive is still there" needs them.
    AppLog.warn('http', `DELETE /api/archives/${archiveId} (server-side delete requested)`);
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(
        `${this.baseUrl}/api/archives/${encodeURIComponent(archiveId)}`,
        {
          method: http.RequestMethod.DELETE,
          header: this.requestHeaders('application/json'),
          expectDataType: http.HttpDataType.STRING,
          usingCache: false,
          connectTimeout: REQUEST_TIMEOUT_MS,
          readTimeout: ARCHIVE_INDEX_TIMEOUT_MS
        }
      );
      if (response.responseCode < 200 || response.responseCode >= 300) {
        AppLog.error('http', `DELETE ${archiveId} -> HTTP ${response.responseCode}`);
        throw new Error(`${localized('删除档案返回 HTTP')} ${response.responseCode}`);
      }
      AppLog.warn('http', `DELETE ${archiveId} -> HTTP ${response.responseCode} (deleted on server)`);
    } catch (error) {
      AppLog.error('http', `DELETE ${archiveId} failed: ${AppLog.describe(error)}`);
      if (error instanceof Error && error.message.length > 0) {
        throw error;
      }
      throw new Error(localized('删除档案失败'));
    } finally {
      request.destroy();
    }
  }

  /**
   * Fetches one image.
   *
   * `priority` marks the page the user is reading: it skips the download queue
   * entirely. Everything else waits its turn, so preloading stays sequential and
   * never competes with the page on screen.
   */
  private async fetchImage(
    imageUrl: string,
    archiveId: string = '',
    pageNumber: number = 0,
    onProgress?: ImageProgressCallback,
    priority: boolean = false
  ): Promise<ArrayBuffer | undefined> {
    const ticket: number = await LanraragiApiClient.pageQueue.acquire(priority);
    try {
      return await this.requestImage(imageUrl, archiveId, pageNumber, onProgress);
    } finally {
      LanraragiApiClient.pageQueue.release(ticket, priority);
    }
  }

  private async requestImage(
    imageUrl: string,
    archiveId: string,
    pageNumber: number,
    onProgress?: ImageProgressCallback
  ): Promise<ArrayBuffer | undefined> {
    const request: http.HttpRequest = http.createHttp();
    const headers: Record<string, string> =
      this.imageHeaders(imageUrl, archiveId, pageNumber);
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      // The app keeps its own deterministic disk cache, so an independent HTTP
      // cache would only add a second, uninvalidatable copy of each page.
      usingCache: false,
      connectTimeout: REQUEST_TIMEOUT_MS,
      readTimeout: IMAGE_TIMEOUT_MS
    };
    try {
      // `dataReceiveProgress` is not delivered for this kind of response, so a
      // caller that needs progress reads the body as a stream instead. The two
      // paths are otherwise the same request.
      if (onProgress !== undefined) {
        return await this.fetchImageStream(request, imageUrl, options, onProgress);
      }
      const response: http.HttpResponse = await request.request(imageUrl, options);
      if (response.responseCode === 202) {
        AppLog.detail('http', `${imageUrl} -> HTTP 202 (not generated yet)`);
        return undefined;
      }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        AppLog.error('http', `${imageUrl} -> HTTP ${response.responseCode}`);
        throw new Error(`${localized('图片请求返回 HTTP')} ${response.responseCode}`);
      }
      if (!(response.result instanceof ArrayBuffer)) {
        AppLog.error('http', `${imageUrl} returned a non-binary body`);
        throw new Error(localized('图片数据格式无法识别'));
      }
      AppLog.detail('http', `${imageUrl} -> HTTP ${response.responseCode}, ` +
        `${response.result.byteLength} bytes`);
      return response.result;
    } catch (error) {
      // A message raised by this client is already user-facing; anything else —
      // a `BusinessError` from the network stack, or an SDK error — keeps its
      // code so the failure can be told apart from the others.
      if (error instanceof Error && error.message.length > 0) {
        throw error;
      }
      AppLog.error('http', `${imageUrl} failed: ${AppLog.describe(error)}`);
      throw new Error(this.networkErrorMessage(error, localized('图片加载失败')));
    } finally {
      // Listeners are removed before the request is destroyed; the stream path
      // registers them per call, and they would otherwise keep their callbacks
      // (and the buffers they captured) alive for the lifetime of the object.
      if (onProgress !== undefined) {
        request.off('dataReceive');
        request.off('headersReceive');
      }
      request.destroy();
    }
  }

  /**
   * Keeps the platform's error code in the message.
   *
   * A `BusinessError` from the network stack carries a code that says whether
   * the address failed to resolve, the connection was refused, or the request
   * timed out. Replacing it with a single sentence removes the only information
   * the user or a log reader could act on.
   */
  private networkErrorMessage(error: Object, fallback: string): string {
    const code: number = (error as BusinessError).code;
    if (Number.isFinite(code) && code !== 0) {
      return `${fallback} (${code})`;
    }
    if (error instanceof Error && error.message.length > 0) {
      return `${fallback} (${error.message})`;
    }
    return fallback;
  }

  /**
   * Collects an image from a streaming response.
   *
   * The chunks are concatenated once at the end rather than grown per chunk,
   * which would copy the whole image on every packet. `Content-Length` is what
   * makes a percentage possible; the received count is still reported without
   * it, so the reader can show a moving bar.
   */
  private async fetchImageStream(
    request: http.HttpRequest,
    imageUrl: string,
    options: http.HttpRequestOptions,
    onProgress: ImageProgressCallback
  ): Promise<ArrayBuffer | undefined> {
    const chunks: Array<Uint8Array> = [];
    let received: number = 0;
    let total: number = 0;
    let responseCode: number = 0;
    let tooLarge: boolean = false;
    let wrongType: string = '';
    try {
      request.on('headersReceive', (header: Object) => {
        const headers: Record<string, string> = header as Record<string, string>;
        total = this.contentLengthOf(headers);
        // A 200 is not proof of an image: a captive portal, a proxy error page
        // or an HTML login form all arrive this way, and the stream path would
        // otherwise hand their bytes to the decoder and cache them as a page.
        //
        // Only an answer the server *labels* as a document is refused. Requiring
        // `image/` instead rejects good pages: LANraragi sends pages as
        // `application/x-download`, so that check made every page unreadable.
        const contentType: string = this.headerValue(headers, 'content-type').toLowerCase();
        if (this.isDocumentContentType(contentType)) {
          wrongType = contentType;
        }
        // Recorded here because only the headers carry the declared type and
        // length. The status is appended once the request settles: at this point
        // it is still unknown, and printing it as 0 would be a lie.
        AppLog.detail('http', `${imageUrl} type="${contentType}" length=${total}`);
      });
      request.on('dataReceive', (chunk: ArrayBuffer) => {
        if (chunk.byteLength <= 0 || tooLarge || wrongType.length > 0) {
          return;
        }
        received += chunk.byteLength;
        if (received > MAX_STREAMED_IMAGE_BYTES) {
          // Stop reading rather than accumulate any further; the stream is then
          // resolved as a failure and no image is assembled.
          tooLarge = true;
          chunks.length = 0;
          request.destroy();
          return;
        }
        chunks.push(new Uint8Array(chunk.slice(0)));
        onProgress(received, total);
      });
      responseCode = await request.requestInStream(imageUrl, options);
    } catch (error) {
      // A destroy on the size limit surfaces as a generic failure, so the flag
      // is what tells the two apart.
      if (tooLarge) {
        AppLog.warn('http', `${imageUrl} exceeded ${MAX_STREAMED_IMAGE_BYTES} bytes`);
        throw new Error(localized('图片超过大小上限'));
      }
      AppLog.error('http', `${imageUrl} failed: ${AppLog.describe(error)}`);
      throw new Error(this.networkErrorMessage(error, localized('图片加载失败')));
    }
    if (tooLarge) {
      throw new Error(localized('图片超过大小上限'));
    }
    if (wrongType.length > 0) {
      AppLog.error('http', `${imageUrl} answered with "${wrongType}", not an image`);
      throw new Error(`${localized('服务器返回的是网页或接口数据，不是图片')} (${wrongType})`);
    }
    AppLog.detail('http', `${imageUrl} -> HTTP ${responseCode}, ${received} bytes`);
    if (responseCode === 202) {
      return undefined;
    }
    if (responseCode < 200 || responseCode >= 300) {
      throw new Error(`${localized('图片请求返回 HTTP')} ${responseCode}`);
    }
    if (chunks.length === 0) {
      return undefined;
    }
    const image: Uint8Array = new Uint8Array(received);
    let offset: number = 0;
    chunks.forEach((chunk: Uint8Array) => {
      image.set(chunk, offset);
      offset += chunk.byteLength;
    });
    return image.buffer as ArrayBuffer;
  }

  /** Response headers, carrying credentials only for the server itself. */
  private imageHeaders(
    imageUrl: string,
    archiveId: string,
    pageNumber: number
  ): Record<string, string> {
    // A page URL comes from the server and may be absolute, so it can point
    // somewhere other than the configured server. Credentials and archive
    // headers must not follow it off-origin: the LAN API key grants full access
    // to the server, and plain-http responses can be tampered with on the wire.
    const sameOrigin: boolean = this.isSameOrigin(imageUrl);
    const headers: Record<string, string> = this.requestHeaders('image/*', sameOrigin);
    if (sameOrigin && archiveId.length > 0) {
      headers['X-Archive-Id'] = archiveId;
      headers['X-Page-Number'] = `${pageNumber}`;
    }
    return headers;
  }

  /**
   * `Content-Length` of a response header block, or 0 when it is absent.
   *
   * Header names are case-insensitive, and the platform does not promise a
   * particular casing, so the lookup ignores it: a miss here silently removes
   * the percentage from the reader's progress bar.
   */
  private contentLengthOf(header: Record<string, string>): number {
    const raw: string = this.headerValue(header, 'content-length');
    if (raw.length === 0) {
      return 0;
    }
    const parsed: number = Number.parseInt(raw, 10);
    return Number.isNaN(parsed) || parsed <= 0 ? 0 : parsed;
  }

  /** Value of a response header, matched without regard to name casing. */
  private headerValue(headers: Record<string, string>, wanted: string): string {
    for (const name of Object.keys(headers)) {
      if (name.toLowerCase() === wanted) {
        const value: string = headers[name];
        return value === undefined ? '' : value;
      }
    }
    return '';
  }

  /**
   * True only for content types that cannot be an image.
   *
   * Anything starting with `image/` is an image by definition — including
   * `image/svg+xml`, which a suffix rule for `+xml` would wrongly reject. A
   * missing or generic type is passed through so the decoder decides, which is
   * the only way pages keep working for a server that does not label images as
   * images: LANraragi sends them as `application/x-download`.
   */
  private isDocumentContentType(contentType: string): boolean {
    if (contentType.length === 0 || contentType.startsWith('image/')) {
      return false;
    }
    if (contentType.startsWith('text/')) {
      return true;
    }
    if (contentType.startsWith('application/json')) {
      return true;
    }
    // +xml documents, but not an image type that happens to end in +xml.
    return contentType.startsWith('application/') && contentType.endsWith('+xml');
  }

  private async fetchJsonText(path: string, label: string): Promise<string> {
    AppLog.detail('http', `GET ${path} (${label})`);
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(this.baseUrl + path, {
        method: http.RequestMethod.GET,
        header: this.requestHeaders('application/json'),
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: ARCHIVE_INDEX_TIMEOUT_MS
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`${label}请求返回 HTTP ${response.responseCode}`);
      }
      if (typeof response.result !== 'string') {
        throw new Error(`${label}格式无法识别`);
      }
      AppLog.detail('http', `${label} ok: ${response.result.length} bytes`);
      return response.result;
    } catch (error) {
      AppLog.error('http', `${label} failed: ${AppLog.describe(error)}`);
      if (error instanceof Error && error.message.length > 0) {
        throw error;
      }
      throw new Error(`${label}加载失败`);
    } finally {
      request.destroy();
    }
  }

  /**
   * Turns a page path from the server into a request URL.
   *
   * A relative path is resolved against the configured server *including* its
   * base path, because LANraragi can be served under one (`LRR_BASE_URL`, a
   * reverse proxy). Resolving against the bare origin dropped that prefix, so
   * every page image 404ed while the rest of the API kept working.
   */
  private resolveArchivePageUrl(pagePath: string): string {
    if (this.isAbsoluteUrl(pagePath)) {
      // Absolute page URLs are passed through so archives stored on another host
      // keep working, but fetchImage strips credentials for these (see there).
      return pagePath;
    }
    if (pagePath.startsWith('/')) {
      // Server-absolute: it already names its own path below the origin.
      return this.serverOrigin() + pagePath;
    }
    return `${this.baseUrl}/${pagePath}`;
  }

  /** True for a URL that carries its own scheme, whatever its case. */
  private isAbsoluteUrl(value: string): boolean {
    const schemeEnd: number = value.indexOf('://');
    if (schemeEnd <= 0) {
      return false;
    }
    const scheme: string = value.substring(0, schemeEnd).toLowerCase();
    return scheme === 'http' || scheme === 'https';
  }

  private authorizationHeader(): string {
    // A LANraragi server that has no API key configured is accessed without
    // credentials, and the Base64 helper rejects a zero-length Uint8Array, so an
    // empty key must not be encoded at all.
    if (this.apiKey.length === 0) {
      return '';
    }
    const encoder: util.TextEncoder = new util.TextEncoder();
    const base64: util.Base64Helper = new util.Base64Helper();
    const encodedKey: string = base64.encodeToStringSync(encoder.encodeInto(this.apiKey));
    return `Bearer ${encodedKey}`;
  }

  /**
   * Builds request headers.
   *
   * `withAuthorization` is false for requests that leave the configured server's
   * origin, so the API key is never sent to a host the server merely named.
   */
  private requestHeaders(accept: string, withAuthorization: boolean = true): Record<string, string> {
    const headers: Record<string, string> = {};
    if (accept.length > 0) {
      headers['Accept'] = accept;
    }
    if (withAuthorization) {
      const authorization: string = this.authorizationHeader();
      if (authorization.length > 0) {
        headers['Authorization'] = authorization;
      }
    }
    return headers;
  }

  /** The scheme://host[:port] part of the configured server URL. */
  private serverOrigin(): string {
    const origin: string = this.originOf(this.baseUrl);
    return origin.length === 0 ? this.baseUrl : origin;
  }

  /**
   * True when the URL points at the configured server itself.
   *
   * Credentials are attached from this answer, so it is compared field by field
   * rather than by string prefix: host names are case-insensitive, a default
   * port may or may not be written out, and `http://host/api.example.com` must
   * not read as the same server as `http://host`.
   */
  private isSameOrigin(url: string): boolean {
    const target: string = this.originOf(url);
    return target.length > 0 && target === this.serverOrigin().toLowerCase();
  }

  /**
   * Scheme, host and port of a URL, lower-cased, or '' when there is none.
   *
   * Kept to the parts that decide an origin: any path, query or fragment is
   * dropped so a URL below the configured base path still counts as the same
   * server.
   */
  private originOf(url: string): string {
    const match: RegExpMatchArray | null =
      url.match(/^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/(\[[^\]]+\]|[^/?#]+)/);
    if (match === null) {
      return '';
    }
    return `${match[1].toLowerCase()}://${match[2].toLowerCase()}`;
  }
}
