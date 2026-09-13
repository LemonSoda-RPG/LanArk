import { common } from '@kit.AbilityKit';
import { OfflineArchiveCache, OfflineArchiveRecord } from '../../data/cache/OfflineArchiveCache';
import { ServerConfigRepository } from '../../data/config/ServerConfigRepository';
import { DownloadManager, DownloadTask } from '../../data/download/DownloadManager';
import { localized } from '../../common/Localization';

@Component
export struct DownloadManagerPage {
  @Consume('pathStack') private pathStack: NavPathStack = new NavPathStack();
  @State private tasks: Array<DownloadTask> = [];
  @State private completedCount: number = 0;
  private lastActiveCount: number = 0;
  private isCountBusy: boolean = false;
  // Bound once so the same reference can be unregistered.
  private readonly downloadListener: () => void = (): void => {
    this.onDownloadsChanged();
  };

  aboutToAppear(): void {
    this.refresh();
    DownloadManager.addChangeListener(this.downloadListener);
  }

  aboutToDisappear(): void {
    DownloadManager.removeChangeListener(this.downloadListener);
  }

  /**
   * Re-reads the task list on change instead of every 500 ms.
   *
   * `snapshot()` builds fresh objects on every call, so the assignment is
   * guarded by a value comparison; without it the whole list re-rendered twice
   * per second even when nothing had changed.
   */
  private onDownloadsChanged(): void {
    this.applySnapshot();
    const active: number = this.activeTaskCount(this.tasks);
    if (this.lastActiveCount > 0 && active === 0) {
      // A download just stopped, so the offline archive set may have changed.
      this.refreshCompletedCount();
    }
    this.lastActiveCount = active;
  }

  private applySnapshot(): void {
    const next: Array<DownloadTask> = DownloadManager.snapshot();
    if (!DownloadManager.sameTasks(next, this.tasks)) {
      this.tasks = next;
    }
  }

  private activeTaskCount(tasks: Array<DownloadTask>): number {
    let count: number = 0;
    for (let index: number = 0; index < tasks.length; index += 1) {
      if (tasks[index].status === 'queued' || tasks[index].status === 'downloading') {
        count += 1;
      }
    }
    return count;
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
          .accessibilityText(localized('返回已下载'))
          .onClick(() => this.pathStack.pop())

          Text(localized('下载管理'))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Text(`${this.completedCount} ${localized('项')}`)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })

        if (this.tasks.length === 0) {
          Column({ space: 10 }) {
            Text(localized('暂无下载任务'))
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(16)
              .fontColor($r('app.color.text_secondary'))
            Text(localized('开始下载后，这里会显示实时进度。'))
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 10 }) {
            ForEach(this.tasks, (task: DownloadTask) => {
              ListItem() {
                this.taskRow(task)
              }
            }, (task: DownloadTask) => `download-task-${task.archiveId}`)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .padding({ left: 16, right: 16, bottom: 20 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private taskRow(task: DownloadTask) {
    Column({ space: 9 }) {
      Row() {
        Text(task.title)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.statusText(task))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .fontColor(task.status === 'failed' ?
            $r('app.color.error') : $r('app.color.text_secondary'))
      }
      .width('100%')

      if (task.status === 'downloading' || task.status === 'queued') {
        Progress({ value: task.completedPages, total: Math.max(task.totalPages, 1), type: ProgressType.Linear })
          .width('100%')
          .height(6)
          .color($r('app.color.accent'))
          .backgroundColor($r('app.color.surface_muted'))
        Text(`${task.completedPages}/${task.totalPages} ${localized('页', 'pages')}`)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      } else if (task.status === 'failed') {
        Text(task.errorMessage)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .fontColor($r('app.color.error'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      } else {
        Text(`${task.totalPages} ${localized('页', 'pages')} · ${localized('下载完成')}`)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  private statusText(task: DownloadTask): string {
    if (task.status === 'queued') {
      return localized('排队中');
    }
    if (task.status === 'downloading') {
      return localized('下载中');
    }
    if (task.status === 'completed') {
      return localized('已完成');
    }
    return localized('下载失败');
  }

  private async refresh(): Promise<void> {
    this.applySnapshot();
    this.lastActiveCount = this.activeTaskCount(this.tasks);
    await this.refreshCompletedCount();
  }

  /** Walks every offline manifest, so it only runs on appear and on completion. */
  private async refreshCompletedCount(): Promise<void> {
    if (this.isCountBusy) {
      return;
    }
    this.isCountBusy = true;
    try {
      const context: common.UIAbilityContext =
        this.getUIContext().getHostContext() as common.UIAbilityContext;
      const config = await new ServerConfigRepository(context).load();
      const records: Array<OfflineArchiveRecord> =
        new OfflineArchiveCache(context, config.serverUrl).listRecords();
      this.completedCount = records.length;
    } catch (error) {
      this.completedCount = 0;
    } finally {
      this.isCountBusy = false;
    }
  }
}
