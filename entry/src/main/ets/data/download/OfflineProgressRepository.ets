import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const PREFERENCES_NAME: string = 'lanark_offline_progress';

/** Stores one-based page positions for archives opened from the offline library. */
export class OfflineProgressRepository {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async load(archiveId: string): Promise<number> {
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const value: number = (await store.get(this.key(archiveId), 0)) as number;
      return Number.isFinite(value) && value > 0 ? Math.floor(value) : 0;
    } catch (error) {
      return 0;
    }
  }

  async save(archiveId: string, oneBasedPageNumber: number): Promise<void> {
    if (archiveId.length === 0 || oneBasedPageNumber <= 0) {
      return;
    }
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(this.key(archiveId), Math.floor(oneBasedPageNumber));
      await store.flush();
    } catch (error) {
      // Local progress is best-effort and must never interrupt reading.
    }
  }

  async clear(archiveId: string): Promise<void> {
    if (archiveId.length === 0) {
      return;
    }
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.delete(this.key(archiveId));
      await store.flush();
    } catch (error) {
      // Best-effort cleanup when a downloaded archive is deleted.
    }
  }

  private key(archiveId: string): string {
    let hash: number = 5381;
    for (let index = 0; index < archiveId.length; index += 1) {
      hash = ((hash * 33) ^ archiveId.charCodeAt(index)) >>> 0;
    }
    return `archive-${hash.toString(16)}`;
  }
}
