import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
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
    this.tryWindowPrivacyMode(windowStage);

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
   * What this can and cannot do is worth stating, because the window is short:
   * the window goes INACTIVE about six milliseconds before the snapshot the task
   * switcher shows is taken, and a frame is nearer sixteen, so the snapshot is
   * very likely to hold the frame from before the cover was drawn. It is kept
   * because it is free and correct where the snapshot comes later, but the only
   * reliable protection is `setWindowPrivacyMode`, which needs a restricted
   * permission — see `tryWindowPrivacyMode`.
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

  /**
   * Asks the window manager to keep this window's content out of screenshots and
   * out of the snapshot the task switcher shows.
   *
   * Drawing the cover cannot win on its own: the window goes INACTIVE about six
   * milliseconds before the snapshot is taken, which is less than a frame, so the
   * snapshot holds the frame from before the cover. This flag is the platform's
   * own mechanism and takes effect without a frame.
   *
   * `ohos.permission.PRIVACY_WINDOW` is a restricted permission, so a refusal is
   * the expected outcome on a normal build; the drawn cover then remains the only
   * protection, and it is best effort.
   */
  private async tryWindowPrivacyMode(windowStage: window.WindowStage): Promise<void> {
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      await mainWindow.setWindowPrivacyMode(true);
      hilog.info(DOMAIN, 'LanArk', 'window privacy mode: on');
    } catch (error) {
      hilog.error(DOMAIN, 'LanArk', 'window privacy mode refused: code=%{public}s',
        `${(error as BusinessError).code}`);
    }
  }
}
