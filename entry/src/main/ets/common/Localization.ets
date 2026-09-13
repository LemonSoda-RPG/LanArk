import { i18n } from '@kit.LocalizationKit';
import { BusinessError } from '@kit.BasicServicesKit';

let languageResolved: boolean = false;
let englishActive: boolean = false;

/**
 * Returns true when the language this app renders in is English.
 *
 * `$r(...)` resolves against the application's preferred language, which the
 * user can set independently of the system language. This helper must read the
 * same source, otherwise one screen can render in two languages at once.
 * The result is memoised because the helper is called from render paths;
 * `invalidateLanguageCache()` drops it when the configuration changes.
 */
export function isEnglishSystemLanguage(): boolean {
  if (!languageResolved) {
    languageResolved = true;
    try {
      const preferred: string = i18n.System.getAppPreferredLanguage().toLowerCase();
      englishActive = preferred.length > 0
        ? preferred.startsWith('en')
        : i18n.System.getSystemLanguage().toLowerCase().startsWith('en');
    } catch (error) {
      englishActive = false;
    }
  }
  return englishActive;
}

/** Drops the memoised language so the next lookup re-reads the configuration. */
export function invalidateLanguageCache(): void {
  languageResolved = false;
}

const TRANSLATIONS: Record<string, string> = {
  '全部': 'All',
  '页': 'pages',
  '当前为': 'Current',
  '请先在设置中配置服务器，然后点击刷新获取档案索引': 'Configure a server in Settings, then tap Refresh to load the library index.',
  '请输入 LANraragi 服务器地址': 'Enter a LANraragi server URL',
  '请先在设置中配置服务器': 'Configure a server in Settings first.',
  '暂无本地档案索引，请点击右上角刷新': 'No local library index. Tap Refresh in the top-right corner.',
  '本地分类信息不存在，请手动刷新书库': 'Local category data is missing. Refresh the library manually.',
  '连接失败，请检查服务器地址、API Key 和网络状态': 'Connection failed. Check the server URL, API key, and network status.',
  '分类': 'Categories',
  '排序方式': 'Sort by',
  '升序': 'Ascending',
  '降序': 'Descending',
  '添加时间': 'Date added',
  '标题': 'Title',
  '页数': 'Pages',
  '阅读进度': 'Reading progress',
  '阅读状态': 'Reading status',
  'NEW 状态': 'NEW status',
  '艺术家': 'Artist',
  '团体': 'Group',
  '活动': 'Event',
  '系列': 'Series',
  '角色': 'Character',
  '原作': 'Parody',
  '随机': 'Random',
  '退出搜索': 'Exit search',
  '搜索档案': 'Search archives',
  '刷新档案库': 'Refresh library',
  '应用设置': 'App settings',
  '选择分类': 'Choose category',
  '排序': 'Sort',
  '清除保存的服务器配置': 'Clear saved server configuration',
  '设置': 'Settings',
  '连接配置与默认阅读体验': 'Connection and default reading experience',
  '服务器连接': 'Server connection',
  '修改后需要验证才能保存': 'Verify changes before saving',
  '保存的服务器': 'Saved servers',
  '新增服务器': 'Add server',
  '没有保存的服务器': 'No saved servers',
  '已选择服务器，请点击验证并保存': 'Server selected. Tap Verify and save to connect.',
  '删除当前服务器': 'Delete current server',
  '确认删除当前服务器？': 'Delete the current server?',
  '服务器配置已删除': 'Server profile deleted',
  '服务器配置已保存': 'Server profile saved',
  '找不到服务器配置': 'The server profile was not found',
  '切换服务器失败：': 'Failed to switch server: ',
  '删除服务器失败：': 'Failed to delete server: ',
  '服务器地址': 'Server URL',
  '服务器配置仅保存在本机；阅读时只同步进度，不会删除服务器中的任何档案。':
    'Server settings stay on this device. Reading progress is synchronized, and no server archives are deleted.',
  '例如：http://192.168.1.10:3000': 'Example: http://192.168.1.10:3000',
  '输入 LANraragi API Key': 'Enter your LANraragi API key',
  '正在验证…': 'Verifying…',
  '验证并保存': 'Verify and save',
  '清除本机配置': 'Clear local settings',
  '书库设置': 'Library settings',
  '筛选与布局会自动保存': 'Filters and layout are saved automatically',
  '隐藏已读完档案': 'Hide completed archives',
  '书库与分类中不显示进度已完成的档案': 'Hide completed archives from the library and categories',
  '书库布局': 'Library layout',
  '列表布局': 'List layout',
  '封面网格布局': 'Cover grid layout',
  '网格每行文档数': 'Grid columns',
  '自动模式会根据手机或平板的可用宽度排列文档，也可以手动指定列数':
    'Automatic mode uses the available phone or tablet width. You can also choose a fixed column count.',
  '自动适配': 'Auto fit',
  '书库中的排序方式与升降序也会自动记住。': 'The library sort field and direction are saved automatically.',
  '阅读设置': 'Reading settings',
  '更改会自动保存': 'Changes are saved automatically',
  '默认阅读模式': 'Default reading mode',
  '单页阅读': 'Single-page reading',
  '双页阅读': 'Two-page reading',
  '瀑布连续阅读': 'Continuous reading',
  '横向阅读方向': 'Reading direction',
  '用于单页和双页阅读；右→左时，双页中的先读页会放在右侧':
    'Used for single- and two-page reading. In right-to-left mode, the first page is placed on the right.',
  '左→右': 'Left to right',
  '右→左': 'Right to left',
  '双页默认配对': 'Two-page pairing',
  '也可以在双页阅读界面点击顶部的配对按钮随时切换': 'You can change this anytime with the pairing button in two-page mode.',
  '预加载页数': 'Preload pages',
  '提前加载当前页前后的页面；数值越大翻页越顺畅，但会占用更多内存和临时缓存':
    'Preload pages around the current page. Larger values make paging smoother but use more memory and temporary cache.',
  '不预加载': 'Do not preload',
  '3 页（推荐）': '3 pages (recommended)',
  '点击区域翻页': 'Tap zones for paging',
  '点击屏幕左右两侧翻页，中间显示或隐藏页码栏': 'Tap the left or right side to turn pages; tap the center to show or hide the page bar.',
  '进入时显示页码栏': 'Show page bar on entry',
  '打开档案时先显示页码与拖拽进度条': 'Show the page number and progress slider when opening an archive',
  '图片缓存': 'Image cache',
  '封面与阅读页都会保留在本机，系统空间紧张时可能自动回收':
    'Covers and reading pages are kept on this device; the system may reclaim them under storage pressure',
  '清空缓存': 'Clear cache',
  '封面和阅读页都会保留在本机，重开同一档案时无需重新下载。清理操作不会影响服务器档案、进度和连接配置。':
    'Covers and reading pages are kept on this device, so reopening an archive does not download it again. Clearing the cache does not affect server archives, progress, or connection settings.',
  '清空图片缓存？': 'Clear image cache?',
  '只会删除手机本地的封面和阅读页副本，下次查看时会重新从服务器加载。':
    'Only local cover and reading-page copies will be deleted. They will be downloaded again when needed.',
  '取消': 'Cancel',
  '清空': 'Clear',
  '正在清理…': 'Clearing…',
  '本机图片缓存已清空': 'Local image cache cleared',
  '清空缓存失败，请稍后重试': 'Could not clear the cache. Try again later.',
  '读取阅读设置失败，将使用默认值': 'Could not read reading settings. Defaults will be used.',
  '统计失败': 'Unable to calculate cache size',
  '暂时无法读取本地缓存信息': 'Local cache information is temporarily unavailable',
  '连接验证成功，配置已安全保存': 'Connection verified. Settings saved securely.',
  '本机连接配置已清除，服务器档案未作任何更改': 'Local connection settings cleared. Server archives were not changed.',
  '阅读设置已保存': 'Reading settings saved',
  '阅读设置保存失败': 'Could not save reading settings',
  '书库设置保存失败': 'Could not save library settings',
  '操作失败，请检查网络和输入内容': 'Operation failed. Check the network and your input.',
  '档案信息': 'Archive information',
  '全部标签': 'All tags',
  '当前档案没有标签': 'This archive has no tags',
  '危险操作': 'Danger zone',
  '删除当前档案': 'Delete archive',
  '确认删除当前档案？': 'Delete this archive?',
  '档案已删除': 'Archive deleted',
  '返回阅读界面': 'Back to reader',
  '档案详情': 'Archive details',
  '标签': 'Tags',
  '删除会同时移除服务器中的档案文件和元数据，此操作无法撤销。':
    'This removes the archive files and metadata from the server. This action cannot be undone.',
  '正在删除…': 'Deleting…',
  '删除': 'Delete',
  '继续阅读': 'Continue reading',
  '开始阅读': 'Start reading',
  '从第一页开始': 'Start from page 1',
  '缩略图正在生成': 'Generating thumbnail',
  '缩略图加载失败': 'Thumbnail failed to load',
  '返回档案库': 'Back to library',
  '重置瀑布页面宽度': 'Reset continuous reading width',
  '查看档案标签和操作': 'View archive tags and actions',
  '仅对当前文档生效，不会修改设置页中的全局默认值': 'Applies only to this document and does not change global defaults.',
  '从左向右': 'Left to right',
  '从右向左': 'Right to left',
  '服务器暂未生成该页面': 'The server has not generated this page yet',
  '正在加载第': 'Loading page',
  '服务器地址必须以 http:// 或 https:// 开头': 'The server URL must start with http:// or https://',
  '请输入完整的服务器地址': 'Enter a complete server URL',
  '服务器返回了无法识别的数据': 'The server returned unrecognized data',
  '网络请求失败，请检查服务器地址和网络状态': 'Network request failed. Check the server URL and network status.',
  '档案索引格式无法识别': 'The archive index format is not recognized',
  '档案索引加载失败': 'Could not load the archive index',
  '分类列表': 'Category list',
  '分类档案': 'Category archives',
  '页面列表格式无法识别': 'The page list format is not recognized',
  '获取档案页面失败': 'Could not load archive pages',
  '同步阅读进度失败': 'Could not synchronize reading progress',
  '缺少要删除的档案 ID': 'The archive ID to delete is missing',
  '删除档案返回 HTTP': 'Archive deletion returned HTTP',
  '删除档案失败': 'Could not delete archive',
  '图片数据格式无法识别': 'The image data format is not recognized',
  '图片加载失败': 'Could not load the image',
  '服务器返回 HTTP': 'Server returned HTTP',
  '档案索引请求返回 HTTP': 'Archive index request returned HTTP',
  '页面列表请求返回 HTTP': 'Page list request returned HTTP',
  '阅读进度同步返回 HTTP': 'Reading progress sync returned HTTP',
  '图片请求返回 HTTP': 'Image request returned HTTP',
  '当前文档阅读设置': 'Current document settings',
  '阅读方式': 'Reading mode',
  '阅读方向': 'Reading direction',
  '重试': 'Retry',
  '页面加载失败': 'Page failed to load',
  '正在准备档案…': 'Preparing archive…',
  '档案加载失败': 'Archive failed to load',
  '服务器返回的页面列表为空': 'The server returned an empty page list',
  '未读': 'Unread',
  '已读完': 'Completed'
  , '已下载': 'Downloaded'
  , '下载管理': 'Download manager'
  , '离线阅读': 'Offline reading'
  , '下载到应用内后可在无网络时阅读，下载内容不会修改服务器中的原始档案。':
    'Downloaded pages stay inside the app for offline reading and do not modify the original server archive.'
  , '下载当前档案': 'Download this archive'
  , '已下载，可离线阅读': 'Downloaded · available offline'
  , '下载管理中': 'Download is managed in the download manager'
  , '下载中': 'Downloading'
  , '排队中': 'Queued'
  , '已完成': 'Completed'
  , '下载失败': 'Download failed'
  , '下载完成': 'Download complete'
  , '下载档案失败': 'Could not download the archive'
  , '下载页面失败': 'Could not download page'
  , '离线档案页面列表为空': 'The offline archive returned no pages'
  , '离线页面不存在，请重新下载档案': 'This offline page is missing. Download the archive again.'
  , '没有已下载档案': 'No downloaded archives'
  , '删除本地下载': 'Delete local download'
  , '确认删除本地下载？': 'Delete this local download?'
  , '只会删除手机上的离线副本，不会删除服务器档案。':
    'Only the offline copy on this device will be deleted. The server archive will not be touched.'
  , '本地下载已删除': 'Local download deleted'
  , '本地下载管理': 'Local download management'
  , '这里只删除本地离线副本，不会删除服务器档案。':
    'Only the local offline copy is managed here. The server archive will not be touched.'
  , '可离线阅读': 'available offline'
  , '在档案信息中点击下载，即可在无网络时阅读。':
    'Tap Download in archive information to read without a network connection.'
  , '暂无下载任务': 'No download tasks'
  , '开始下载后，这里会显示实时进度。': 'Active download progress will appear here.'
  , '返回已下载': 'Back to downloaded archives'
  , '项': 'items'
  , '该档案正在下载，请先在下载管理中清除任务':
    'This archive is downloading. Clear the task in Download manager first.'
  , '无法确认本地下载状态，请稍后重试':
    'Could not confirm the local download state. Try again in a moment.'
  , '清除本机配置？': 'Clear local configuration?'
  , '将删除本机保存的所有服务器地址和 API Key，服务器上的档案不会受影响。':
    'Every saved server address and API key on this device will be deleted. Archives on the server are not affected.'
  , '书库设置已保存': 'Library settings saved'
  , '无法打开该页面': 'This page could not be opened'
  , '观看历史': 'History'
  , '全部历史': 'All history'
  , '仅看在读': 'In progress'
  , '显示全部历史': 'Show all history'
  , '只显示正在阅读的档案': 'Show only archives in progress'
  , '还没有阅读记录': 'No reading history yet'
  , '没有正在阅读的档案': 'No archive is in progress'
  , '打开档案开始阅读后，这里会按最近阅读时间排序。':
    'Archives you open appear here, most recently read first.'
  , '刚刚': 'just now'
  , '分钟前': 'min ago'
  , '今天': 'Today'
  , '昨天': 'Yesterday'
  , '月': '/'
  , '日': ''
  , '正在刷新档案库': 'Refreshing the library'
  , '无法刷新档案库，正在显示本地缓存':
    'Could not refresh the library. Showing the local copy.'
  , '版本更新': 'App update'
  , '从 GitHub 获取最新发布': 'Reads the newest release from GitHub'
  , '当前版本': 'Current version'
  , '最新版本': 'Latest version'
  , '检查更新': 'Check for updates'
  , '检查中…': 'Checking…'
  , '发现新版本': 'New version available:'
  , '已是最新版本': 'You are on the latest version'
  , '前往下载': 'Open the download page'
  , '未知': 'unknown'
  , '版本服务返回的内容无法识别': 'The release service response could not be read'
  , '版本服务返回错误': 'The release service returned an error'
  , '请求过于频繁，请稍后再试': 'Too many requests. Try again later.'
  , '还没有发布任何版本': 'No release has been published yet'
  , '检查更新失败': 'Could not check for updates'
  , '无法连接版本服务，请检查网络': 'Could not reach the release service. Check your network.'
  , '无法打开浏览器，请手动访问': 'Could not open a browser. Visit this address manually:'
};

