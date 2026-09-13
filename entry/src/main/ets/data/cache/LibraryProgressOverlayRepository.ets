import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const PREFERENCES_NAME: string = 'lanark_library_progress';
const OVERLAY_KEY: string = 'progress_overlay';
const READ_KEY: string = 'read_overlay';

/**
 * Page positions and read times changed since the library index was written.
 *
 * The index file embeds every archive together with its tags, so persisting a
 * single page turn used to re-serialise the whole library on the UI thread.
 * Only the archives touched since the last full refresh are kept here as two
 * small maps (page position, last read time) and merged back in when the index
 * is loaded.
 *
 * The server records both values as well, so these maps only cover the window
 * between a page turn and the next full refresh; they exist so the history order
 * survives a restart even when the server does not track reading progress.
 */
export class LibraryProgressOverlayRepository {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async load(): Promise<Record<string, number>> {
    return this.loadNumberMap(OVERLAY_KEY);
  }

  /** Epoch seconds of the last local read, per archive id. */
  async loadReadTimes(): Promise<Record<string, number>> {
    return this.loadNumberMap(READ_KEY);
  }

  private async loadNumberMap(key: string): Promise<Record<string, number>> {
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const raw: preferences.ValueType = await store.get(key, '');
      if (typeof raw !== 'string' || raw.length === 0) {
        return {};
      }
      return JSON.parse(raw) as Record<string, number>;
    } catch (error) {
      // A missing or unreadable overlay simply means nothing has changed yet.
      return {};
    }
  }

  async save(overlay: Record<string, number>, readTimes: Record<string, number>): Promise<void> {
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      // Both maps describe the same page turn, so they share one flush.
      await store.put(OVERLAY_KEY, JSON.stringify(overlay));
      await store.put(READ_KEY, JSON.stringify(readTimes));
      await store.flush();
    } catch (error) {
      // Local progress is best-effort and must never interrupt reading.
    }
  }

  async clear(): Promise<void> {
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.delete(OVERLAY_KEY);
      await store.delete(READ_KEY);
      await store.flush();
    } catch (error) {
      // Best-effort: a stale overlay is merged again on the next full refresh.
    }
  }
}
