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

    // The ability being paused is the signal the published sample uses, so it
    // covers too: whichever of the two arrives first has to be enough.
    it('covers the app when the ability is paused', 0, () => {
      const cover: boolean | undefined =
        privacyCoverForStageEvent(window.WindowStageEventType.PAUSED);
      expect(cover).assertTrue();
    });

    it('uncovers the app when it is the active window again', 0, () => {
      expect(privacyCoverForStageEvent(window.WindowStageEventType.ACTIVE)).assertFalse();
      expect(privacyCoverForStageEvent(window.WindowStageEventType.RESUMED)).assertFalse();
    });

    // HIDDEN arrives after the snapshot was taken, and SHOWN says nothing the
    // others do not, so neither may touch the cover.
    it('leaves the cover alone for events that say nothing about it', 0, () => {
      expect(privacyCoverForStageEvent(window.WindowStageEventType.HIDDEN) === undefined)
        .assertTrue();
      expect(privacyCoverForStageEvent(window.WindowStageEventType.SHOWN) === undefined)
        .assertTrue();
    });
  });
}
