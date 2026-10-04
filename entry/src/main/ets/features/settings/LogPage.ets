import { pasteboard } from '@kit.BasicServicesKit';
import { AppLog, LogLevel } from '../../data/log/AppLog';
import { installedVersion } from '../../data/update/UpdateChecker';
import { ServerConfigRepository } from '../../data/config/ServerConfigRepository';
import { ServerConfig } from '../../domain/model/LanraragiModels';
import { localized } from '../../common/Localization';
import { common } from '@kit.AbilityKit';

/**
 * The collected diagnostic log, ready to be copied out.
 *
 * A problem reported without a log can only be guessed at, and the system log
 * needs a development cable. This screen is the way out: copy everything here
 * and it can be pasted into a bug report instead of described.
 */
@Component
export struct LogPage {
  @Consume('pathStack') private pathStack: NavPathStack = new NavPathStack();
  @State private lines: Array<string> = [];
  @State private serverUrl: string = '';
  @State private statusText: string = '';

  aboutToAppear(): void {
    this.load();
  }

  private load(): void {
    this.lines = AppLog.snapshot();
    this.resolveServerUrl();
    this.statusText = '';
  }

  private async resolveServerUrl(): Promise<void> {
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const config: ServerConfig = await new ServerConfigRepository(context).load();
      this.serverUrl = config.serverUrl;
    } catch (error) {
      // The log is still worth copying without knowing the address.
    }
  }

  /** Header plus entries: what a reader of the log needs to place it in time. */
  private fullText(): string {
    return `${AppLog.header(this.serverUrl, installedVersion())}\n` +
      `${AppLog.exportText()}\n===== end =====`;
  }

  private async copyAll(): Promise<void> {
    try {
      const data: pasteboard.PasteData =
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.fullText());
      await pasteboard.getSystemPasteboard().setData(data);
      this.statusText = localized('日志已复制到剪贴板，可直接粘贴发送',
        'Log copied to the clipboard — paste it into your report');
    } catch (error) {
      AppLog.error('log', `copy failed: ${AppLog.describe(error)}`);
      this.statusText = localized('复制失败，请稍后重试', 'Could not copy. Try again.');
    }
  }

  private confirmClear(): void {
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: localized('清空日志？'),
        message: localized('只会删除本机收集的诊断日志，不影响任何其他数据。',
          'Only the local diagnostic log is deleted; nothing else is touched.'),
        buttons: [
          { text: localized('取消'), color: $r('app.color.text_secondary') },
          { text: localized('清空'), color: $r('app.color.error') }
        ]
      }).then((result: Object) => {
        const index: number = (result as Record<string, number>).index;
        if (index === 1) {
          AppLog.clear();
          this.load();
        }
      }).catch(() => {
        // A dismissed dialog leaves the log as it was.
      });
    } catch (error) {
      AppLog.warn('log', `clear dialog failed: ${AppLog.describe(error)}`);
    }
  }

  private levelColor(level: LogLevel): ResourceColor {
    if (level === 'E') {
      return $r('app.color.error');
    }
    if (level === 'W') {
      return $r('app.color.new_badge');
    }
    return $r('app.color.text_secondary');
  }

  build() {
    NavDestination() {
      Column({ space: 10 }) {
        Row({ space: 10 }) {
          Button() {
            Image($r('app.media.icon_chevron_left'))
              .width(21)
              .height(21)
              .renderMode(ImageRenderMode.Template)
              .fillColor($r('app.color.text_primary'))
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor($r('app.color.surface'))
          .border({ width: 1, color: $r('app.color.divider') })
          .accessibilityText(localized('返回设置'))
          .onClick(() => {
            this.pathStack.pop();
          })

          Text(localized('诊断日志'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })

        Text(localized('遇到问题时，把这里的内容复制发送，就可以定位问题。日志不包含 API Key。',
          'When something goes wrong, copy this and send it along. The log never contains the API key.'))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .lineHeight(18)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ left: 16, right: 16 })

        Row({ space: 10 }) {
          Button(localized('复制全部'))
            .height(44)
            .layoutWeight(1)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.accent'))
            .onClick(() => {
              this.copyAll();
            })

          Button(localized('清空'))
            .height(44)
            .fontSize(14)
            .fontColor($r('app.color.error'))
            .backgroundColor($r('app.color.error_soft'))
            .onClick(() => {
              this.confirmClear();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        if (this.statusText.length > 0) {
          Text(this.statusText)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(13)
            .fontColor($r('app.color.success'))
            .width('100%')
            .padding(10)
            .backgroundColor($r('app.color.success_soft'))
            .borderRadius(10)
            .margin({ left: 16, right: 16 })
        }

        Text(`${this.lines.length} ${localized('条记录', 'entries')}`)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ left: 16, right: 16 })

        List({ space: 2 }) {
          ForEach(this.lines, (line: string) => {
            ListItem() {
              Text(line)
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(11)
                .fontFamily('monospace')
                .fontColor(this.levelColor(AppLog.levelOf(line)))
                .width('100%')
            }
          }, (line: string, index: number) => `log-${index}-${line.length}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .padding({ left: 16, right: 16, bottom: 24 })
        .backgroundColor($r('app.color.surface'))
        .borderRadius(14)
        .margin({ left: 16, right: 16 })
      }
      .width('100%')
      .height('100%')
      .padding({ top: 6 })
      .backgroundColor($r('app.color.page_background'))
    }
    .title(localized('诊断日志'))
    .backgroundColor($r('app.color.page_background'))
  }
}
