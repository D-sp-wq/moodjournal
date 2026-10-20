/**
 * 「今日提醒」：纯函数模型（不读存储、不碰界面，可直接单元测试）。
 *
 * 提醒的语义照抄 DailyLog.plan：日期 D 要做的事写在 **D-1** 那条记录的 plan 里
 * （见 DayPlanPage 的写入规则、HomePage 的读取规则）。
 * 所以这里只接收调用方按该规则取好的 { date, plan }，不自己算日期、不碰数据库。
 *
 * 全离线：提醒由系统「提醒」服务在本地定时触发，不联网、不上传任何数据。
 */

/** 今日提醒设置：开关 + 每天几点几分 */
export interface PlanReminderSettings {
  enabled: boolean;
  hour: number;
  minute: number;
}

/** 某一天要做的事；date 是「要做这件事」的那一天（不是它被存进去的那一天） */
export interface DayPlan {
  date: string;
  plan: string;
}

/** 是否为整数（用 Math.floor 判断，避免依赖 Number.isInteger） */
function isWholeNumber(value: number): boolean {
  return Math.floor(value) === value;
}

/** 补零：9 → '09'；其它（含负数、两位以上）原样输出 */
function pad2(value: number): string {
  return value >= 0 && value < 10 ? `0${value}` : `${value}`;
}

/**
 * 时间 → 'HH:mm'。只负责补零，不做合法性校验（校验用 isValidTime）。
 * 例：formatTime(9, 0) === '09:00'，formatTime(23, 59) === '23:59'。
 */
export function formatTime(hour: number, minute: number): string {
  return `${pad2(hour)}:${pad2(minute)}`;
}

/**
 * 时间是否合法：小时 0..23、分钟 0..59，且都是整数。
 * 小数、NaN、越界一律不合法 —— 脏数据宁可不排提醒，也不要排到错误的时间上。
 */
export function isValidTime(hour: number, minute: number): boolean {
  if (!isWholeNumber(hour) || !isWholeNumber(minute)) {
    return false;
  }
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

/**
 * 计划 → 通知正文摘要。
 *
 * 规则：去掉首尾空白（含换行/制表）；空串返回空串（调用方据此跳过这一天）；
 * 超过 maxLen 个字符时截断并追加 '…'（与 logSummary 的既有写法一致：
 * 结果长度是 maxLen + 1）。maxLen <= 0 视为「不可展示」，返回空串。
 */
export function reminderContent(plan: string, maxLen: number): string {
  const text: string = plan.trim();
  if (text === '' || maxLen <= 0) {
    return '';
  }
  return text.length <= maxLen ? text : `${text.slice(0, maxLen)}…`;
}

/**
 * 一组 { date, plan } → 只保留 plan 非空的条目（决定给哪几天排提醒）。
 *
 * plan 只有空白（空格/换行/制表）也算空，直接丢掉；留下来的 plan 顺手去首尾空白，
 * 让输出是规范的（正文截断交给 reminderContent）。保持传入顺序，不去重、不排序。
 */
export function buildReminderPlan(dayPlans: DayPlan[]): DayPlan[] {
  const result: DayPlan[] = [];
  for (const item of dayPlans) {
    const raw: string = item.plan;
    const plan: string = raw === undefined || raw === null ? '' : raw.trim();
    if (plan === '') {
      continue;
    }
    result.push({ date: item.date, plan: plan });
  }
  return result;
}

/**
 * 该设置下是否应该排提醒：开关打开 **且** 时间是合法时间。
 *
 * 这是「设置关闭时不应发布」这条规则的唯一判定处：
 * PlanReminderService.sync() 与 ReminderService.publishPlanReminders() 都走它，
 * 所以哪怕日历上有安排，关掉开关也不会排任何提醒。
 */
export function shouldPublish(settings: PlanReminderSettings): boolean {
  return settings.enabled && isValidTime(settings.hour, settings.minute);
}

/**
 * 状态文案：开启时显示时间（如 '09:00'），关闭时显示 '已关闭'。
 * 开启但时间非法（脏数据）也按 '已关闭' 显示 —— 那种情况下确实不会排提醒。
 */
export function planReminderStatusLabel(enabled: boolean, hour: number, minute: number): string {
  if (!enabled || !isValidTime(hour, minute)) {
    return '已关闭';
  }
  return formatTime(hour, minute);
}

/**
 * 已排期的 reminderId 列表 → 存 preferences 的字符串。
 * 空列表存空串（与 DailyLog.serializeTags 的既有约定一致）。
 */
export function serializeReminderIds(ids: number[]): string {
  if (ids.length === 0) {
    return '';
  }
  return JSON.stringify(ids);
}

/**
 * preferences 里的字符串 → reminderId 列表。
 * 空串、坏 JSON、非数组、非整数项一律丢弃，绝不抛错：读坏了最多是提醒没取消成功，
 * 不能让设置页或启动流程跟着崩。
 */
export function parseReminderIds(raw: string): number[] {
  const out: number[] = [];
  if (raw === '') {
    return out;
  }
  try {
    const parsed = JSON.parse(raw) as number[];
    if (!parsed || !Array.isArray(parsed)) {
      return out;
    }
    for (const item of parsed) {
      if (typeof item !== 'number' || !isWholeNumber(item) || item < 0) {
        continue;
      }
      out.push(item);
    }
  } catch (err) {
    return out;
  }
  return out;
}
