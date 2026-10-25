import { describe, expect, it } from '@ohos/hypium';
import {
  ArchiveIndexPayload,
  ArchiveItem,
  ServerProfile
} from '../main/ets/domain/model/LanraragiModels';
import { localized } from '../main/ets/common/Localization';

function makeArchive(progress: number, pageCount: number, isNew: boolean): ArchiveItem {
  const payload: ArchiveIndexPayload = {
    arcid: 'archive-1',
    extension: 'zip',
    isnew: isNew,
    title: 'A title',
    pagecount: pageCount,
    progress: progress
  };
  return new ArchiveItem(payload);
}

/**
 * The card line, the NEW badge and the reader's start page are all derived from
 * these few values, so they are pinned here.
 */
export default function archiveModelTest() {
  describe('archiveModel', () => {
    it('reads an unread archive as unread', 0, () => {
      expect(makeArchive(0, 32, false).progressText).assertEqual(localized('未读'));
    });

    it('shows the position while a document is being read', 0, () => {
      expect(makeArchive(3, 32, false).progressText).assertEqual('3/32');
    });

    it('reads a finished archive as finished', 0, () => {
      expect(makeArchive(32, 32, false).progressText).assertEqual(localized('已读完'));
    });

    it('treats an archive with no pages as unread', 0, () => {
      expect(makeArchive(0, 0, false).progressText).assertEqual(localized('未读'));
    });

    it('marks a new archive as new until it is read', 0, () => {
      expect(makeArchive(0, 32, true).displayAsNew).assertTrue();
      expect(makeArchive(3, 32, true).displayAsNew).assertFalse();
      expect(makeArchive(0, 32, false).displayAsNew).assertFalse();
    });

    it('reports the reading state used by the completed filter', 0, () => {
      expect(makeArchive(0, 32, false).readingState).assertEqual(0);
      expect(makeArchive(3, 32, false).readingState).assertEqual(1);
      expect(makeArchive(32, 32, false).readingState).assertEqual(2);
    });

    // The library replaces the row instance instead of writing into it, which is
    // what makes a row rebuild. That only works if the copy carries everything.
    it('copies an archive with a new position, leaving the original alone', 0, () => {
      const original: ArchiveItem = makeArchive(0, 32, true);
      const moved: ArchiveItem = original.withProgress(20);
      expect(moved === original).assertFalse();
      expect(moved.progress).assertEqual(20);
      expect(original.progress).assertEqual(0);
      expect(moved.id).assertEqual(original.id);
      expect(moved.title).assertEqual(original.title);
      expect(moved.pageCount).assertEqual(32);
      // Reading clears the NEW badge: it only shows while the position is zero.
      expect(moved.displayAsNew).assertFalse();
      expect(original.displayAsNew).assertTrue();
    });

    it('moves the read time forward only', 0, () => {
      const archive: ArchiveItem = makeArchive(4, 32, false);
      archive.markReadAt(200);
      expect(archive.lastReadTime).assertEqual(200);
      archive.markReadAt(100);
      expect(archive.lastReadTime).assertEqual(200);
    });

    // A profile saved without a name falls back to its address, which is what a
    // server saved before names existed shows in the list.
    it('falls back to the address when a server has no name', 0, () => {
      const unnamed: ServerProfile = new ServerProfile('p1', 'http://nas:3000', 'key', '');
      expect(unnamed.name).assertEqual('http://nas:3000');
      const named: ServerProfile = new ServerProfile('p2', 'http://nas:3000', 'key', 'NAS');
      expect(named.name).assertEqual('NAS');
      expect(named.toConfig().serverUrl).assertEqual('http://nas:3000');
      expect(named.toConfig().apiKey).assertEqual('key');
    });
  });
}
