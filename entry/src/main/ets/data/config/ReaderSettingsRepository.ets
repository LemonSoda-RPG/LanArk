import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { localized } from '../../common/Localization';

const PREFERENCES_NAME: string = 'lanark_reader_settings';
const DIRECTION_KEY: string = 'reader_direction';
const MODE_KEY: string = 'reader_mode';
const DOUBLE_PAGE_OFFSET_KEY: string = 'reader_double_page_offset';
const PRELOAD_PAGE_COUNT_KEY: string = 'reader_preload_page_count';
const INTERPOLATION_KEY: string = 'reader_interpolation';

export class ReaderSettings {
  readonly directionIndex: number;
  readonly modeIndex: number;
  readonly doublePageOffset: number;
  readonly preloadPageCount: number;
  readonly interpolationIndex: number;

  constructor(
    directionIndex: number = 0,
    modeIndex: number = 0,
    doublePageOffset: number = 0,
    preloadPageCount: number = 3,
    interpolationIndex: number = 3
  ) {
    this.directionIndex = Math.min(Math.max(directionIndex, 0), 1);
    this.modeIndex = Math.min(Math.max(modeIndex, 0), 2);
    this.doublePageOffset = doublePageOffset === 1 ? 1 : 0;
    this.preloadPageCount = ReaderSettings.normalizePreloadPageCount(preloadPageCount);
    this.interpolationIndex = ReaderSettings.normalizeInterpolationIndex(interpolationIndex);
  }

  private static normalizePreloadPageCount(value: number): number {
    const allowedValues: Array<number> = [0, 1, 2, 3, 5, 8];
    return allowedValues.indexOf(value) >= 0 ? value : 3;
  }

  private static normalizeInterpolationIndex(value: number): number {
    return value >= 0 && value <= 3 ? Math.floor(value) : 3;
  }
}

export class ReaderSettingsRepository {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async load(): Promise<ReaderSettings> {
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const direction: number =
        (await store.get(DIRECTION_KEY, 0)) as number;
      const hasMode: boolean = await store.has(MODE_KEY);
      const mode: number = hasMode ?
        (await store.get(MODE_KEY, 0)) as number : (direction === 2 ? 2 : 0);
      const normalizedDirection: number = direction === 1 ? 1 : 0;
      const doublePageOffset: number =
        (await store.get(DOUBLE_PAGE_OFFSET_KEY, 0)) as number;
      const preloadPageCount: number =
        (await store.get(PRELOAD_PAGE_COUNT_KEY, 3)) as number;
      const interpolationIndex: number =
        (await store.get(INTERPOLATION_KEY, 3)) as number;
      return new ReaderSettings(
        normalizedDirection,
        mode,
        doublePageOffset,
        preloadPageCount,
        interpolationIndex
      );
    } catch (error) {
      throw new Error(localized('读取阅读设置失败', 'Could not read reading settings'));
    }
  }

  async save(settings: ReaderSettings): Promise<void> {
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(DIRECTION_KEY, settings.directionIndex);
      await store.put(MODE_KEY, settings.modeIndex);
      await store.put(DOUBLE_PAGE_OFFSET_KEY, settings.doublePageOffset);
      await store.put(PRELOAD_PAGE_COUNT_KEY, settings.preloadPageCount);
      await store.put(INTERPOLATION_KEY, settings.interpolationIndex);
      await store.flush();
    } catch (error) {
      throw new Error(localized('保存阅读设置失败', 'Could not save reading settings'));
    }
  }
}
