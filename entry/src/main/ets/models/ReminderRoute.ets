/**
 * 提醒 → 落地页的纯函数映射。
 *
 * 四类后台提醒（每日记录 / 今日提醒 / 习惯打卡 / 重要日子）都通过
 * `wantAgent.parameters[ROUTE_PARAM_KEY]` 携带一个字符串，
 * EntryAbility 收到后写进 AppStorage('pendingRoute')，由首页在解锁后消费。
 *
 * 这里刻意只依赖 DateUtils（纯函数、无系统 API），
 * 既可以在 Ability / 页面里共用，也能被本地单元测试直接覆盖。
 */
import { DateUtils } from '../common/utils/DateUtils';

/** 提醒种类 */
export enum ReminderKind {
  DAILY_RECORD,
  TODAY_PLAN,
  HABIT,
  ANNIVERSARY
}

/** 通知里传递目标页面的参数 key（WantAgent.parameters / Want.parameters 通用） */
export const ROUTE_PARAM_KEY: string = 'target';

/**
 * 从通知带进来、尚未消费的目标路由。
 * EntryAbility 写入，HomePage 在确认已解锁后读取并清空。
 */
export const PENDING_ROUTE_KEY: string = 'pendingRoute';

/** 各提醒种类对应的路由参数值（稳定字符串，改动会让已排期的提醒失效） */
const PARAM_RECORD: string = 'record';
const PARAM_PLAN: string = 'plan';
const PARAM_HABIT: string = 'habit';
const PARAM_ANNIVERSARY: string = 'anniversary';

/** 提醒种类 → 点击通知后应打开的页面（必须在 main_pages.json 里注册过） */
export function pageForReminder(kind: ReminderKind): string {
  switch (kind) {
    case ReminderKind.DAILY_RECORD:
      return 'pages/RecordPage';
    case ReminderKind.TODAY_PLAN:
      return 'pages/HomePage';
    case ReminderKind.HABIT:
      return 'pages/HabitPage';
    case ReminderKind.ANNIVERSARY:
      return 'pages/AnniversaryPage';
    default:
      return 'pages/HomePage';
  }
}

/** 提醒种类 → 路由参数值（如 'habit'） */
export function routeParamValue(kind: ReminderKind): string {
  switch (kind) {
    case ReminderKind.DAILY_RECORD:
      return PARAM_RECORD;
    case ReminderKind.TODAY_PLAN:
      return PARAM_PLAN;
    case ReminderKind.HABIT:
      return PARAM_HABIT;
    case ReminderKind.ANNIVERSARY:
      return PARAM_ANNIVERSARY;
    default:
      return PARAM_PLAN;
  }
}

/** 路由参数值 → 提醒种类；未知（含空串、旧参数）返回 null */
export function kindFromParam(value: string): ReminderKind | null {
  if (value === PARAM_RECORD) {
    return ReminderKind.DAILY_RECORD;
  }
  if (value === PARAM_PLAN) {
    return ReminderKind.TODAY_PLAN;
  }
  if (value === PARAM_HABIT) {
    return ReminderKind.HABIT;
  }
  if (value === PARAM_ANNIVERSARY) {
    return ReminderKind.ANNIVERSARY;
  }
  return null;
}

/**
 * 构造 ReminderRequest.wantAgent.parameters。
 *
 * 类型对齐 SDK：`reminderAgentManager.WantAgent.parameters?: Record<string, Object>`
 * （见 @ohos.reminderAgentManager.d.ts），字符串值天然是 Object，可直接赋值。
 */
export function buildWantAgentParams(kind: ReminderKind): Record<string, string> {
  const params: Record<string, string> = {};
  params[ROUTE_PARAM_KEY] = routeParamValue(kind);
  return params;
}

// ---------------- 重要日子：提前提醒 ----------------

/** 提前提醒可选天数（当天 / 提前 1 天 / 提前 3 天） */
export const ANNIVERSARY_ADVANCE_OPTIONS: number[] = [0, 1, 3];

/** 默认提前 1 天 */
export const DEFAULT_ANNIVERSARY_ADVANCE_DAYS: number = 1;

/** 把任意输入归一到允许的提前天数：不在 0 / 1 / 3 里的一律按默认 1 天 */
export function normalizeAdvanceDays(days: number): number {
  for (const option of ANNIVERSARY_ADVANCE_OPTIONS) {
    if (option === days) {
      return option;
    }
  }
  return DEFAULT_ANNIVERSARY_ADVANCE_DAYS;
}

/**
 * 提醒日 = 纪念日 - 提前天数。
 * 跨月、跨年、闰年全部交给 DateUtils.addDays，不在这里手写月份天数。
 */
export function reminderDateFor(dateStr: string, advanceDays: number): string {
  return DateUtils.addDays(dateStr, -advanceDays);
}

/** 提前提醒的正文：0 天「今天是」/ 1 天「明天是」/ N 天「还有 N 天是」 */
export function anniversaryReminderText(title: string, advanceDays: number): string {
  if (advanceDays <= 0) {
    return `今天是「${title}」`;
  }
  if (advanceDays === 1) {
    return `明天是「${title}」`;
  }
  return `还有 ${advanceDays} 天是「${title}」`;
}

/**
 * 提醒时刻是否还没到。
 *
 * 与「今日提醒」跳过已过时刻的思路一致：已过或正好到点都返回 false，
 * 避免一打开应用就把过期的一次性提醒立刻补弹出来。
 *
 * @param reminderDate 提醒日 'yyyy-MM-dd'
 * @param hour 提醒小时
 * @param minute 提醒分钟
 * @param now 当前时间
 */
export function shouldScheduleAt(reminderDate: string, hour: number, minute: number, now: Date): boolean {
  if (!DateUtils.isValidDateStr(reminderDate)) {
    return false;
  }
  const target: Date = DateUtils.parseDate(reminderDate);
  target.setHours(hour, minute, 0, 0);
  return target.getTime() > now.getTime();
}
