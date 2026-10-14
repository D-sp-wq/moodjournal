import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ThemeManager } from '../services/storage/ThemeManager';
import { AppLockManager } from '../services/storage/AppLockManager';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  /** 主窗口，供锁屏页推送使用 */
  private mainWindow: window.Window | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 冷启动：进程刚起来，内存里的时间戳无意义，若开了应用锁则需要验证
    AppLockManager.getInstance().markColdStart();
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 先应用已保存的外观模式，再加载页面，避免首帧闪烁
    ThemeManager.getInstance().applySavedColorMode(this.context);

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      this.watchNavigationBar(windowStage);
    });
  }

  /**
   * 底部导航条（手势指示条）适配。
   *
   * 应用商店上架后会检查「底部导航条适配」：底部页签栏与底部操作区必须避让系统的
   * 导航条，不能贴屏/被遮挡。这里读出导航条高度写进 AppStorage，页面按它留出间距。
   *
   * 刻意不启用全屏沉浸式（setWindowLayoutFullScreen），否则四个方向的安全区都要自己处理，
   * 回归面太大；只取底部这一段，按需留白。
   */
  private watchNavigationBar(windowStage: window.WindowStage): void {
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      this.mainWindow = mainWindow;
      this.writeBottomInset(mainWindow);

      // 用户在系统设置里从手势导航切到三键导航时高度会变，需要跟着刷新
      mainWindow.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
        if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          this.writeBottomInset(mainWindow);
        }
      });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'watchNavigationBar failed: %{public}s', JSON.stringify(err));
      AppStorage.setOrCreate<number>('bottomInset', 0);
    }
  }

  private writeBottomInset(mainWindow: window.Window): void {
    try {
      const area: window.AvoidArea = mainWindow.getWindowAvoidArea(
        window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const inset: number = area.bottomRect.height > 0 ? px2vp(area.bottomRect.height) : 0;
      AppStorage.setOrCreate<number>('bottomInset', inset);
    } catch (err) {
      AppStorage.setOrCreate<number>('bottomInset', 0);
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // 回到前台：超过宽限期则要求重新验证密码（AppLockManager 内部判定）
    AppLockManager.getInstance().onForeground();
    this.pushLockPageIfNeeded();
  }

  /**
   * 需要解锁时把锁屏页推到最上层。
   *
   * 放在 Ability 里做，是为了**只用一个点覆盖全部页面**：用户切回来时可能停在
   * 记录页、搜索页或任何一页，逐个页面写 onPageShow 检查容易漏。
   */
  private pushLockPageIfNeeded(): void {
    if (!AppLockManager.getInstance().needsUnlock()) {
      return;
    }
    try {
      const mainWindow: window.Window | undefined = this.mainWindow;
      if (mainWindow === undefined) {
        return;
      }
      const router = mainWindow.getUIContext().getRouter();
      const top = router.getState();
      if (top !== undefined && top.name === 'LockPage') {
        return;
      }
      router.pushUrl({ url: 'pages/LockPage' });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'pushLockPageIfNeeded failed: %{public}s', JSON.stringify(err));
    }
  }

  onBackground(): void {
    // 进入后台记下时间戳，用于判断回来时是否需要重新验证
    AppLockManager.getInstance().onBackground();
  }
}