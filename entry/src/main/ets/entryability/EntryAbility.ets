import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppLog } from '../data/log/AppLog';
import { PRIVACY_COVER_KEY, privacyCoverForStageEvent } from '../common/PrivacyCover';

const DOMAIN: number = 0x0000;

export default class EntryAbility extends UIAbility {
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
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000'
      }).catch((error: Object) => {
        hilog.error(
          DOMAIN,
          'LanArk',
          'Failed to make system bars transparent. Cause: %{public}s',
          JSON.stringify(error)
        );
      });
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
   * Blurs the app whenever it stops being the foreground window.
   *
   * The switcher shows a snapshot taken as the app goes away, so the cover must
   * be up before that: `INACTIVE` is the first signal that the window is losing
   * the foreground, which leaves a frame to draw into. `onBackground` repeats it
   * as a backstop for devices that do not deliver the stage event in time.
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
    AppLog.info('ability', 'onBackground');
    AppStorage.setOrCreate(PRIVACY_COVER_KEY, true);
  }

  onForeground(): void {
    AppLog.info('ability', 'onForeground');
    AppStorage.setOrCreate(PRIVACY_COVER_KEY, false);
  }
}
