import { common } from '@kit.AbilityKit';
import {
  ImageCacheStats,
  ImageDiskCache
} from '../../data/cache/ImageDiskCache';
import {
  LibrarySettings,
  LibrarySettingsRepository
} from '../../data/config/LibrarySettingsRepository';
import {
  ReaderSettings,
  ReaderSettingsRepository
} from '../../data/config/ReaderSettingsRepository';
import { ServerConfigRepository } from '../../data/config/ServerConfigRepository';
import { LanraragiApiClient } from '../../data/network/LanraragiApiClient';
import { ServerConfig, ServerProfile } from '../../domain/model/LanraragiModels';
import { localized } from '../../common/Localization';

interface CacheDialogResult {
  index: number;
}

class ServerProfileSelectOption {
  readonly value: string;

  constructor(value: string) {
    this.value = value;
  }
}

@Component
export struct SettingsPage {
  @Consume('pathStack') private pathStack: NavPathStack = new NavPathStack();
  onServerSaved: (config: ServerConfig) => void = (config: ServerConfig): void => {};
  onServerCleared: () => void = (): void => {};
  onLibrarySettingsSaved: (settings: LibrarySettings) => void =
    (settings: LibrarySettings): void => {};
  @State private serverUrl: string = '';
  @State private apiKey: string = '';
  @State private serverProfiles: Array<ServerProfile> = [];
  @State private selectedServerProfileIndex: number = -1;
  @State private directionIndex: number = 0;
  @State private readerModeIndex: number = 0;
  @State private doublePageOffset: number = 0;
  @State private preloadPageCount: number = 3;
  @State private interpolationIndex: number = 3;
  @State private hideCompleted: boolean = false;
  @State private gridLayout: boolean = true;
  @State private gridColumns: number = 0;
  @State private isServerBusy: boolean = false;
  @State private serverMessage: string = '';
  @State private serverMessageIsError: boolean = false;
  @State private readerMessage: string = '';
  @State private cacheSizeText: string = localized('正在统计…', 'Calculating…');
  @State private cacheFileCount: number = 0;
  @State private isCacheBusy: boolean = false;
  @State private cacheMessage: string = '';
  @State private cacheMessageIsError: boolean = false;

