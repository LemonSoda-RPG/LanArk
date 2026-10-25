import { window } from '@kit.ArkUI';

/**
 * AppStorage key the root page reads to know it must cover itself.
 *
 * Also written as a literal in `Index`'s `@StorageProp`, because a decorator
 * argument has to be a literal, so the two names must stay in step.
 */
export const PRIVACY_COVER_KEY: string = 'lanarkPrivacyCover';

/**
 * Whether the application should be covered, for one window-stage event.
 *
 * `INACTIVE` is the first signal that the window is losing the foreground, and
 * `PAUSED` follows it when the ability is actually paused; both mean the app is
 * on its way out, and either may be the one that arrives before the system takes
 * the snapshot the task switcher shows. `ACTIVE` and `RESUMED` mean the app is
 * back in front.
 *
 * Returns `undefined` for the events that say nothing about the cover, so the
 * caller leaves it as it is.
 */
export function privacyCoverForStageEvent(
  event: window.WindowStageEventType): boolean | undefined {
  if (event === window.WindowStageEventType.INACTIVE ||
    event === window.WindowStageEventType.PAUSED) {
    return true;
  }
  if (event === window.WindowStageEventType.ACTIVE ||
    event === window.WindowStageEventType.RESUMED) {
    return false;
  }
  return undefined;
}
