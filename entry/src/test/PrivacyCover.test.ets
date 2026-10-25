import { describe, expect, it } from '@ohos/hypium';
import { window } from '@kit.ArkUI';
import { privacyCoverForStageEvent } from '../main/ets/common/PrivacyCover';

/**
 * The cover has to be up before the system takes the snapshot the task switcher
 * shows, which is why the decision is made on the window stage events.
 */
export default function privacyCoverTest() {
  describe('privacyCover', () => {
    it('covers the app as soon as it loses the foreground', 0, () => {
      const cover: boolean | undefined =
        privacyCoverForStageEvent(window.WindowStageEventType.INACTIVE);
      expect(cover).assertTrue();
    });

    it('uncovers the app when it is the active window again', 0, () => {
      const cover: boolean | undefined =
        privacyCoverForStageEvent(window.WindowStageEventType.ACTIVE);
      expect(cover).assertFalse();
    });

    // HIDDEN and PAUSED arrive after the snapshot was taken, so acting on them
    // would be too late; SHOWN and RESUMED say nothing the other two do not.
    it('leaves the cover alone for events that say nothing about it', 0, () => {
      expect(privacyCoverForStageEvent(window.WindowStageEventType.HIDDEN) === undefined)
        .assertTrue();
      expect(privacyCoverForStageEvent(window.WindowStageEventType.PAUSED) === undefined)
        .assertTrue();
      expect(privacyCoverForStageEvent(window.WindowStageEventType.SHOWN) === undefined)
        .assertTrue();
      expect(privacyCoverForStageEvent(window.WindowStageEventType.RESUMED) === undefined)
        .assertTrue();
    });
  });
}
