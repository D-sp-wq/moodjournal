import { DateUtils } from '../common/utils/DateUtils';

/**
 * 习惯打卡模型（纯函数，可直接单元测试）。
 *
 * 为什么做这个：手机系统只有「运动健康」那种特定打卡，管不了读书、喝水、早睡这类
 * 个人自定义的每日习惯。应用商店审核指南 3.5 明确排除「手机系统自带的简易功能」，
 * 这一块是系统做不到的。
 *
 * 一天可以打多次：同一习惯同一天最多 timesPerDay 条记录，用 slotIndex 区分第几次。
 * 老数据（timesPerDay=1、slotIndex=0）与原来的「一天一条」语义完全等价。
 */
export interface Habit {
  id: string;
  name: string;
  /** 展示顺序，小的在前 */
  sortOrder: number;
  createdAt: number;
  /** 每天几次（1..MAX_HABIT_TIMES） */
  timesPerDay: number;
  /** 每个时段的提醒时间，长度对齐 timesPerDay，元素为 'HH:mm'；空串表示这个时段没设时间 */
  slotTimes: string[];
  /** 是否按时段定时提醒 */
  reminderEnabled: boolean;
}

export interface HabitCheck {
  id: string;
  habitId: string;
  /** 'yyyy-MM-dd' */
  date: string;
  createdAt: number;
  /** 第几次（0 基） */
  slotIndex: number;
}

/** 最多同时坚持几个习惯（和任务规划保持一致，避免列表失控） */
export const MAX_HABITS: number = 6;
/** 一个习惯每天最多分几次 */
export const MAX_HABIT_TIMES: number = 4;
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

// ---------------- 一天多次打卡：时段相关的纯函数 ----------------

/**
 * 每天次数：夹到 1..MAX_HABIT_TIMES。
 * 非整数、NaN、无穷大、缺失都按 1 处理 —— 脏数据宁可退回「一天一次」，
 * 也不要排出一堆重复提醒或者画出不存在的时段。
 */
export function normalizeTimesPerDay(n: number): number {
  if (typeof n !== 'number' || !Number.isFinite(n) || Math.floor(n) !== n) {
    return 1;
  }
  if (n < 1) {
    return 1;
  }
  if (n > MAX_HABIT_TIMES) {
    return MAX_HABIT_TIMES;
  }
  return n;
}

