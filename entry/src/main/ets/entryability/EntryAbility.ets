import {
  AbilityConstant,
  Configuration,
  ConfigurationConstant,
  UIAbility,
  Want
} from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppLog } from '../data/log/AppLog';
import { PRIVACY_COVER_KEY, privacyCoverForStageEvent } from '../common/PrivacyCover';

const DOMAIN: number = 0x0000;

export default class EntryAbility extends UIAbility {
  /** Kept so the bar colour can be repainted when the theme changes. */
  private mainWindow: window.Window | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // Started here so the log covers the whole process, including window setup.
    AppLog.initialize(this.context);
    // Unconditional, unlike the log's own entries: it proves the module ran even
    // when logging is switched off.
    hilog.info(DOMAIN, 'LanArk', 'log init: enabled=%{public}s verbose=%{public}s',
      `${AppLog.isEnabled()}`, `${AppLog.isVerbose()}`);
    AppLog.info('ability', 'onCreate');
    AppStorage.setOrCreate('lanarkReaderFullscreen', false);
    AppStorage.setOrCreate(PRIVACY_COVER_KEY, false);
    try {
      this.context.getApplicationContext()
        .setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (error) {
      hilog.error(
        DOMAIN,
        'LanArk',
        'Failed to follow the system color mode. Cause: %{public}s',
        JSON.stringify(error)
      );
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      mainWindow.setWindowLayoutFullScreen(false).catch((error: Object) => {
        hilog.error(
          DOMAIN,
          'LanArk',
          'Failed to restore the system-safe window layout. Cause: %{public}s',
          JSON.stringify(error)
        );
      });
      this.mainWindow = mainWindow;
      this.applySystemBarColors(mainWindow);
      mainWindow.setSpecificSystemBarEnabled('status', true, false)
        .catch((error: Object) => {
          hilog.error(
            DOMAIN,
            'LanArk',
            'Failed to show the portrait status bar. Cause: %{public}s',
            JSON.stringify(error)
          );
        });
      mainWindow.setSpecificSystemBarEnabled('navigation', false, false)
        .catch((error: Object) => {
          hilog.error(
            DOMAIN,
            'LanArk',
            'Failed to hide the navigation bar. Cause: %{public}s',
            JSON.stringify(error)
          );
        });
      mainWindow.setSpecificSystemBarEnabled('navigationIndicator', false, false)
        .catch((error: Object) => {
          hilog.error(
            DOMAIN,
            'LanArk',
            'Failed to hide the navigation indicator. Cause: %{public}s',
            JSON.stringify(error)
          );
        });
      setTimeout(() => {
        mainWindow.setSpecificSystemBarEnabled('navigationIndicator', false, false)
          .catch(() => {});
      }, 400);
    } catch (error) {
      hilog.error(
        DOMAIN,
        'LanArk',
        'Failed to configure the main window. Cause: %{public}s',
        JSON.stringify(error)
      );
    }

    this.watchPrivacyCover(windowStage);

    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(
          DOMAIN,
          'LanArk',
          'Failed to load the main page. Cause: %{public}s',
          JSON.stringify(error)
        );
      }
    });
  }

  /**
   * Covers the app whenever it stops being the foreground window.
   *
   * `PAUSED` is the signal that arrives in time for this. `INACTIVE` alone is not
   * enough: measured on the device, the window goes INACTIVE six milliseconds
   * before it is hidden, less than a frame at 60Hz, so a cover keyed on it alone
   * is drawn too late and the task switcher keeps the clear frame. Both are
   * handled, since which of them comes first is not guaranteed across devices.
   */
  private watchPrivacyCover(windowStage: window.WindowStage): void {
    try {
      windowStage.on('windowStageEvent', (event: window.WindowStageEventType) => {
        const cover: boolean | undefined = privacyCoverForStageEvent(event);
        if (cover === undefined) {
          return;
        }
        AppStorage.setOrCreate(PRIVACY_COVER_KEY, cover);
        AppLog.detail('ability', `privacy cover ${cover ? 'on' : 'off'} (stage event ${event})`);
      });
    } catch (error) {
      hilog.error(
        DOMAIN,
        'LanArk',
        'Failed to watch the window stage. Cause: %{public}s',
        JSON.stringify(error)
      );
    }
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'LanArk', 'onBackground');
    AppStorage.setOrCreate(PRIVACY_COVER_KEY, true);
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'LanArk', 'onForeground');
    AppStorage.setOrCreate(PRIVACY_COVER_KEY, false);
  }

  onWindowStageDestroy(): void {
    this.mainWindow = undefined;
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // The page background follows the light and dark palettes, so the bar that
    // continues it has to be repainted on a theme change as well.
    if (this.mainWindow !== undefined) {
      this.applySystemBarColors(this.mainWindow);
    }
  }

  /**
   * Paints the system bars with the colour the page itself uses.
   *
   * The window does not extend behind the status bar, so that strip is whatever
   * the window's bar colour is: left transparent it renders as black, which cuts
   * a black band across the top of a page whose own background is #0F141A in the
   * dark theme. The colour is read from the resource manager rather than written
   * as a literal so both palettes apply, and the bar's icons are switched to stay
   * readable on it.
   */
  private applySystemBarColors(windowClass: window.Window): void {
    let background: string = '#F5F7FA';
    try {
      const value: number =
        this.context.resourceManager.getColorByNameSync('page_background');
      background = `#${(value & 0xFFFFFF).toString(16).padStart(6, '0')}`;
    } catch (error) {
      hilog.error(
        DOMAIN,
        'LanArk',
        'Failed to read the page background colour. Cause: %{public}s',
        JSON.stringify(error)
      );
    }
    const dark: boolean = this.context.config.colorMode ===
      ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    windowClass.setWindowSystemBarProperties({
      statusBarColor: background,
      statusBarContentColor: dark ? '#FFFFFF' : '#000000',
      navigationBarColor: background
    }).catch((error: Object) => {
      hilog.error(
        DOMAIN,
        'LanArk',
        'Failed to colour the system bars. Cause: %{public}s',
        JSON.stringify(error)
      );
    });
  }
}
