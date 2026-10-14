/**
 * 应用全局常量定义
 * 颜色统一使用资源引用，由 base / dark 资源限定符自动适配日间与夜间模式
 */
export class Constants {
  // 偏好存储名称（用于会话信息缓存）
  static readonly PREF_SESSION_NAME: string = 'journal_session';

  // 偏好存储名称（用于应用设置，如外观模式）
  static readonly PREF_SETTINGS_NAME: string = 'journal_settings';

  // 关系型数据库名称
  static readonly DB_NAME: string = 'mood_journal.db';

  // 主题配色（暖黄奶咖系，随日间/夜间自动切换）
  static readonly COLOR_PRIMARY: Resource = $r('app.color.brand_primary');
  static readonly COLOR_PRIMARY_LIGHT: Resource = $r('app.color.brand_primary_light');
  static readonly COLOR_BACKGROUND: Resource = $r('app.color.page_background');
  static readonly COLOR_CARD: Resource = $r('app.color.card_background');
  static readonly COLOR_SURFACE_SECONDARY: Resource = $r('app.color.surface_secondary');
  static readonly COLOR_BORDER_SUBTLE: Resource = $r('app.color.border_subtle');
  static readonly COLOR_PRESSED_SURFACE: Resource = $r('app.color.pressed_surface');
  static readonly COLOR_TEXT_PRIMARY: Resource = $r('app.color.text_primary');
  static readonly COLOR_TEXT_SECONDARY: Resource = $r('app.color.text_secondary');
  static readonly COLOR_TEXT_TERTIARY: Resource = $r('app.color.text_tertiary');
  static readonly COLOR_DIVIDER: Resource = $r('app.color.divider');

  // 通用色
  static readonly COLOR_ON_BRAND: Resource = $r('app.color.on_brand');
  static readonly COLOR_WHITE: Resource = $r('app.color.white');
  static readonly COLOR_TRANSPARENT: Resource = $r('app.color.transparent');
  static readonly COLOR_SHADOW: Resource = $r('app.color.shadow');
  static readonly COLOR_TRACK: Resource = $r('app.color.track');

  // 顶部英雄区渐变
  static readonly COLOR_HERO_START: Resource = $r('app.color.hero_start');
  static readonly COLOR_HERO_END: Resource = $r('app.color.hero_end');

  // 日志域名与标签
  static readonly LOG_DOMAIN: number = 0x0000;
  static readonly LOG_TAG: string = 'MoodJournal';

  // 每日记录提醒默认时间（21:00）
  static readonly REMINDER_HOUR: number = 21;
  static readonly REMINDER_MINUTE: number = 0;

  // 单条记录正文长度上限（避免异常输入撑爆数据库）
  static readonly MAX_JOURNAL_LENGTH: number = 2000;
  static readonly MAX_PLAN_LENGTH: number = 500;
}
