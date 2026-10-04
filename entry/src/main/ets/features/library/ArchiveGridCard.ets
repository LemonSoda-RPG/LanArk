import { ArchiveItem } from '../../domain/model/LanraragiModels';
import { localized } from '../../common/Localization';
import { ArchiveCoverView } from './ArchiveCoverView';

/**
 * The "NEW" flag on a cover.
 *
 * Reads the archive through `@ObjectLink` so clearing the flag while the card is
 * on screen redraws it.
 */
@Component
export struct ArchiveNewBadge {
  @ObjectLink archive: ArchiveItem;
  marginTop: number = 0;
  marginRight: number = 0;

  build() {
    if (this.archive.displayAsNew) {
      Text('NEW')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .padding({ left: 6, right: 6, top: 3, bottom: 3 })
        .backgroundColor($r('app.color.new_badge'))
        .borderRadius(6)
        .margin({ top: this.marginTop, right: this.marginRight })
        .hitTestBehavior(HitTestMode.None)
    }
  }
}

/** Page position under a cover: unread, in progress, or finished. */
@Component
export struct ArchiveProgressText {
  @ObjectLink archive: ArchiveItem;
  fontSize: number = 11;

  build() {
    Text(`${this.archive.pageCount} ${localized('页', 'pages')} · ${this.archive.progressText}`)
      .copyOption(CopyOptions.LocalDevice)
      .fontSize(this.fontSize)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .hitTestBehavior(HitTestMode.None)
  }
}

/**
 * One archive as a cover card.
 *
 * Shared so every grid that lists archives looks the same; the library and the
 * random screen both show this, and a card written separately for each drifted
 * apart in shape, spacing and the information it showed.
 *
 * Presentation only: the tap is handled by the wrapping GridItem, so there is
 * one click target per card rather than a nested pair.
 */
@Component
export struct ArchiveGridCard {
  @ObjectLink archive: ArchiveItem;
  @Prop coverCrop: boolean = true;
  serverUrl: string = '';
  apiKey: string = '';

  build() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        ArchiveCoverView({
          archiveId: this.archive.id,
          fileExtension: this.archive.fileExtension,
          serverUrl: this.serverUrl,
          apiKey: this.apiKey,
          coverWidth: '100%',
          coverHeight: '100%',
          cropCover: this.coverCrop
        })
        ArchiveNewBadge({
          archive: this.archive,
          marginTop: 7,
          marginRight: 7
        })
      }
      .width('100%')
      // A fixed ratio keeps every card the same shape whatever the column width;
      // a fixed height would make the covers taller on a narrow screen.
      .aspectRatio(0.75)
      .margin({ bottom: 8 })

      Text(this.archive.title)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      ArchiveProgressText({ archive: this.archive, fontSize: 11 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding(10)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
    .border({ width: 1, color: $r('app.color.divider') })
  }
}
