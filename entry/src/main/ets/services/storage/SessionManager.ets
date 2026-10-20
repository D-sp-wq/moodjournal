import dataPreferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { Constants } from '../../common/constants/Constants';
import { parseReminderIds, serializeReminderIds } from '../../models/PlanReminder';

/**
 * 会话信息单例：用 preferences 持久化昵称、头像、开始记录日期等本机信息。
 * 单用户模型，不存在账号与绑定关系。
 */
export class SessionManager {
  private static instance: SessionManager | undefined = undefined;
  private pref: dataPreferences.Preferences | undefined = undefined;
  private initialized: boolean = false;

  private static readonly KEY_NICKNAME: string = 'nickname';
  private static readonly KEY_START_DATE: string = 'startDate';
  private static readonly KEY_LAST_LOGGED_DATE: string = 'lastLoggedDate';
  private static readonly KEY_TODAY_MOOD: string = 'todayMood';
  private static readonly KEY_TODAY_CUSTOM_MOOD: string = 'todayCustomMood';
  private static readonly KEY_AVATAR_ID: string = 'avatarId';
  /** 从相册选的头像（file:// 路径）；空串表示用内置头像 */
  private static readonly KEY_AVATAR_URI: string = 'avatarUri';
  private static readonly KEY_MONTHLY_BUDGET: string = 'monthlyBudget';
  private static readonly KEY_PRIVACY_AGREED: string = 'privacyAgreed';
  /** 应用锁：开关 / 密码摘要 / 盐 / 宽限期分钟 */
  private static readonly KEY_LOCK_ENABLED: string = 'lockEnabled';
  private static readonly KEY_LOCK_HASH: string = 'lockHash';
  private static readonly KEY_LOCK_SALT: string = 'lockSalt';
  private static readonly KEY_LOCK_GRACE_MIN: string = 'lockGraceMin';
  /** 今日提醒：开关 / 时 / 分 / 已排期的 reminderId 列表（JSON 字符串） */
  private static readonly KEY_PLAN_REMINDER_ENABLED: string = 'planReminderEnabled';
  private static readonly KEY_PLAN_REMINDER_HOUR: string = 'planReminderHour';
  private static readonly KEY_PLAN_REMINDER_MINUTE: string = 'planReminderMinute';
  private static readonly KEY_PLAN_REMINDER_IDS: string = 'planReminderIds';

  private constructor() {
  }

