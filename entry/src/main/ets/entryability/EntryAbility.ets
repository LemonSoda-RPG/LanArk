import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN: number = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('lanarkReaderFullscreen', false);
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
}
