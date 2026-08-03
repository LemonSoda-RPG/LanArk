import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { localized } from '../../common/Localization';

const PREFERENCES_NAME: string = 'lanark_library_settings';
const SORT_MODE_KEY: string = 'library_sort_mode';
const SORT_ASCENDING_KEY: string = 'library_sort_ascending';
const HIDE_COMPLETED_KEY: string = 'library_hide_completed';
const GRID_LAYOUT_KEY: string = 'library_grid_layout';
const GRID_COLUMNS_KEY: string = 'library_grid_columns';

export class LibrarySettings {
  readonly sortModeIndex: number;
  readonly sortAscending: boolean;
  readonly hideCompleted: boolean;
  readonly gridLayout: boolean;
  readonly gridColumns: number;

  constructor(
    sortModeIndex: number = 0,
    sortAscending: boolean = false,
    hideCompleted: boolean = false,
    gridLayout: boolean = false,
    gridColumns: number = 0
  ) {
    this.sortModeIndex = Math.min(Math.max(sortModeIndex, 0), 11);
    this.sortAscending = sortAscending;
    this.hideCompleted = hideCompleted;
    this.gridLayout = gridLayout;
    const allowedValues: Array<number> = [0, 2, 3, 4, 5, 6];
    this.gridColumns = allowedValues.indexOf(gridColumns) >= 0 ? gridColumns : 0;
  }
}

export class LibrarySettingsRepository {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async load(): Promise<LibrarySettings> {
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      const sortModeIndex: number =
        (await store.get(SORT_MODE_KEY, 0)) as number;
      const sortAscending: boolean =
        (await store.get(SORT_ASCENDING_KEY, false)) as boolean;
      const hideCompleted: boolean =
        (await store.get(HIDE_COMPLETED_KEY, false)) as boolean;
      const gridLayout: boolean =
        (await store.get(GRID_LAYOUT_KEY, false)) as boolean;
      const gridColumns: number =
        (await store.get(GRID_COLUMNS_KEY, 0)) as number;
      return new LibrarySettings(
        sortModeIndex,
        sortAscending,
        hideCompleted,
        gridLayout,
        gridColumns
      );
    } catch (error) {
      throw new Error(localized('读取书库设置失败', 'Could not read library settings'));
    }
  }

  async save(settings: LibrarySettings): Promise<void> {
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, PREFERENCES_NAME);
      await store.put(SORT_MODE_KEY, settings.sortModeIndex);
      await store.put(SORT_ASCENDING_KEY, settings.sortAscending);
      await store.put(HIDE_COMPLETED_KEY, settings.hideCompleted);
      await store.put(GRID_LAYOUT_KEY, settings.gridLayout);
      await store.put(GRID_COLUMNS_KEY, settings.gridColumns);
      await store.flush();
    } catch (error) {
      throw new Error(localized('保存书库设置失败', 'Could not save library settings'));
    }
  }
}
