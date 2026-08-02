import { common } from '@kit.AbilityKit';
import { ServerConfigRepository } from '../../data/config/ServerConfigRepository';
import { LanraragiApiClient } from '../../data/network/LanraragiApiClient';
import {
  ArchiveIndexPayload,
  ArchiveItem,
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

interface DeleteDialogResult {
  index: number;
}

@Component
export struct ArchiveInfoPage {
  @Consume('pathStack') private pathStack: NavPathStack = new NavPathStack();
  archive: ArchiveItem = emptyArchive();
  onTagSelected: (tag: string) => void = (tag: string): void => {};
  onArchiveDeleted: (archiveId: string) => void = (archiveId: string): void => {};
  @State private isDeleting: boolean = false;
  @State private deleteError: string = '';

  build() {
    NavDestination() {
      Column({ space: 8 }) {
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
          .accessibilityText('返回阅读界面')
          .onClick(() => {
            this.pathStack.pop();
          })

          Text('档案信息')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })

        List({ space: 18 }) {
          ListItem() {
            this.archiveSummaryCard()
          }
          ListItem() {
            this.tagSection()
          }
          ListItem() {
            this.dangerSection()
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ left: 16, right: 16, bottom: 32 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private archiveSummaryCard() {
    Column({ space: 7 }) {
      Text(this.archive.title)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(`${this.archive.pageCount} 页 · ${this.archive.progressText}`)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1, color: $r('app.color.divider') })
    .borderRadius(16)
  }

  @Builder
  private tagSection() {
    Column({ space: 12 }) {
      Row() {
        Text('全部标签')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`${this.archive.tagItems().length} 项`)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')

      if (this.archive.tagItems().length === 0) {
        Text('当前档案没有标签')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .padding({ top: 10, bottom: 10 })
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.archive.tagItems(), (tag: string, index: number) => {
            Row() {
              Text(tag)
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(13)
                .lineHeight(19)
                .fontColor($r('app.color.accent_text'))
                .maxLines(3)
                .hitTestBehavior(HitTestMode.None)
            }
            .constraintSize({ maxWidth: '100%' })
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .margin({ right: 8, bottom: 8 })
            .backgroundColor($r('app.color.accent_soft'))
            .borderRadius(11)
            .accessibilityText(`搜索标签 ${tag}`)
            .onClick(() => {
              this.onTagSelected(tag);
            })
          }, (tag: string, index: number) => `archive-tag-${index}-${tag}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1, color: $r('app.color.divider') })
    .borderRadius(16)
  }

  @Builder
  private dangerSection() {
    Column({ space: 12 }) {
      Text('危险操作')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.error'))
        .width('100%')
      Text('删除会同时移除服务器中的档案文件和元数据，此操作无法撤销。')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(13)
        .lineHeight(19)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      if (this.deleteError.length > 0) {
        Text(this.deleteError)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .fontColor($r('app.color.error'))
          .width('100%')
          .padding(10)
          .backgroundColor($r('app.color.error_soft'))
          .borderRadius(10)
      }

      Button(this.isDeleting ? '正在删除…' : '删除当前档案')
        .width('100%')
        .height(48)
        .enabled(!this.isDeleting)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.error'))
        .backgroundColor($r('app.color.error_soft'))
        .onClick(() => {
          this.confirmDelete();
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .border({ width: 1, color: $r('app.color.error_soft') })
    .borderRadius(16)
  }

  private async confirmDelete(): Promise<void> {
    if (this.isDeleting || this.archive.id.length === 0) {
      return;
    }
    this.deleteError = '';
    try {
      const result: DeleteDialogResult = await
        (this.getUIContext().getPromptAction().showDialog({
        title: '确认删除当前档案？',
        message: `“${this.archive.title}”将从服务器永久删除，文件和元数据均无法恢复。`,
        buttons: [
          { text: '取消', color: '#5D6B7A' },
          { text: '删除', color: '#C43E3E' }
        ]
      }) as Promise<DeleteDialogResult>);
      if (result.index !== 1) {
        return;
      }
      await this.deleteArchive();
    } catch (error) {
      this.deleteError = this.describeError(error);
    }
  }

  private async deleteArchive(): Promise<void> {
    this.isDeleting = true;
    this.deleteError = '';
    try {
      const config: ServerConfig = await this.repository().load();
      const client: LanraragiApiClient =
        new LanraragiApiClient(config.serverUrl, config.apiKey);
      await client.deleteArchive(this.archive.id);
      this.onArchiveDeleted(this.archive.id);
    } catch (error) {
      this.deleteError = this.describeError(error);
    } finally {
      this.isDeleting = false;
    }
  }

  private repository(): ServerConfigRepository {
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    return new ServerConfigRepository(context);
  }

  private describeError(error: Object): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return '删除档案失败';
  }
}
