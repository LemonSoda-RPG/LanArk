import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import {
  ArchiveItem,
  ArchivePagesPayload,
  ArchiveSearchPayload,
  CategoryItem,
  ReaderPage,
  ServerInfo
} from '../../domain/model/LanraragiModels';
import { localized } from '../../common/Localization';

const REQUEST_TIMEOUT_MS: number = 15_000;
const ARCHIVE_INDEX_TIMEOUT_MS: number = 240_000;

export class LanraragiApiClient {
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
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(`${this.baseUrl}/api/info`, {
        method: http.RequestMethod.GET,
        header: {
          'Authorization': this.authorizationHeader(),
          'Accept': 'application/json'
        },
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
      return ServerInfo.fromJson(response.result);
    } catch (error) {
      if (error instanceof Error && error.message.length > 0) {
        throw error;
      }
      throw new Error(localized('网络请求失败，请检查服务器地址和网络状态'));
    } finally {
      request.destroy();
    }
  }

  async fetchArchiveIndex(): Promise<Array<ArchiveItem>> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(`${this.baseUrl}/api/archives`, {
        method: http.RequestMethod.GET,
        header: {
          'Authorization': this.authorizationHeader(),
          'Accept': 'application/json'
        },
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
      return ArchiveItem.listFromJson(response.result);
    } catch (error) {
      if (error instanceof Error && error.message.length > 0) {
        throw error;
      }
      throw new Error(localized('档案索引加载失败'));
    } finally {
      request.destroy();
    }
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
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse =
        await request.request(`${this.baseUrl}/api/archives/${archiveId}/files`, {
          method: http.RequestMethod.GET,
          header: {
            'Authorization': this.authorizationHeader(),
            'Accept': 'application/json'
          },
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
      return payload.pages.map((path: string, index: number) => {
        return new ReaderPage(path, index + 1);
      });
    } catch (error) {
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
    archiveId: string
  ): Promise<ArrayBuffer | undefined> {
    return this.fetchImage(
      this.resolveArchivePageUrl(page.path),
      archiveId,
      page.pageNumber
    );
  }

  async updateArchiveProgress(archiveId: string, oneBasedPageNumber: number): Promise<void> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(
        `${this.baseUrl}/api/archives/${archiveId}/progress/${oneBasedPageNumber}`,
        {
          method: http.RequestMethod.PUT,
          header: {
            'Authorization': this.authorizationHeader()
          },
          expectDataType: http.HttpDataType.STRING,
          usingCache: false,
          connectTimeout: REQUEST_TIMEOUT_MS,
          readTimeout: REQUEST_TIMEOUT_MS
        }
      );
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`${localized('阅读进度同步返回 HTTP')} ${response.responseCode}`);
      }
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
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(
        `${this.baseUrl}/api/archives/${encodeURIComponent(archiveId)}`,
        {
          method: http.RequestMethod.DELETE,
          header: {
            'Authorization': this.authorizationHeader(),
            'Accept': 'application/json'
          },
          expectDataType: http.HttpDataType.STRING,
          usingCache: false,
          connectTimeout: REQUEST_TIMEOUT_MS,
          readTimeout: ARCHIVE_INDEX_TIMEOUT_MS
        }
      );
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`${localized('删除档案返回 HTTP')} ${response.responseCode}`);
      }
    } catch (error) {
      if (error instanceof Error && error.message.length > 0) {
        throw error;
      }
      throw new Error(localized('删除档案失败'));
    } finally {
      request.destroy();
    }
  }

  private async fetchImage(
    imageUrl: string,
    archiveId: string = '',
    pageNumber: number = 0
  ): Promise<ArrayBuffer | undefined> {
    const request: http.HttpRequest = http.createHttp();
    const requestHeaders: Record<string, string> = {
      'Authorization': this.authorizationHeader(),
      'Accept': 'image/*'
    };
    if (archiveId.length > 0) {
      requestHeaders['X-Archive-Id'] = archiveId;
      requestHeaders['X-Page-Number'] = `${pageNumber}`;
    }
    try {
      const response: http.HttpResponse = await request.request(imageUrl, {
        method: http.RequestMethod.GET,
        header: requestHeaders,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: true,
        connectTimeout: REQUEST_TIMEOUT_MS,
        readTimeout: ARCHIVE_INDEX_TIMEOUT_MS
      });
      if (response.responseCode === 202) {
        return undefined;
      }
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`${localized('图片请求返回 HTTP')} ${response.responseCode}`);
      }
      if (!(response.result instanceof ArrayBuffer)) {
        throw new Error(localized('图片数据格式无法识别'));
      }
      return response.result;
    } catch (error) {
      if (error instanceof Error && error.message.length > 0) {
        throw error;
      }
      throw new Error(localized('图片加载失败'));
    } finally {
      request.destroy();
    }
  }

  private async fetchJsonText(path: string, label: string): Promise<string> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(this.baseUrl + path, {
        method: http.RequestMethod.GET,
        header: {
          'Authorization': this.authorizationHeader(),
          'Accept': 'application/json'
        },
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
      return response.result;
    } catch (error) {
      if (error instanceof Error && error.message.length > 0) {
        throw error;
      }
      throw new Error(`${label}加载失败`);
    } finally {
      request.destroy();
    }
  }

  private resolveArchivePageUrl(pagePath: string): string {
    if (pagePath.startsWith('http://') || pagePath.startsWith('https://')) {
      return pagePath;
    }
    const schemeEnd: number = this.baseUrl.indexOf('://') + 3;
    const pathStart: number = this.baseUrl.indexOf('/', schemeEnd);
    const origin: string =
      pathStart >= schemeEnd ? this.baseUrl.substring(0, pathStart) : this.baseUrl;
    if (pagePath.startsWith('/')) {
      return origin + pagePath;
    }
    return `${origin}/${pagePath}`;
  }

  private authorizationHeader(): string {
    const encoder: util.TextEncoder = new util.TextEncoder();
    const base64: util.Base64Helper = new util.Base64Helper();
    const encodedKey: string = base64.encodeToStringSync(encoder.encodeInto(this.apiKey));
    return `Bearer ${encodedKey}`;
  }
}
