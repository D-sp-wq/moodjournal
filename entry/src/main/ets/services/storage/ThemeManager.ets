import dataPreferences from '@ohos.data.preferences';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../../common/constants/Constants';

/**
 * 外观模式管理器（日间 / 夜间）
 *
 * 颜色由 base 与 dark 资源限定符承载，这里只负责切换与持久化应用的颜色模式。
 * 不提供「跟随系统」——只保留明确的两档，行为可预期。
 *
 * 关于上下文：启动时 applySavedColorMode 会拿到一个可靠的 UIAbility 上下文，这里把它存下来，
 * 之后切换外观就用它。**不要再让调用方传 getHostContext()** —— 在某些回调里它会返回 undefined，
 * 一旦静默 return，用户看到的就是「点了没反应」。
 */
export class ThemeManager {
  private static instance: ThemeManager | undefined = undefined;

  static readonly MODE_DARK: number = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  static readonly MODE_LIGHT: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  /** 没有保存过时的默认外观 */
  static readonly MODE_DEFAULT: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  private static readonly KEY_THEME_MODE: string = 'themeMode';

  /** 启动时记下来的应用上下文，供后续切换外观使用 */
  private context: common.Context | undefined = undefined;

  private constructor() {
  }

  static getInstance(): ThemeManager {
    if (!ThemeManager.instance) {
      ThemeManager.instance = new ThemeManager();
    }
    return ThemeManager.instance;
  }

  /**
   * 同步读取已保存的外观模式。
   * 未设置过、或存着历史遗留的「跟随系统」(-1) 这类无效值，一律回落到日间，
   * 避免升级上来的用户出现一个选项都不高亮的尴尬状态。
   */
  getMode(context: common.Context): number {
    try {
      const pref = dataPreferences.getPreferencesSync(context, { name: Constants.PREF_SETTINGS_NAME });
      const value = pref.getSync(ThemeManager.KEY_THEME_MODE, ThemeManager.MODE_DEFAULT) as number;
      if (value === ThemeManager.MODE_DARK || value === ThemeManager.MODE_LIGHT) {
        return value;
      }
      return ThemeManager.MODE_DEFAULT;
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '读取外观模式失败: %{public}s', JSON.stringify(err));
      return ThemeManager.MODE_DEFAULT;
    }
  }

  /**
   * 保存并立即应用外观模式。
   * 不接收上下文参数：用启动时存下来的那个，避免回调里 getHostContext() 取不到值。
   * 返回是否真的应用成功，调用方可据此提示用户。
   */
  async setMode(mode: number): Promise<boolean> {
    const ctx: common.Context | undefined = this.context;
    if (ctx === undefined) {
      hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, '切换外观失败：没有可用的应用上下文');
      return false;
    }
    try {
      const pref = dataPreferences.getPreferencesSync(ctx, { name: Constants.PREF_SETTINGS_NAME });
      await pref.put(ThemeManager.KEY_THEME_MODE, mode);
      await pref.flush();
      ctx.getApplicationContext().setColorMode(mode as ConfigurationConstant.ColorMode);
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '外观模式已切换: %{public}d', mode);
      return true;
    } catch (err) {
      hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, '设置外观模式失败: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * 启动时应用已保存的外观模式（同步，须在 loadContent 之前调用以避免首帧闪烁），
   * 同时把这个上下文留存下来供 setMode 使用。
   */
  applySavedColorMode(context: common.Context): void {
    this.context = context;
    try {
      const mode: number = this.getMode(context);
      context.getApplicationContext().setColorMode(mode as ConfigurationConstant.ColorMode);
    } catch (err) {
      hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, '应用外观模式失败: %{public}s', JSON.stringify(err));
    }
  }

  /** 当前是否已经启动过（没启动就没上下文，切换会失败） */
  hasContext(): boolean {
    return this.context !== undefined;
  }
}
