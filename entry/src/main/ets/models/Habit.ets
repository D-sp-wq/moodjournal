import { DateUtils } from '../common/utils/DateUtils';

/**
 * 习惯打卡模型（纯函数，可直接单元测试）。
 *
 * 为什么做这个：手机系统只有「运动健康」那种特定打卡，管不了读书、喝水、早睡这类
 * 个人自定义的每日习惯。应用商店审核指南 3.5 明确排除「手机系统自带的简易功能」，
 * 这一块是系统做不到的。
 *
 * 一天一条打卡记录：同一习惯同一天只会有一条。
 */
export interface Habit {
  id: string;
  name: string;
  /** 展示顺序，小的在前 */
  sortOrder: number;
  createdAt: number;
}

export interface HabitCheck {
  id: string;
  habitId: string;
  /** 'yyyy-MM-dd' */
  date: string;
  createdAt: number;
}

/** 最多同时坚持几个习惯（和任务规划保持一致，避免列表失控） */
export const MAX_HABITS: number = 6;
/** 习惯名称长度上限 */
export const MAX_HABIT_NAME_LENGTH: number = 8;
/** 进度默认看多少天 */
export const HABIT_WINDOW_DAYS: number = 30;

/** 一个习惯当前的完成情况 */
export interface HabitProgress {
  habitId: string;
  /** 今天是否打过卡 */
  doneToday: boolean;
  /** 当前连续天数（今天还没打时从昨天往前算，避免早上打开就被清零） */
  streak: number;
  /** 近 window 天的完成率 0-100 */
  rate: number;
  /** 近 window 天里已打卡的天数 */
  doneDays: number;
  /** 近 window 天的总天数 */
  window: number;
}

/** 清洗习惯名称：去空白、截断到上限 */
export function normalizeHabitName(text: string): string {
  const trimmed: string = text.trim();
  return trimmed.length > MAX_HABIT_NAME_LENGTH
    ? trimmed.slice(0, MAX_HABIT_NAME_LENGTH)
    : trimmed;
}

/** 还能再加几个习惯 */
export function remainingHabitSlots(current: number): number {
  const left: number = MAX_HABITS - current;
  return left > 0 ? left : 0;
}

/**
 * 当前连续打卡天数。
 * 今天已打卡则从今天起算；今天还没打卡则从昨天起算——否则每天早上一打开，
 * 昨天刚建立起来的连续记录就会显示成 0，体验很糟。
 */
export function computeHabitStreak(checks: string[], todayStr: string): number {
  if (checks.length === 0) {
    return 0;
  }
  const set: Set<string> = new Set(checks);
  let cursor: string = set.has(todayStr) ? todayStr : DateUtils.addDays(todayStr, -1);
  let streak: number = 0;
  while (set.has(cursor)) {
    streak += 1;
    cursor = DateUtils.addDays(cursor, -1);
  }
  return streak;
}

/** 汇总一个习惯在近 window 天的完成情况 */
export function computeHabitProgress(
  habitId: string,
  checks: string[],
  todayStr: string,
  window: number
): HabitProgress {
  const safeWindow: number = window > 0 ? window : HABIT_WINDOW_DAYS;
  const set: Set<string> = new Set(checks);
  let doneDays: number = 0;
  for (let i: number = 0; i < safeWindow; i++) {
    if (set.has(DateUtils.addDays(todayStr, -i))) {
      doneDays += 1;
    }
  }
  return {
    habitId: habitId,
    doneToday: set.has(todayStr),
    streak: computeHabitStreak(checks, todayStr),
    rate: Math.round(doneDays * 100 / safeWindow),
    doneDays: doneDays,
    window: safeWindow
  };
}

/** 近 window 天里某一天的打卡状态，供条带展示（按日期升序） */
export interface HabitDay {
  date: string;
  done: boolean;
}

export function buildHabitDays(checks: string[], todayStr: string, window: number): HabitDay[] {
  const safeWindow: number = window > 0 ? window : HABIT_WINDOW_DAYS;
  const set: Set<string> = new Set(checks);
  const out: HabitDay[] = [];
  for (let i: number = safeWindow - 1; i >= 0; i--) {
    const date: string = DateUtils.addDays(todayStr, -i);
    out.push({ date: date, done: set.has(date) });
  }
  return out;
}

/** 把打卡记录按 habitId 分组 */
export function groupChecksByHabit(checks: HabitCheck[]): Map<string, string[]> {
  const map: Map<string, string[]> = new Map();
  for (const item of checks) {
    const list: string[] | undefined = map.get(item.habitId);
    if (list === undefined) {
      map.set(item.habitId, [item.date]);
    } else {
      list.push(item.date);
    }
  }
  return map;
}