  aboutToAppear(): void {
    this.loadSettings();
    this.refreshCacheStats();
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 18 }) {
          this.introductionCard()
          this.serverSection()
          this.librarySection()
          this.cacheSection()
          this.readerSection()
          Text(localized('服务器配置仅保存在本机；阅读时只同步进度，不会删除服务器中的任何档案。'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .padding({ left: 4, right: 4, bottom: 24 })
        }
        .width('100%')
        .constraintSize({ maxWidth: 680 })
        .padding({ left: 16, right: 16, top: 14, bottom: 24 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
    }
    .title(localized('设置'))
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private introductionCard() {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        Image($r('app.media.icon_settings'))
          .width(25)
          .height(25)
          .renderMode(ImageRenderMode.Template)
          .fillColor(Color.White)
      }
      .width(48)
      .height(48)
      .backgroundColor($r('app.color.accent'))
      .borderRadius(15)

      Column({ space: 4 }) {
        Text(localized('应用设置'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(localized('连接配置与默认阅读体验'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1, color: $r('app.color.divider') })
    .borderRadius(18)
  }

  @Builder
  private serverSection() {
    Column({ space: 14 }) {
      this.sectionTitle(localized('服务器连接'), localized('修改后需要验证才能保存'))

      Column({ space: 8 }) {
        Text(localized('保存的服务器'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        if (this.serverProfiles.length > 0) {
          Select(this.serverProfiles.map((profile: ServerProfile) => {
            return new ServerProfileSelectOption(profile.name);
          }))
            .selected(Math.max(this.selectedServerProfileIndex, 0))
            .value(this.selectedServerProfileLabel())
            .height(46)
            .fontColor($r('app.color.text_primary'))
            .selectedOptionFontColor(Color.White)
            .selectedOptionBgColor($r('app.color.accent'))
            .optionFontColor($r('app.color.text_primary'))
            .optionBgColor($r('app.color.surface'))
            .backgroundColor($r('app.color.surface_muted'))
            .width('100%')
            .onSelect((index: number, value: string) => {
              this.selectServerProfile(index);
            })
        } else {
          Text(localized('没有保存的服务器'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
        Button(localized('新增服务器'))
          .height(40)
          .fontSize(13)
          .fontColor($r('app.color.accent'))
          .backgroundColor($r('app.color.accent_soft'))
          .width('100%')
          .onClick(() => {
            this.startNewServer();
          })
      }
      .width('100%')

      Column({ space: 7 }) {
        Text(localized('服务器地址'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        TextInput({
          placeholder: localized('例如：http://192.168.1.10:3000'),
          text: this.serverUrl
        })
          .type(InputType.Normal)
          .height(50)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius(12)
          .onChange((value: string) => {
            this.serverUrl = value;
            this.serverMessage = '';
          })
      }
      .width('100%')

      Column({ space: 7 }) {
        Text('API Key')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        TextInput({
          placeholder: localized('输入 LANraragi API Key'),
          text: this.apiKey
        })
          .type(InputType.Password)
          .showPasswordIcon(true)
          .height(50)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius(12)
          .onChange((value: string) => {
            this.apiKey = value;
            this.serverMessage = '';
          })
      }
      .width('100%')

      if (this.serverMessage.length > 0) {
        Text(this.serverMessage)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .lineHeight(19)
          .fontColor(this.serverMessageIsError ?
            $r('app.color.error') : $r('app.color.success'))
          .width('100%')
          .padding(11)
          .backgroundColor(this.serverMessageIsError ?
            $r('app.color.error_soft') : $r('app.color.success_soft'))
          .borderRadius(10)
      }

      Row({ space: 10 }) {
        Button(this.isServerBusy ? localized('正在验证…') : localized('验证并保存'))
          .height(46)
          .layoutWeight(1)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .backgroundColor($r('app.color.accent'))
          .enabled(!this.isServerBusy)
          .onClick(() => {
            this.verifyAndSaveServer();
          })

        Button(localized('清除本机配置'))
          .height(46)
          .fontSize(14)
          .fontColor($r('app.color.error'))
          .backgroundColor($r('app.color.error_soft'))
          .enabled(!this.isServerBusy)
          .onClick(() => {
            this.clearLocalServer();
          })
      }
      .width('100%')

      if (this.selectedServerProfileIndex >= 0 && this.serverProfiles.length > 0) {
        Button(localized('删除当前服务器'))
          .height(42)
          .fontSize(14)
          .fontColor($r('app.color.error'))
          .backgroundColor($r('app.color.error_soft'))
          .enabled(!this.isServerBusy)
          .width('100%')
          .onClick(() => {
            this.confirmDeleteServer();
          })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1, color: $r('app.color.divider') })
    .borderRadius(18)
  }

  @Builder
  private librarySection() {
    Column({ space: 10 }) {
      this.sectionTitle(localized('书库设置'), localized('筛选与布局会自动保存'))

      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text(localized('隐藏已读完档案'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text(localized('书库与分类中不显示进度已完成的档案'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(12)
            .lineHeight(17)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.hideCompleted })
          .selectedColor($r('app.color.accent'))
          .onChange((value: boolean) => {
            this.hideCompleted = value;
            this.saveLibrarySettings();
          })
      }
      .width('100%')
      .height(66)
      .padding({ top: 8, bottom: 8 })

      Divider().color($r('app.color.divider'))

      Column({ space: 8 }) {
        Text(localized('书库布局'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Select([
          { value: localized('列表布局') },
          { value: localized('封面网格布局') }
        ])
          .selected(this.gridLayout ? 1 : 0)
          .value(this.gridLayout ? localized('封面网格布局') : localized('列表布局'))
          .height(46)
          .fontColor($r('app.color.text_primary'))
          .selectedOptionFontColor(Color.White)
          .selectedOptionBgColor($r('app.color.accent'))
          .optionFontColor($r('app.color.text_primary'))
          .optionBgColor($r('app.color.surface'))
          .backgroundColor($r('app.color.surface_muted'))
          .width('100%')
          .onSelect((index: number, value: string) => {
          this.gridLayout = index === 1;
          this.saveLibrarySettings();
        })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })

      Column({ space: 8 }) {
        Text(localized('网格每行文档数'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(localized('自动模式会根据手机或平板的可用宽度排列文档，也可以手动指定列数'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .lineHeight(17)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        Select([
          { value: localized('自动适配') },
          { value: localized('每行 2 个', '2 per row') },
          { value: localized('每行 3 个', '3 per row') },
          { value: localized('每行 4 个', '4 per row') },
          { value: localized('每行 5 个', '5 per row') },
          { value: localized('每行 6 个', '6 per row') }
        ])
          .selected(this.gridColumnsOptionIndex())
          .value(this.gridColumnsLabel())
          .height(46)
          .fontColor($r('app.color.text_primary'))
          .selectedOptionFontColor(Color.White)
          .selectedOptionBgColor($r('app.color.accent'))
          .optionFontColor($r('app.color.text_primary'))
          .optionBgColor($r('app.color.surface'))
          .backgroundColor($r('app.color.surface_muted'))
          .width('100%')
          .onSelect((index: number, value: string) => {
            const values: Array<number> = [0, 2, 3, 4, 5, 6];
            this.gridColumns = values[index] ?? 0;
            this.saveLibrarySettings();
          })
      }
      .width('100%')
      .padding({ top: 6, bottom: 6 })

      Text(localized('书库中的排序方式与升降序也会自动记住。'))
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .padding({ top: 6 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1, color: $r('app.color.divider') })
    .borderRadius(18)
  }

  @Builder
  private readerSection() {
    Column({ space: 6 }) {
      this.sectionTitle(localized('阅读设置'), localized('更改会自动保存'))

      Column({ space: 8 }) {
        Text(localized('默认阅读模式'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Select([
          { value: localized('单页阅读') },
          { value: localized('双页阅读') },
          { value: localized('瀑布连续阅读') }
        ])
          .selected(this.readerModeIndex)
          .value(this.readerModeLabel())
          .height(46)
          .fontColor($r('app.color.text_primary'))
          .selectedOptionFontColor(Color.White)
          .selectedOptionBgColor($r('app.color.accent'))
          .optionFontColor($r('app.color.text_primary'))
          .optionBgColor($r('app.color.surface'))
          .backgroundColor($r('app.color.surface_muted'))
          .width('100%')
          .onSelect((index: number, value: string) => {
            this.readerModeIndex = index;
            this.saveReaderSettings();
          })
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })

      Divider().color($r('app.color.divider'))

      Column({ space: 8 }) {
        Text(localized('横向阅读方向'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(localized('用于单页和双页阅读；右→左时，双页中的先读页会放在右侧'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .lineHeight(17)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        Select([
          { value: localized('左→右') },
          { value: localized('右→左') }
        ])
          .selected(this.directionIndex)
          .value(this.directionLabel())
          .height(46)
          .fontColor($r('app.color.text_primary'))
          .selectedOptionFontColor(Color.White)
          .selectedOptionBgColor($r('app.color.accent'))
          .optionFontColor($r('app.color.text_primary'))
          .optionBgColor($r('app.color.surface'))
          .backgroundColor($r('app.color.surface_muted'))
          .width('100%')
          .onSelect((index: number, value: string) => {
            this.directionIndex = index;
            this.saveReaderSettings();
          })
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })

      Divider().color($r('app.color.divider'))

      Column({ space: 8 }) {
        Text(localized('双页默认配对'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(localized('也可以在双页阅读界面点击顶部的配对按钮随时切换'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .lineHeight(17)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        Select([
          { value: localized('第 1+2 页、3+4 页…', 'Pages 1+2, 3+4…') },
          { value: localized('第 1 页单独、2+3 页…', 'Page 1 alone, then 2+3…') }
        ])
          .selected(this.doublePageOffset)
          .value(this.doublePageOffsetLabel())
          .height(46)
          .fontColor($r('app.color.text_primary'))
          .selectedOptionFontColor(Color.White)
          .selectedOptionBgColor($r('app.color.accent'))
          .optionFontColor($r('app.color.text_primary'))
          .optionBgColor($r('app.color.surface'))
          .backgroundColor($r('app.color.surface_muted'))
          .width('100%')
          .onSelect((index: number, value: string) => {
            this.doublePageOffset = index === 1 ? 1 : 0;
            this.saveReaderSettings();
          })
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })

      Divider().color($r('app.color.divider'))

      Column({ space: 8 }) {
        Text(localized('预加载页数'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(localized('提前加载当前页前后的页面；数值越大翻页越顺畅，但会占用更多内存和临时缓存'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .lineHeight(17)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        Select([
          { value: localized('不预加载') },
          { value: localized('1 页', '1 page') },
          { value: localized('2 页', '2 pages') },
          { value: localized('3 页（推荐）') },
          { value: localized('5 页', '5 pages') },
          { value: localized('8 页', '8 pages') }
        ])
          .selected(this.preloadOptionIndex())
          .value(this.preloadLabel())
          .height(46)
          .fontColor($r('app.color.text_primary'))
          .selectedOptionFontColor(Color.White)
          .selectedOptionBgColor($r('app.color.accent'))
          .optionFontColor($r('app.color.text_primary'))
          .optionBgColor($r('app.color.surface'))
          .backgroundColor($r('app.color.surface_muted'))
          .width('100%')
          .onSelect((index: number, value: string) => {
            const values: Array<number> = [0, 1, 2, 3, 5, 8];
            this.preloadPageCount = values[index] ?? 3;
            this.saveReaderSettings();
          })
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })

      Divider().color($r('app.color.divider'))

      Column({ space: 8 }) {
        Text(localized('图片插值方式', 'Image interpolation'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(localized('设置阅读器缩放图片时的插值方式，解码尺寸保持固定', 'Choose how scaled reader images are interpolated. Decode dimensions remain fixed.'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .lineHeight(17)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
        Select([
          { value: localized('关闭（最近邻）', 'Off (nearest neighbor)') },
          { value: localized('低（双线性）', 'Low (bilinear)') },
          { value: localized('中（MipMap）', 'Medium (MipMap)') },
          { value: localized('高（三次插值）', 'High (cubic)') }
        ])
          .selected(this.interpolationIndex)
          .value(this.interpolationLabel())
          .height(46)
          .fontColor($r('app.color.text_primary'))
          .selectedOptionFontColor(Color.White)
          .selectedOptionBgColor($r('app.color.accent'))
          .optionFontColor($r('app.color.text_primary'))
          .optionBgColor($r('app.color.surface'))
          .backgroundColor($r('app.color.surface_muted'))
          .width('100%')
          .onSelect((index: number, value: string) => {
            this.interpolationIndex = Math.min(Math.max(index, 0), 3);
            this.saveReaderSettings();
          })
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })

      Divider().color($r('app.color.divider'))

      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text(localized('点击区域翻页'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text(localized('点击屏幕左右两侧翻页，中间显示或隐藏页码栏'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(12)
            .lineHeight(17)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: true })
          .selectedColor($r('app.color.accent'))
          .onChange((value: boolean) => {
            this.saveReaderSettings();
          })
      }
      .width('100%')
      .height(66)
      .padding({ top: 8, bottom: 8 })
      .visibility(Visibility.None)

      Divider().color($r('app.color.divider')).visibility(Visibility.None)

      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text(localized('进入时显示页码栏'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text(localized('打开档案时先显示页码与拖拽进度条'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(12)
            .lineHeight(17)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: false })
          .selectedColor($r('app.color.accent'))
          .onChange((value: boolean) => {
            this.saveReaderSettings();
          })
      }
      .width('100%')
      .height(66)
      .padding({ top: 8, bottom: 8 })
      .visibility(Visibility.None)

      if (this.readerMessage.length > 0) {
        Text(this.readerMessage)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .fontColor($r('app.color.success'))
          .width('100%')
          .padding({ top: 6 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1, color: $r('app.color.divider') })
    .borderRadius(18)
  }

  @Builder
  private cacheSection() {
    Column({ space: 14 }) {
      this.sectionTitle(localized('图片缓存'), localized('封面长期保存，阅读页退出档案后自动删除'))

      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(this.cacheSizeText)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          Text(`${this.cacheFileCount} ${localized('个图片文件', 'image files')}`)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
        .layoutWeight(1)

        Button(this.isCacheBusy ? localized('正在清理…') : localized('清空缓存'))
          .height(44)
          .fontSize(14)
          .fontColor($r('app.color.error'))
          .backgroundColor($r('app.color.error_soft'))
          .enabled(!this.isCacheBusy)
          .onClick(() => {
            this.confirmClearCache();
          })
      }
      .width('100%')

      Text(localized('阅读页只在当前阅读期间缓存；退出档案后自动释放。清理操作不会影响服务器档案、进度和连接配置。'))
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')

      if (this.cacheMessage.length > 0) {
        Text(this.cacheMessage)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .fontColor(this.cacheMessageIsError ?
            $r('app.color.error') : $r('app.color.success'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1, color: $r('app.color.divider') })
    .borderRadius(18)
  }

  @Builder
  private sectionTitle(title: string, subtitle: string) {
    Column({ space: 3 }) {
      Text(title)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(subtitle)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
    }
    .width('100%')
    .padding({ bottom: 4 })
  }

  private async loadSettings(): Promise<void> {
    try {
      this.serverProfiles = await this.serverRepository().loadProfiles();
      const active: ServerProfile | undefined = await this.serverRepository().loadActiveProfile();
      if (active !== undefined) {
        this.selectedServerProfileIndex = this.serverProfiles.findIndex(
          (profile: ServerProfile) => profile.id === active.id);
        this.serverUrl = active.serverUrl;
        this.apiKey = active.apiKey;
      } else {
        this.selectedServerProfileIndex = -1;
        this.serverUrl = '';
        this.apiKey = '';
      }
    } catch (error) {
      this.serverMessageIsError = true;
      this.serverMessage = this.describeError(error);
    }

    try {
      const settings: ReaderSettings = await this.readerRepository().load();
      this.applyReaderSettings(settings);
    } catch (error) {
      this.readerMessage = localized('读取阅读设置失败，将使用默认值');
    }

    try {
      const settings: LibrarySettings = await this.libraryRepository().load();
      this.hideCompleted = settings.hideCompleted;
      this.gridLayout = settings.gridLayout;
      this.gridColumns = settings.gridColumns;
    } catch (error) {
      // Library defaults remain available when preferences cannot be read.
    }
  }

  private selectedServerProfileLabel(): string {
    if (this.selectedServerProfileIndex >= 0 &&
      this.selectedServerProfileIndex < this.serverProfiles.length) {
      return this.serverProfiles[this.selectedServerProfileIndex].name;
    }
    return localized('新增服务器');
  }

  private selectServerProfile(index: number): void {
    if (index < 0 || index >= this.serverProfiles.length) {
      return;
    }
    const profile: ServerProfile = this.serverProfiles[index];
    this.selectedServerProfileIndex = index;
    this.serverUrl = profile.serverUrl;
    this.apiKey = profile.apiKey;
    this.serverMessageIsError = false;
    this.serverMessage = localized('已选择服务器，请点击验证并保存');
  }

  private startNewServer(): void {
    this.selectedServerProfileIndex = -1;
    this.serverUrl = '';
    this.apiKey = '';
    this.serverMessageIsError = false;
    this.serverMessage = '';
  }

  private async confirmDeleteServer(): Promise<void> {
    if (this.selectedServerProfileIndex < 0 ||
      this.selectedServerProfileIndex >= this.serverProfiles.length) {
      return;
    }
    try {
      const result: CacheDialogResult = await
        (this.getUIContext().getPromptAction().showDialog({
          title: localized('删除当前服务器'),
          message: localized('确认删除当前服务器？'),
          buttons: [
            { text: localized('取消'), color: '#5D6B7A' },
            { text: localized('删除'), color: '#C43E3E' }
          ]
        }) as Promise<CacheDialogResult>);
      if (result.index !== 1) {
        return;
      }
      const profile: ServerProfile = this.serverProfiles[this.selectedServerProfileIndex];
      this.isServerBusy = true;
      await this.serverRepository().deleteProfile(profile.id);
      this.serverProfiles = await this.serverRepository().loadProfiles();
      const active: ServerProfile | undefined = await this.serverRepository().loadActiveProfile();
      if (active === undefined) {
        this.selectedServerProfileIndex = -1;
        this.serverUrl = '';
        this.apiKey = '';
      } else {
        this.selectedServerProfileIndex = this.serverProfiles.findIndex(
          (item: ServerProfile) => item.id === active.id);
        this.serverUrl = active.serverUrl;
        this.apiKey = active.apiKey;
      }
      this.serverMessageIsError = false;
      this.serverMessage = localized('服务器配置已删除');
    } catch (error) {
      this.serverMessageIsError = true;
      this.serverMessage = this.describeError(error);
    } finally {
      this.isServerBusy = false;
    }
  }

  private refreshCacheStats(): void {
    try {
      const stats: ImageCacheStats = this.imageCache().stats();
      this.cacheSizeText = this.formatBytes(stats.bytes);
      this.cacheFileCount = stats.fileCount;
      this.cacheMessageIsError = false;
    } catch (error) {
      this.cacheSizeText = localized('统计失败');
      this.cacheFileCount = 0;
      this.cacheMessageIsError = true;
      this.cacheMessage = localized('暂时无法读取本地缓存信息');
    }
  }

  private async confirmClearCache(): Promise<void> {
    try {
      const result: CacheDialogResult = await
        (this.getUIContext().getPromptAction().showDialog({
          title: localized('清空图片缓存？'),
          message: localized('只会删除手机本地的封面和阅读页副本，下次查看时会重新从服务器加载。'),
          buttons: [
            { text: localized('取消'), color: '#5D6B7A' },
            { text: localized('清空'), color: '#C43E3E' }
          ]
        }) as Promise<CacheDialogResult>);
      if (result.index === 1) {
        this.clearImageCache();
      }
    } catch (error) {
      // Closing the dialog or a prompt failure should not affect settings.
    }
  }

  private clearImageCache(): void {
    if (this.isCacheBusy) {
      return;
    }
    this.isCacheBusy = true;
    this.cacheMessage = '';
    try {
      this.imageCache().clearAll();
      this.cacheSizeText = '0 B';
      this.cacheFileCount = 0;
      this.cacheMessageIsError = false;
      this.cacheMessage = localized('本机图片缓存已清空');
    } catch (error) {
      this.cacheMessageIsError = true;
      this.cacheMessage = localized('清空缓存失败，请稍后重试');
      this.refreshCacheStats();
    } finally {
      this.isCacheBusy = false;
    }
  }

  private formatBytes(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`;
    }
    if (bytes < 1024 * 1024 * 1024) {
      return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    }
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  }

  private async verifyAndSaveServer(): Promise<void> {
    if (this.isServerBusy) {
      return;
    }
    if (this.serverUrl.trim().length === 0) {
      this.serverMessageIsError = true;
      this.serverMessage = localized('请输入 LANraragi 服务器地址');
      return;
    }

    this.isServerBusy = true;
    this.serverMessage = '';
    try {
      const normalizedUrl: string =
        LanraragiApiClient.normalizeServerUrl(this.serverUrl);
      const config: ServerConfig = new ServerConfig(normalizedUrl, this.apiKey);
      const client: LanraragiApiClient =
        new LanraragiApiClient(config.serverUrl, config.apiKey);
      await client.fetchServerInfo();
      await this.serverRepository().save(config);
      this.serverUrl = normalizedUrl;
      this.serverMessageIsError = false;
      this.serverMessage = localized('连接验证成功，配置已安全保存');
      this.onServerSaved(config);
      this.pathStack.pop();
    } catch (error) {
      this.serverMessageIsError = true;
      this.serverMessage = this.describeError(error);
    } finally {
      this.isServerBusy = false;
    }
  }

  private async clearLocalServer(): Promise<void> {
    if (this.isServerBusy) {
      return;
    }
    this.isServerBusy = true;
    this.serverMessage = '';
    try {
      await this.serverRepository().clear();
      this.serverProfiles = [];
      this.selectedServerProfileIndex = -1;
      this.serverUrl = '';
      this.apiKey = '';
      this.serverMessageIsError = false;
      this.serverMessage = localized('本机连接配置已清除，服务器档案未作任何更改');
      this.onServerCleared();
      this.pathStack.pop();
    } catch (error) {
      this.serverMessageIsError = true;
      this.serverMessage = this.describeError(error);
    } finally {
      this.isServerBusy = false;
    }
  }

  private async saveReaderSettings(): Promise<void> {
    try {
      await this.readerRepository().save(this.currentReaderSettings());
      this.readerMessage = localized('阅读设置已保存');
    } catch (error) {
      this.readerMessage = localized('阅读设置保存失败');
    }
  }

  private async saveLibrarySettings(): Promise<void> {
    try {
      const current: LibrarySettings = await this.libraryRepository().load();
      const updated: LibrarySettings = new LibrarySettings(
        current.sortModeIndex,
        current.sortAscending,
        this.hideCompleted,
        this.gridLayout,
        this.gridColumns
      );
      await this.libraryRepository().save(updated);
      this.onLibrarySettingsSaved(updated);
    } catch (error) {
      this.readerMessage = localized('书库设置保存失败');
    }
  }

  private gridColumnsOptionIndex(): number {
    const values: Array<number> = [0, 2, 3, 4, 5, 6];
    const index: number = values.indexOf(this.gridColumns);
    return index >= 0 ? index : 0;
  }

  private gridColumnsLabel(): string {
    const labels: Array<string> = [
      localized('自动适配'),
      localized('每行 2 个', '2 per row'),
      localized('每行 3 个', '3 per row'),
      localized('每行 4 个', '4 per row'),
      localized('每行 5 个', '5 per row'),
      localized('每行 6 个', '6 per row')
    ];
    return labels[this.gridColumnsOptionIndex()];
  }

  private currentReaderSettings(): ReaderSettings {
    return new ReaderSettings(
      this.directionIndex,
      this.readerModeIndex,
      this.doublePageOffset,
      this.preloadPageCount,
      this.interpolationIndex
    );
  }

  private applyReaderSettings(settings: ReaderSettings): void {
    this.directionIndex = settings.directionIndex;
    this.readerModeIndex = settings.modeIndex;
    this.doublePageOffset = settings.doublePageOffset;
    this.preloadPageCount = settings.preloadPageCount;
    this.interpolationIndex = settings.interpolationIndex;
  }

  private preloadOptionIndex(): number {
    const values: Array<number> = [0, 1, 2, 3, 5, 8];
    const index: number = values.indexOf(this.preloadPageCount);
    return index >= 0 ? index : 3;
  }

  private preloadLabel(): string {
    const labels: Array<string> = [
      localized('不预加载'),
      localized('1 页', '1 page'),
      localized('2 页', '2 pages'),
      localized('3 页（推荐）'),
      localized('5 页', '5 pages'),
      localized('8 页', '8 pages')
    ];
    return labels[this.preloadOptionIndex()];
  }

  private interpolationLabel(): string {
    const labels: Array<string> = [
      localized('关闭（最近邻）', 'Off (nearest neighbor)'),
      localized('低（双线性）', 'Low (bilinear)'),
      localized('中（MipMap）', 'Medium (MipMap)'),
      localized('高（三次插值）', 'High (cubic)')
    ];
    return labels[Math.min(Math.max(this.interpolationIndex, 0), 3)];
  }

  private directionLabel(): string {
    if (this.directionIndex === 1) {
      return localized('右→左');
    }
    return localized('左→右');
  }

  private readerModeLabel(): string {
    const labels: Array<string> = [localized('单页阅读'), localized('双页阅读'), localized('瀑布连续阅读')];
    return labels[this.readerModeIndex] ?? labels[0];
  }

  private doublePageOffsetLabel(): string {
    return this.doublePageOffset === 1 ?
      localized('第 1 页单独、2+3 页…', 'Page 1 alone, then 2+3…') :
      localized('第 1+2 页、3+4 页…', 'Pages 1+2, 3+4…');
  }

  private serverRepository(): ServerConfigRepository {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    return new ServerConfigRepository(context);
  }

  private readerRepository(): ReaderSettingsRepository {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    return new ReaderSettingsRepository(context);
  }

  private libraryRepository(): LibrarySettingsRepository {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    return new LibrarySettingsRepository(context);
  }

  private imageCache(): ImageDiskCache {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    return new ImageDiskCache(context);
  }

  private describeError(error: Object): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return localized('操作失败，请检查网络和输入内容');
  }
}
