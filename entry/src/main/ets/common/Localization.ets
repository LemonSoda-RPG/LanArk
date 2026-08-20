import { i18n } from '@kit.LocalizationKit';

/**
 * Returns true when the system language is English.
 *
 * ArkUI resource qualifiers handle strings referenced through `$r(...)`.
 * This helper covers the legacy inline labels that are still assembled in
 * ArkTS (for example, dynamic menu labels and validation messages).
 */
export function isEnglishSystemLanguage(): boolean {
  try {
    return i18n.System.getSystemLanguage().toLowerCase().startsWith('en');
  } catch (error) {
    return false;
  }
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
  '封面长期保存，阅读页退出档案后自动删除': 'Covers are kept; reading pages are removed when you leave an archive',
  '清空缓存': 'Clear cache',
  '阅读页只在当前阅读期间缓存；退出档案后自动释放。清理操作不会影响服务器档案、进度和连接配置。':
    'Reading pages are cached only during the current session and released when you leave. Clearing the cache does not affect server archives, progress, or connection settings.',
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
  , '可离线阅读': 'available offline'
  , '在档案信息中点击下载，即可在无网络时阅读。':
    'Tap Download in archive information to read without a network connection.'
  , '暂无下载任务': 'No download tasks'
  , '开始下载后，这里会显示实时进度。': 'Active download progress will appear here.'
  , '返回已下载': 'Back to downloaded archives'
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