/** 是不是两位数字（'０９' 这种全角数字不算） */
function isTwoDigits(text: string): boolean {
  if (text.length !== 2) {
    return false;
  }
  for (let i: number = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}

/**
 * 严格 'HH:mm'：必须正好 5 个字符、第 3 个是半角冒号、时分各两位数字，
 * 且 00..23 / 00..59。所以 '00:00'、'23:59' 合法，'24:00'、'9:00'、'09:60' 都不合法。
 */
export function isValidSlotTime(text: string): boolean {
  if (typeof text !== 'string' || text.length !== 5) {
    return false;
  }
  if (text.charAt(2) !== ':') {
    return false;
  }
  const hourText: string = text.slice(0, 2);
  const minuteText: string = text.slice(3, 5);
  if (!isTwoDigits(hourText) || !isTwoDigits(minuteText)) {
    return false;
  }
  const hour: number = Number(hourText);
  const minute: number = Number(minuteText);
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

/** 补零到两位：9 → '09'；formatSlotTime(9, 5) === '09:05' */
export function formatSlotTime(hour: number, minute: number): string {
  const h: string = hour >= 0 && hour < 10 ? `0${hour}` : `${hour}`;
  const m: string = minute >= 0 && minute < 10 ? `0${minute}` : `${minute}`;
  return `${h}:${m}`;
}

/**
 * 把任意长度的时间数组对齐到 timesPerDay：
 * - 不够的补空串（表示这个时段还没设时间）
 * - 多出来的截掉
 * - 非法的时间置空串（宁可不提醒，也不要提醒到错误时间）
 */
export function normalizeSlotTimes(timesPerDay: number, raw: string[]): string[] {
  const total: number = normalizeTimesPerDay(timesPerDay);
  const source: string[] = raw === undefined || raw === null ? [] : raw;
  const out: string[] = [];
  for (let i: number = 0; i < total; i++) {
    const item: string = i < source.length ? source[i] : '';
    out.push(isValidSlotTime(item) ? item : '');
  }
  return out;
}

/**
 * 某习惯某天已完成几个时段。
 * 只计 0 <= slotIndex < timesPerDay 的记录；同一个 slotIndex 有多条（脏数据）只算一次。
 */
export function countDoneSlots(
  checks: HabitCheck[],
  habitId: string,
  date: string,
  timesPerDay: number
): number {
  const total: number = normalizeTimesPerDay(timesPerDay);
  const seen: Set<number> = new Set();
  for (const check of checks) {
    if (check.habitId !== habitId || check.date !== date) {
      continue;
    }
    if (check.slotIndex < 0 || check.slotIndex >= total) {
      continue;
    }
    seen.add(check.slotIndex);
  }
  return seen.size;
}

/** 某习惯某天是不是全部时段都打了卡（单次习惯即「今天打过卡」） */
export function isHabitFullyDone(
  checks: HabitCheck[],
  habitId: string,
  date: string,
  timesPerDay: number
): boolean {
  const total: number = normalizeTimesPerDay(timesPerDay);
  return countDoneSlots(checks, habitId, date, timesPerDay) >= total;
}

/**
 * 每个习惯「当天全部次数都完成」的日期列表（升序）。
 *
 * 这是多时段折算的唯一入口：拿到日期数组后再交给 computeHabitStreak /
 * computeHabitProgress / buildHabitDays，那几个函数的语义因此一行都不用改。
 * 习惯已删除时残留的打卡记录会被忽略；没有打卡的习惯也会返回空数组。
 */
export function fullyDoneDates(habits: Habit[], checks: HabitCheck[]): Map<string, string[]> {
  // habitId → (date → 已完成的 slotIndex 集合)
  const done: Map<string, Map<string, Set<number>>> = new Map();
  for (const habit of habits) {
    done.set(habit.id, new Map());
  }
  for (const check of checks) {
    const perDate: Map<string, Set<number>> | undefined = done.get(check.habitId);
    if (perDate === undefined) {
      continue;
    }
    let slots: Set<number> | undefined = perDate.get(check.date);
    if (slots === undefined) {
      slots = new Set();
      perDate.set(check.date, slots);
    }
    slots.add(check.slotIndex);
  }
  const result: Map<string, string[]> = new Map();
  for (const habit of habits) {
    const perDate: Map<string, Set<number>> | undefined = done.get(habit.id);
    const total: number = normalizeTimesPerDay(habit.timesPerDay);
    const dates: string[] = [];
    if (perDate !== undefined) {
      perDate.forEach((slots: Set<number>, date: string) => {
        let count: number = 0;
        slots.forEach((slotIndex: number) => {
          if (slotIndex >= 0 && slotIndex < total) {
            count += 1;
          }
        });
        if (count >= total) {
          dates.push(date);
        }
      });
    }
    dates.sort((a: string, b: string): number => {
      if (a < b) {
        return -1;
      }
      return a > b ? 1 : 0;
    });
    result.set(habit.id, dates);
  }
  return result;
}

/** 一条待排期的习惯提醒（由 buildReminderSlots 产出，供 ReminderService 排期） */
export interface HabitReminderSlot {
  habitId: string;
  name: string;
  slotIndex: number;
  hour: number;
  minute: number;
  /** 这个习惯一天总共几次，用于文案「第 x/N 次」 */
  total: number;
}

/**
 * 习惯列表 → 需要排期的提醒时段。
 *
 * 只保留 reminderEnabled === true 且时间合法的时段；同一习惯同一时刻只排一条
 * （比如「早上一次、晚上一次」被设成了同一时间，没必要弹两次）。
 * 不同习惯的同一时刻互不影响。
 */
export function buildReminderSlots(habits: Habit[]): HabitReminderSlot[] {
  const out: HabitReminderSlot[] = [];
  const seen: Set<string> = new Set();
  for (const habit of habits) {
    if (!habit.reminderEnabled) {
      continue;
    }
    const total: number = normalizeTimesPerDay(habit.timesPerDay);
    const times: string[] = normalizeSlotTimes(total, habit.slotTimes);
    for (let i: number = 0; i < total; i++) {
      const text: string = times[i];
      if (!isValidSlotTime(text)) {
        continue;
      }
      const key: string = `${habit.id}|${text}`;
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      const name: string = habit.name === undefined || habit.name === null ? '' : habit.name;
      out.push({
        habitId: habit.id,
        name: name,
        slotIndex: i,
        hour: Number(text.slice(0, 2)),
        minute: Number(text.slice(3, 5)),
        total: total
      });
    }
  }
  return out;
}

/**
 * 时段列表 → 存库字符串（JSON）。空列表存空串，与 tags / photoUris 的既有约定一致。
 *
 * 用 JSON 而不是逗号分隔：位置就是时段序号，必须保持数组形状。
 */
export function serializeSlotTimes(times: string[]): string {
  if (times.length === 0) {
    return '';
  }
  return JSON.stringify(times);
}

/**
 * 存库字符串 → 时段列表。空串 / 坏 JSON / 非数组一律回退空数组，绝不抛错。
 *
 * 注意：**位置必须保留**（第 i 项对应第 i 个时段），所以非法项补空串而不是丢掉，
 * 否则后面的时间会整体前移，提醒就排到错误的时段上了。
 */
export function parseSlotTimes(raw: string): string[] {
  const out: string[] = [];
  if (raw === '' || raw === undefined || raw === null) {
    return out;
  }
  try {
    const parsed = JSON.parse(raw) as string[];
    if (!parsed || !Array.isArray(parsed)) {
      return out;
    }
    for (const item of parsed) {
      out.push(typeof item === 'string' ? item : '');
    }
  } catch (err) {
    return [];
  }
  return out;
}
