import { describe, expect, it } from '@ohos/hypium';
import { ServerProfile } from '../main/ets/domain/model/LanraragiModels';
import { isNameOnlyEdit } from '../main/ets/data/config/ServerProfileEdit';

function profile(): ServerProfile {
  return new ServerProfile('p1', 'http://nas:3000', 'key-1', 'NAS');
}

/**
 * Saving a renamed server used to run the connection test first, so a server
 * whose key no longer matched could not be renamed at all. Recognising a
 * name-only change is what keeps renaming off the network.
 */
export default function serverProfileEditTest() {
  describe('serverProfileEdit', () => {
    it('recognises a rename as a local change', 0, () => {
      expect(isNameOnlyEdit(profile(), 'http://nas:3000', 'key-1')).assertTrue();
    });

    it('treats a changed address as needing a test', 0, () => {
      expect(isNameOnlyEdit(profile(), 'http://nas:3001', 'key-1')).assertFalse();
      expect(isNameOnlyEdit(profile(), 'http://other:3000', 'key-1')).assertFalse();
    });

    it('treats a changed key as needing a test', 0, () => {
      expect(isNameOnlyEdit(profile(), 'http://nas:3000', 'key-2')).assertFalse();
      expect(isNameOnlyEdit(profile(), 'http://nas:3000', '')).assertFalse();
    });
  });
}