  static getInstance(): SessionManager {
    if (!SessionManager.instance) {
      SessionManager.instance = new SessionManager();
    }
    return SessionManager.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.initialized) {
      return;
    }
    this.pref = await dataPreferences.getPreferences(context, Constants.PREF_SESSION_NAME);
    this.initialized = true;
  }

  async getNickname(): Promise<string> {
    return await this.pref!.get(SessionManager.KEY_NICKNAME, '我') as string;
  }

  async setNickname(nickname: string): Promise<void> {
    await this.pref!.put(SessionManager.KEY_NICKNAME, nickname);
    await this.pref!.flush();
  }

  /** 选中的内置头像 id（如 'm1' / 'f3'），默认第一个 */
  async getAvatarId(): Promise<string> {
    return await this.pref!.get(SessionManager.KEY_AVATAR_ID, 'm1') as string;
  }

  async setAvatarId(id: string): Promise<void> {
    await this.pref!.put(SessionManager.KEY_AVATAR_ID, id);
    await this.pref!.flush();
  }

  /** 是否已同意隐私政策（首启需同意后才能使用） */
  async isPrivacyAgreed(): Promise<boolean> {
    return await this.pref!.get(SessionManager.KEY_PRIVACY_AGREED, false) as boolean;
  }

  async setPrivacyAgreed(agreed: boolean): Promise<void> {
    await this.pref!.put(SessionManager.KEY_PRIVACY_AGREED, agreed);
    await this.pref!.flush();
  }

  /** 开始记录的日期，空串表示尚未完成初始设置 */
  async getStartDate(): Promise<string> {
    return await this.pref!.get(SessionManager.KEY_START_DATE, '') as string;
  }

  async setStartDate(date: string): Promise<void> {
    await this.pref!.put(SessionManager.KEY_START_DATE, date);
    await this.pref!.flush();
  }

  /** 是否已完成初始设置（导向分流依据） */
  async isInitialized(): Promise<boolean> {
    const start: string = await this.getStartDate();
    return start !== '';
  }

  /** 最近一次记录的日期，供服务卡片判断"今天是否已记录" */
  async getLastLoggedDate(): Promise<string> {
    return await this.pref!.get(SessionManager.KEY_LAST_LOGGED_DATE, '') as string;
  }

  async setLastLoggedDate(date: string): Promise<void> {
    await this.pref!.put(SessionManager.KEY_LAST_LOGGED_DATE, date);
    await this.pref!.flush();
  }

  /** 今日心情枚举值，供服务卡片展示 */
  async getTodayMood(): Promise<number> {
    return await this.pref!.get(SessionManager.KEY_TODAY_MOOD, 0) as number;
  }

  async setTodayMood(mood: number): Promise<void> {
    await this.pref!.put(SessionManager.KEY_TODAY_MOOD, mood);
    await this.pref!.flush();
  }

  /** 今日自定义心情文字，供服务卡片展示（卡片进程不读数据库） */
  async getTodayCustomMood(): Promise<string> {
    return await this.pref!.get(SessionManager.KEY_TODAY_CUSTOM_MOOD, '') as string;
  }

  async setTodayCustomMood(text: string): Promise<void> {
    await this.pref!.put(SessionManager.KEY_TODAY_CUSTOM_MOOD, text);
    await this.pref!.flush();
  }

  /** 月度预算（元）；0 表示未设置 */
  async getMonthlyBudget(): Promise<number> {
    return await this.pref!.get(SessionManager.KEY_MONTHLY_BUDGET, 0) as number;
  }

  async setMonthlyBudget(budget: number): Promise<void> {
    await this.pref!.put(SessionManager.KEY_MONTHLY_BUDGET, budget);
    await this.pref!.flush();
  }

  /** 从相册选的头像（file:// 路径）；空串表示使用内置头像 */
  async getAvatarUri(): Promise<string> {
    return await this.pref!.get(SessionManager.KEY_AVATAR_URI, '') as string;
  }

  async setAvatarUri(uri: string): Promise<void> {
    await this.pref!.put(SessionManager.KEY_AVATAR_URI, uri);
    await this.pref!.flush();
  }

  /** 是否开启应用锁 */
  async isLockEnabled(): Promise<boolean> {
    return await this.pref!.get(SessionManager.KEY_LOCK_ENABLED, false) as boolean;
  }

  /** 密码摘要（SHA-256 十六进制）；空串表示未设置密码 */
  async getLockHash(): Promise<string> {
    return await this.pref!.get(SessionManager.KEY_LOCK_HASH, '') as string;
  }

  /** 密码盐；与摘要成对存在，盐为空一律视为未设置密码 */
  async getLockSalt(): Promise<string> {
    return await this.pref!.get(SessionManager.KEY_LOCK_SALT, '') as string;
  }

  /**
   * 一次性写入密码（盐 + 摘要 + 启用状态）。
   * 先写盐再写摘要再写开关：中途失败时，读到盐有值而摘要为空会按"未设置"处理，
   * 不会把用户锁在门外。
   */
  async setLockCredential(salt: string, hash: string, enabled: boolean): Promise<void> {
    await this.pref!.put(SessionManager.KEY_LOCK_SALT, salt);
    await this.pref!.put(SessionManager.KEY_LOCK_HASH, hash);
    await this.pref!.put(SessionManager.KEY_LOCK_ENABLED, enabled);
    await this.pref!.flush();
  }

  /** 清除密码并关闭应用锁 */
  async clearLockCredential(): Promise<void> {
    await this.pref!.put(SessionManager.KEY_LOCK_SALT, '');
    await this.pref!.put(SessionManager.KEY_LOCK_HASH, '');
    await this.pref!.put(SessionManager.KEY_LOCK_ENABLED, false);
    await this.pref!.flush();
  }

  async setLockEnabled(enabled: boolean): Promise<void> {
    await this.pref!.put(SessionManager.KEY_LOCK_ENABLED, enabled);
    await this.pref!.flush();
  }

  /** 切后台多久后需要重新验证（分钟）；0 表示立即 */
  async getLockGraceMinutes(): Promise<number> {
    return await this.pref!.get(SessionManager.KEY_LOCK_GRACE_MIN, 1) as number;
  }

  async setLockGraceMinutes(minutes: number): Promise<void> {
    await this.pref!.put(SessionManager.KEY_LOCK_GRACE_MIN, minutes);
    await this.pref!.flush();
  }

  // ---------------- 今日提醒 ----------------

  /** 是否开启「今日提醒」；默认关闭（用户没主动开就不打扰） */
  async isPlanReminderEnabled(): Promise<boolean> {
    return await this.pref!.get(SessionManager.KEY_PLAN_REMINDER_ENABLED, false) as boolean;
  }

  async setPlanReminderEnabled(enabled: boolean): Promise<void> {
    await this.pref!.put(SessionManager.KEY_PLAN_REMINDER_ENABLED, enabled);
    await this.pref!.flush();
  }

  /** 提醒的小时（默认 09:00），合法性由 models/PlanReminder.isValidTime 判定 */
  async getPlanReminderHour(): Promise<number> {
    return await this.pref!.get(SessionManager.KEY_PLAN_REMINDER_HOUR, Constants.PLAN_REMINDER_HOUR) as number;
  }

  async setPlanReminderHour(hour: number): Promise<void> {
    await this.pref!.put(SessionManager.KEY_PLAN_REMINDER_HOUR, hour);
    await this.pref!.flush();
  }

  /** 提醒的分钟（默认 00） */
  async getPlanReminderMinute(): Promise<number> {
    return await this.pref!.get(SessionManager.KEY_PLAN_REMINDER_MINUTE, Constants.PLAN_REMINDER_MINUTE) as number;
  }

  async setPlanReminderMinute(minute: number): Promise<void> {
    await this.pref!.put(SessionManager.KEY_PLAN_REMINDER_MINUTE, minute);
    await this.pref!.flush();
  }

  /** 已排期的今日提醒 id 列表；读坏了按空列表处理（最多取消不掉，不会崩） */
  async getPlanReminderIds(): Promise<number[]> {
    const raw: string = await this.pref!.get(SessionManager.KEY_PLAN_REMINDER_IDS, '') as string;
    return parseReminderIds(raw);
  }

  /** 保存已排期的今日提醒 id 列表；空列表存空串 */
  async setPlanReminderIds(ids: number[]): Promise<void> {
    await this.pref!.put(SessionManager.KEY_PLAN_REMINDER_IDS, serializeReminderIds(ids));
    await this.pref!.flush();
  }
}
