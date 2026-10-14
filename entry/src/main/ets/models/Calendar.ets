import { DateUtils } from '../common/utils/DateUtils';
import { DailyLog, countChars, hasEntry, moodLabel } from './DailyLog';

/**
 * 月度记录日历的纯函数模型。
 *
 * 为什么做这个：系统日历只会告诉你"今天几号"，绝不会把每一天的心情染成颜色，
 * 更不会告诉你"这个月比上个月多记了 3 天"。应用商店审核指南 3.5 要求应用
 * 「具备实用价值」**且具备创意**，这一块正好是系统自带日历做不到的。
 *
 * 本文件不访问存储、不碰 UI，输入输出都是纯数据，可直接单元测试。
 */

/** 某一天的日历标记 */
export interface CalendarMark {
  /** 'yyyy-MM-dd' */
  date: string;
  /** 当天心情标签；没有记录时为空串 */
  mood: string;
  /** 当天是否有照片 */
  hasPhoto: boolean;
  /** 这一天有没有"要做的事"的安排（可能存在只写了计划的存根） */
  hasPlan: boolean;
  /** 过去且没有记录 —— 按应用的"记录封存"规则，不能补记 */
  sealed: boolean;
}

/** 某个月的汇总 */
export interface MonthSummary {
  year: number;
  month: number;
  /** 本月有记录的天数 */
  recordedDays: number;
  /** 本月记录篇数 */
  entries: number;
  /** 本月正文总字数 */
  chars: number;
  /** 本月出现最多的心情标签，没记录时为空串 */
  topMood: string;
  /** 与「上一个自然月」相比的记录天数差，正数表示更多 */
  daysDelta: number;
  /** 规则式一句话总结 */
  summary: string;
}

export const EMPTY_MONTH_SUMMARY: MonthSummary = {
  year: 0,
  month: 0,
  recordedDays: 0,
  entries: 0,
  chars: 0,
  topMood: '',
  daysDelta: 0,
  summary: ''
};

/** 'yyyy-MM' 前缀 */
function monthPrefix(year: number, month: number): string {
  return `${year}-${month < 10 ? '0' : ''}${month}`;
}

/**
 * 生成某个月每一天的标记，按日期升序。
 * 返回长度 = 当月天数（平年 2 月 28、闰年 29），调用方可以按下标直接铺格子。
 */
export function buildMonthMarks(logs: DailyLog[], year: number, month: number, today: string): CalendarMark[] {
  const byDate: Map<string, DailyLog> = new Map();
  for (const log of logs) {
    byDate.set(log.date, log);
  }

  const total: number = DateUtils.daysInMonth(year, month);
  const marks: CalendarMark[] = [];
  for (let day: number = 1; day <= total; day++) {
    const date: string = DateUtils.buildDateStr(year, month, day);
    const hit: DailyLog | undefined = byDate.get(date);
    if (hit === undefined) {
      marks.push({
        date: date,
        mood: '',
        hasPhoto: false,
        hasPlan: false,
        sealed: DateUtils.isSealed(date, today)
      });
    } else {
      // 只有计划的存根不算"记录"，因此不给它心情色，只标 hasPlan
      const recorded: boolean = hasEntry(hit);
      marks.push({
        date: date,
        mood: recorded ? moodLabel(hit.mood, hit.customMood) : '',
        hasPhoto: recorded && hit.photoUris.length > 0,
        hasPlan: hit.plan.trim() !== '',
        sealed: false
      });
    }
  }
  return marks;
}

/**
 * 月度小结。
 *
 * 注意口径：这里对比的是**上一个自然月**（1 月的上个月是去年 12 月），
 * 与 models/Report.ets 里"上一个等长区间"的口径不同，两者不要混用。
 */