export function localized(chinese: string, english?: string): string {
  if (!isEnglishSystemLanguage()) {
    return chinese;
  }
  if (english !== undefined) {
    return english;
  }
  return TRANSLATIONS[chinese] ?? chinese;
}

/**
 * Maps a HarmonyOS network-stack error code to an actionable message.
 *
 * `http.request` reports its failures as `BusinessError`s whose `message` is
 * English SDK text (for example "Failed to resolve the host name."). The code,
 * not the message, decides what the user reads.
 */
export function describeNetworkErrorCode(code: number): string {
  switch (code) {
    case 2300001:
      return localized('不支持的协议，请使用 http:// 或 https://');
    case 2300006:
      return localized('无法解析服务器地址，请检查地址是否正确');
    case 2300007:
      return localized('无法连接服务器，请检查地址、端口和网络');
    case 2300028:
      return localized('请求超时，请检查网络和服务器状态');
    case 2300056:
      return localized('连接已被远端关闭，请重试');
    case 2300060:
      return localized('服务器证书校验失败');
    case 2300997:
      return localized('系统禁止明文 HTTP 访问，请改用 HTTPS 或更换网络');
    default:
      return `${localized('网络请求失败')} (${code})`;
  }
}

/**
 * Returns a message that is safe to show the user.
 *
 * Errors raised by this app already carry localized text, so their message is
 * reused. An error from a system stack carries English SDK text and is mapped
 * through its code instead. `fallback` is used when there is nothing to report.
 */
export function describeUserFacingError(error: Object, fallback: string = ''): string {
  // `Number.isFinite` rather than comparing with undefined: the field is typed
  // `number`, and a plain Error simply has no code at runtime.
  const code: number = (error as BusinessError).code;
  if (Number.isFinite(code) && code !== 0) {
    return describeNetworkErrorCode(code);
  }
  if (error instanceof Error && error.message.length > 0) {
    return error.message;
  }
  return fallback.length > 0 ? fallback : localized('操作失败，请重试');
}
