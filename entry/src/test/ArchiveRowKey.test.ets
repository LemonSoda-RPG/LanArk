import { describe, expect, it } from '@ohos/hypium';
import { ArchiveIndexPayload, ArchiveItem } from '../main/ets/domain/model/LanraragiModels';
import { archiveRowKey } from '../main/ets/features/library/ArchiveRowKey';

function makeArchive(progress: number): ArchiveItem {
  const payload: ArchiveIndexPayload = {
    arcid: 'archive-1',
    extension: 'zip',
    isnew: true,
    title: 'A title',
    pagecount: 32,
    progress: progress
  };
  return new ArchiveItem(payload);
}

/**
 * `LazyForEach` keeps the component it already built while the key is unchanged,
 * so a key that ignores the position leaves the card showing the text it was
 * created with.
 */
export default function archiveRowKeyTest() {
  describe('archiveRowKey', () => {
    it('changes when the page position changes, so the row is rebuilt', 0, () => {
      const unread: string = archiveRowKey(makeArchive(0));
      const reading: string = archiveRowKey(makeArchive(5));
      expect(unread === reading).assertFalse();
    });

    it('stays the same while the position does, so nothing rebuilds for nothing', 0, () => {
      expect(archiveRowKey(makeArchive(5))).assertEqual(archiveRowKey(makeArchive(5)));
    });

    it('keeps the two lists apart with a prefix', 0, () => {
      const archive: ArchiveItem = makeArchive(5);
      expect(archiveRowKey(archive, 'grid')).assertEqual(`grid-${archiveRowKey(archive)}`);
      expect(archiveRowKey(archive, 'grid') === archiveRowKey(archive)).assertFalse();
    });
  });
}
