import { bundleManager } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { localized } from '../../common/Localization';

const REPOSITORY_URL: string = 'https://github.com/LemonSoda-RPG/LanArk';
/**
 * Release feed of the project.
 *
 * The REST endpoint (`/releases/latest`) is deliberately not used: anonymous
 * API calls share a 60-per-hour quota per public address, which is routinely
 * spent behind a carrier NAT, and the call then fails with HTTP 403. The atom
 * feed has no such quota and carries the same version, page link and notes.
 * Its one difference is that a pre-release would show up here as well.
 */
const RELEASES_FEED_URL: string = REPOSITORY_URL + '/releases.atom';
const RELEASE_PAGE_PREFIX: string = REPOSITORY_URL + '/releases/tag/';
const RELEASE_TAG_MARKER: string = '/releases/tag/';
const REQUEST_TIMEOUT_MS: number = 15_000;
const SUCCESS_STATUS: number = 200;

/** One released version, as reported by the release feed. */
export class ReleaseInfo {
  readonly version: string;
  readonly title: string;
  readonly notes: string;
  readonly pageUrl: string;

  constructor(version: string, title: string, notes: string, pageUrl: string) {
    this.version = version;
    this.title = title;
    this.notes = notes;
    this.pageUrl = pageUrl;
  }
}

/** Version of the running app, as declared in `AppScope/app.json5`. */
export function installedVersion(): string {
  try {
    const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    return info.versionName;
  } catch (error) {
    // An unreadable version only costs the comparison, not the whole page.
    return '';
  }
}

/**
 * Splits a version into numeric components.
 *
 * Tags may carry a leading `v` and a pre-release suffix (`v1.2.0-beta`); only
 * the leading numbers decide the comparison, so a suffix never reads as newer.
 */
function versionParts(version: string): Array<number> {
  const trimmed: string = version.trim().replace(/^[vV]/, '');
  const head: string = trimmed.split('-')[0];
  return head.split('.').map((part: string) => {
    const parsed: number = Number.parseInt(part, 10);
    return Number.isNaN(parsed) ? 0 : parsed;
  });
}

/** True when `candidate` is a later version than `current`. */
export function isNewerVersion(candidate: string, current: string): boolean {
  if (candidate.length === 0 || current.length === 0) {
    return false;
  }
  const left: Array<number> = versionParts(candidate);
  const right: Array<number> = versionParts(current);
  const length: number = Math.max(left.length, right.length);
  for (let index: number = 0; index < length; index += 1) {
    const a: number = index < left.length ? left[index] : 0;
    const b: number = index < right.length ? right[index] : 0;
    if (a !== b) {
      return a > b;
    }
  }
  return false;
}

/** Reads the newest published release. Throws a localized error on failure. */
export async function fetchLatestRelease(): Promise<ReleaseInfo> {
  const request: http.HttpRequest = http.createHttp();
  try {
    const response: http.HttpResponse = await request.request(RELEASES_FEED_URL, {
      method: http.RequestMethod.GET,
      header: {
        'Accept': 'application/atom+xml',
        'User-Agent': 'LanArk-HarmonyOS'
      },
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: REQUEST_TIMEOUT_MS,
      readTimeout: REQUEST_TIMEOUT_MS
    });
    if (response.responseCode !== SUCCESS_STATUS) {
      throw new Error(describeStatus(response.responseCode));
    }
    if (typeof response.result !== 'string') {
      throw new Error(localized('版本服务返回的内容无法识别'));
    }
    // The feed lists the newest release first.
    const entry: string = firstEntry(response.result);
    if (entry.length === 0) {
      // Nothing has been released yet, which is not an error.
      return new ReleaseInfo('', '', '', '');
    }
    const tag: string = extractTag(entry);
    if (tag.length === 0) {
      throw new Error(localized('版本服务返回的内容无法识别'));
    }
    return new ReleaseInfo(
      tag,
      extractElement(entry, 'title'),
      plainTextFromHtml(extractElement(entry, 'content')),
      RELEASE_PAGE_PREFIX + tag
    );
  } catch (error) {
    // Rethrown untouched so the caller still sees the original error code.
    // ArkTS only allows `throw` on an `Error`, and a rejected network call is
    // a BusinessError carrying both a code and a message.
    throw error as Error;
  } finally {
    request.destroy();
  }
}

/**
 * Turns a non-200 answer into an explanation.
 *
 * GitHub answers 403/429 when the anonymous API quota is spent; the feed has no
 * such quota, so this is mostly here for captive portals and blocked networks.
 */
function describeStatus(status: number): string {
  if (status === 403 || status === 429) {
    return localized('请求过于频繁，请稍后再试');
  }
  if (status === 404) {
    return localized('还没有发布任何版本');
  }
  return `${localized('版本服务返回错误')} (HTTP ${status})`;
}

/** Text of the first `<entry>` block, or an empty string when there is none. */
function firstEntry(feed: string): string {
  const start: number = feed.indexOf('<entry>');
  if (start < 0) {
    return '';
  }
  const end: number = feed.indexOf('</entry>', start);
  if (end < 0) {
    return '';
  }
  return feed.substring(start, end);
}

/** Tag of the entry, read from its release-page link. */
function extractTag(entry: string): string {
  let from: number = 0;
  while (from < entry.length) {
    const at: number = entry.indexOf('href="', from);
    if (at < 0) {
      return '';
    }
    const valueStart: number = at + 'href="'.length;
    const valueEnd: number = entry.indexOf('"', valueStart);
    if (valueEnd < 0) {
      return '';
    }
    const href: string = entry.substring(valueStart, valueEnd);
    const marker: number = href.indexOf(RELEASE_TAG_MARKER);
    if (marker >= 0) {
      return href.substring(marker + RELEASE_TAG_MARKER.length);
    }
    from = valueEnd + 1;
  }
  return '';
}

/** Inner text of the first `<name>` element, ignoring its attributes. */
function extractElement(entry: string, name: string): string {
  const open: string = '<' + name;
  const start: number = entry.indexOf(open);
  if (start < 0) {
    return '';
  }
  const headerEnd: number = entry.indexOf('>', start);
  if (headerEnd < 0) {
    return '';
  }
  const close: string = '</' + name + '>';
  const end: number = entry.indexOf(close, headerEnd);
  if (end < 0) {
    return '';
  }
  return entry.substring(headerEnd + 1, end);
}

function unescapeHtml(value: string): string {
  // `&amp;` is replaced last so an escaped ampersand is not decoded twice.
  return value
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');
}

/** Release notes arrive as escaped HTML; the app shows them as plain lines. */
function plainTextFromHtml(html: string): string {
  // Entities are decoded first: the feed escapes its HTML, so the tags only
  // become visible once `&lt;` turns into `<`.
  const decoded: string = unescapeHtml(html);
  const withBreaks: string = decoded
    .replace(/<\/li>/g, '\n')
    .replace(/<\/p>/g, '\n')
    .replace(/<br\s*\/?>/g, '\n')
    .replace(/<\/h[1-6]>/g, '\n');
  return withBreaks
    .replace(/<[^>]*>/g, '')
    .split('\n')
    .map((line: string) => line.trim())
    .filter((line: string) => line.length > 0)
    .join('\n');
}