export function summarizeMonth(logs: DailyLog[], year: number, month: number, today: string): MonthSummary {
  const current: string = monthPrefix(year, month);
  const prevYear: number = month === 1 ? year - 1 : year;
  const prevMonth: number = month === 1 ? 12 : month - 1;
  const previous: string = monthPrefix(prevYear, prevMonth);

  const dates: Set<string> = new Set();
  const prevDates: Set<string> = new Set();
  const counter: Map<string, number> = new Map();
  let entries: number = 0;
  let chars: number = 0;

  for (const log of logs) {
    const head: string = log.date.slice(0, 7);
    if (head === current) {
      dates.add(log.date);
      entries += 1;
      chars += countChars(log);
      const label: string = moodLabel(log.mood, log.customMood);
      const seen: number | undefined = counter.get(label);
      counter.set(label, (seen === undefined ? 0 : seen) + 1);
    } else if (head === previous) {
      prevDates.add(log.date);
    }
  }

  let topMood: string = '';
  let topCount: number = 0;
  counter.forEach((count: number, label: string) => {
    if (count > topCount) {
      topCount = count;
      topMood = label;
    }
  });

  const recordedDays: number = dates.size;
  const daysDelta: number = recordedDays - prevDates.size;

  const summary: MonthSummary = {
    year: year,
    month: month,
    recordedDays: recordedDays,
    entries: entries,
    chars: chars,
    topMood: topMood,
    daysDelta: daysDelta,
    summary: ''
  };
  summary.summary = buildMonthSummary(summary);
  return summary;
}

/** 规则式一句话总结 —— 纯本地计算，不依赖任何模型 */
function buildMonthSummary(item: MonthSummary): string {
  if (item.recordedDays === 0) {
    return '这个月还没有记录，写下第一篇吧';
  }
  let line: string = `这个月记录了 ${item.recordedDays} 天，共 ${item.entries} 篇、${item.chars} 字`;
  if (item.topMood !== '') {
    line += `，最常出现的心情是「${item.topMood}」`;
  }
  if (item.daysDelta > 0) {
    line += `；比上个月多记了 ${item.daysDelta} 天`;
  } else if (item.daysDelta < 0) {
    line += `；比上个月少记了 ${-item.daysDelta} 天`;
  } else {
    line += '；与上个月持平';
  }
  return line;
}

/** 首页「接下来几天」用的条目 */
export interface UpcomingPlan {
  /** 这件事要在哪一天做 */
  date: string;
  /** 要做的事 */
  plan: string;
  /** 距离今天几天：1 = 明天 */
  daysAhead: number;
}

/**
 * 取出接下来 days 天里安排了事情的日子，按日期升序。
 *
 * 注意这里有一次"顺延"：按本应用的存储约定，"日期 D 要做的事"写在 **D-1** 的 plan 里，
 * 所以遍历 [今天, 今天+days-1] 的 plan，落到 [明天, 今天+days]。
 */
export function buildUpcomingPlans(logs: DailyLog[], today: string, days: number): UpcomingPlan[] {
  const wanted: number = days > 0 ? days : 7;
  const byDate: Map<string, DailyLog> = new Map();
  for (const log of logs) {
    byDate.set(log.date, log);
  }

  const out: UpcomingPlan[] = [];
  for (let i: number = 0; i < wanted; i++) {
    const sourceDate: string = DateUtils.addDays(today, i);
    const hit: DailyLog | undefined = byDate.get(sourceDate);
    if (hit === undefined) {
      continue;
    }
    const text: string = hit.plan.trim();
    if (text === '') {
      continue;
    }
    out.push({
      date: DateUtils.addDays(sourceDate, 1),
      plan: text,
      daysAhead: i + 1
    });
  }
  return out;
}

/** 「明天 / 后天 / N 天后」 */
export function daysAheadLabel(daysAhead: number): string {
  if (daysAhead <= 0) {
    return '今天';
  }
  if (daysAhead === 1) {
    return '明天';
  }
  if (daysAhead === 2) {
    return '后天';
  }
  return `${daysAhead} 天后`;
}
