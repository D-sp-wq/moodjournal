import { DateUtils } from '../common/utils/DateUtils';
import { moodScoreByLabel } from './DailyLog';

/** 统计用的最小记录：与持久化模型解耦，便于单元测试 */
export interface StatsLog {
  date: string;
  mood: string;
  /** 该条记录的日记 + 计划字数 */
  chars: number;
  /**
   * 这一天是不是"真的记录过"，对齐 DailyLog.hasEntry（见 models/DailyLog.ets）。
   *
   * 可选，且**目前只有年度报告读它**：周报 / 统计 / 趋势走 StatsService.loadRecords()，
   * 那里在转成 StatsLog 之前已经用 hasEntry 过滤过，所以不填不影响既有功能。
   * 年度报告按自然年重新分桶，需要一个能表达"这是计划存根"的字段。
   * 年度报告按 hasEntry === true 严格判定：false 或缺失都算计划存根，不计入。
   */
  hasEntry?: boolean;
}

export interface MoodCount {
  mood: string;
  count: number;
  /** 占比百分比 0-100 */
  percent: number;
}

export interface MonthCount {
  label: string;
  count: number;
}

export interface StatsResult {
  /** 记录总篇数 */
  total: number;
  /** 有记录的天数（按日期去重） */
  activeDays: number;
  /** 已使用天数（自开始记录日算起） */
  recordDays: number;
  /** 记录覆盖率百分比 0-100 */
  ratePercent: number;
  /** 当前连续记录天数 */
  currentStreak: number;
  /** 历史最长连续记录天数 */
  bestStreak: number;
  /** 今天是否已记录 */
  loggedToday: boolean;
  /** 日记与计划的总字数 */
  totalChars: number;
  /** 心情分布，按次数降序 */
  moods: MoodCount[];
  /** 近 6 个月记录数，按时间升序 */
  months: MonthCount[];
  /** 重要日子数量 */
  importantCount: number;
  /** 图片数量 */
  photoCount: number;
}

const RECENT_MONTHS: number = 6;

/** 近 count 个月的月份键（'yyyy-MM'），按时间升序 */
function recentMonthKeys(todayStr: string, count: number): string[] {
  const y: number = Number(todayStr.slice(0, 4));
  const m: number = Number(todayStr.slice(5, 7));
  const keys: string[] = [];
  for (let i: number = count - 1; i >= 0; i--) {
    let mm: number = m - i;
    let yy: number = y;
    while (mm <= 0) {
      mm += 12;
      yy -= 1;
    }
    keys.push(`${yy}-${mm < 10 ? '0' : ''}${mm}`);
  }
  return keys;
}

function bump(counter: Map<string, number>, key: string, delta: number): void {
  const prev: number | undefined = counter.get(key);
  counter.set(key, (prev === undefined ? 0 : prev) + delta);
}

function read(counter: Map<string, number>, key: string): number {
  const value: number | undefined = counter.get(key);
  return value === undefined ? 0 : value;
}

/**
 * 汇总每日记录 / 重要日子 / 图片数据的纯函数。
 * 不访问任何存储，数据加载由 StatsService 负责，因此可直接单元测试。
 */
export function computeStats(
  logs: StatsLog[],
  startDate: string,
  todayStr: string,
  importantCount: number,
  photoCount: number
): StatsResult {
  const dates: string[] = [];
  const moodCounter: Map<string, number> = new Map();
  const monthCounter: Map<string, number> = new Map();
  let totalChars: number = 0;

  for (const item of logs) {
    dates.push(item.date);
    bump(moodCounter, item.mood !== '' ? item.mood : '未记录', 1);
    bump(monthCounter, item.date.slice(0, 7), 1);
    totalChars += item.chars;
  }

  const activeDays: number = new Set(dates).size;
  const total: number = logs.length;

  let recordDays: number = DateUtils.daysBetween(startDate, todayStr) + 1;
  if (recordDays < 1) {
    recordDays = 1;
  }
  const ratePercent: number = Math.round(activeDays * 100 / recordDays);

  const moods: MoodCount[] = [];
  moodCounter.forEach((count: number, mood: string) => {
    moods.push({
      mood: mood,
      count: count,
      percent: total > 0 ? Math.round(count * 100 / total) : 0
    });
  });
  moods.sort((a: MoodCount, b: MoodCount): number => b.count - a.count);

  const months: MonthCount[] = [];
  for (const key of recentMonthKeys(todayStr, RECENT_MONTHS)) {
    months.push({ label: `${Number(key.slice(5, 7))}月`, count: read(monthCounter, key) });
  }

  return {
    total: total,
    activeDays: activeDays,
    recordDays: recordDays,
    ratePercent: ratePercent,
    currentStreak: DateUtils.computeStreak(dates, todayStr),
    bestStreak: DateUtils.computeBestStreak(dates),
    loggedToday: DateUtils.hasCheckedToday(dates, todayStr),
    totalChars: totalChars,
    moods: moods,
    months: months,
    importantCount: importantCount,
    photoCount: photoCount
  };
}

export interface TrendPoint {
  date: string;
  /** 情绪值 1~5；0 表示当天没有记录 */
  score: number;
  /** 心情标签，没记录时为空 */
  label: string;
}

export interface MoodTrend {
  /** 按日期升序，长度等于 days */
  points: TrendPoint[];
  /** 区间内有记录的天数 */
  recordedDays: number;
  /** 出现次数最多的心情标签，没有记录时为空 */
  topMood: string;
  /** 区间内平均每次记录的字数 */
  avgChars: number;
}

/**
 * 近 days 天（含今天）的心情趋势，按日期升序。
 * 情绪值用 moodScoreByLabel 的**固定映射**，只为把离散心情画成折线。
 */
export function computeMoodTrend(logs: StatsLog[], todayStr: string, days: number): MoodTrend {
  const byDate: Map<string, StatsLog> = new Map();
  for (const item of logs) {
    byDate.set(item.date, item);
  }

  const points: TrendPoint[] = [];
  const moodCounter: Map<string, number> = new Map();
  let recordedDays: number = 0;
  let totalChars: number = 0;

  for (let i: number = days - 1; i >= 0; i--) {
    const date: string = DateUtils.addDays(todayStr, -i);
    const log: StatsLog | undefined = byDate.get(date);
    if (log === undefined) {
      points.push({ date: date, score: 0, label: '' });
      continue;
    }
    recordedDays += 1;
    totalChars += log.chars;
    bump(moodCounter, log.mood !== '' ? log.mood : '未记录', 1);
    points.push({ date: date, score: moodScoreByLabel(log.mood), label: log.mood });
  }

  let bestCount: number = 0;
  let topMood: string = '';
  moodCounter.forEach((count: number, mood: string) => {
    if (count > bestCount) {
      bestCount = count;
      topMood = mood;
    }
  });

  return {
    points: points,
    recordedDays: recordedDays,
    topMood: topMood,
    avgChars: recordedDays > 0 ? Math.round(totalChars / recordedDays) : 0
  };
}
