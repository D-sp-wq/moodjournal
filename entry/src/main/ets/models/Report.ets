import { DateUtils } from '../common/utils/DateUtils';
import { StatsLog } from './Stats';

/**
 * 周报 / 月度回顾的纯函数模型。
 *
 * 为什么做这个：应用商店审核指南 3.5 要求应用「具备实用价值」**且具备创意**。
 * 系统备忘录、系统日历都不可能生成「这一周记录了 5 天、最常出现的心情是开心、
 * 比上一周多了 2 天」这种东西——这是应用"创意"最直接的落点。
 *
 * 本文件不访问任何存储，输入输出都是纯数据，可直接单元测试。
 */
export interface ReportMood {
  label: string;
  count: number;
}

export interface RangeReport {
  /** 区间起止，均为 'yyyy-MM-dd'，含首含尾 */
  from: string;
  to: string;
  /** 这段区间一共多少天 */
  days: number;
  /** 有记录的天数 */
  recordedDays: number;
  /** 记录篇数（同一天多条时大于天数，当前一天一条，二者相等） */
  entries: number;
  /** 总字数 */
  chars: number;
  /** 平均每次记录的字数 */
  avgChars: number;
  /** 心情出现次数，按次数降序 */
  moods: ReportMood[];
  /** 出现最多的心情标签，没记录时为空串 */
  topMood: string;
  /** 写得最多的一天，没记录时为空串 */
  busiestDate: string;
  /** 与「上一个等长区间」相比的记录天数变化，正数表示更多 */
  daysDelta: number;
  /** 一句话总结，由规则生成 */
  summary: string;
}

/** 把区间内的记录按日期索引，方便查上一个区间 */
function indexByDate(logs: StatsLog[]): Map<string, StatsLog> {
  const map: Map<string, StatsLog> = new Map();
  for (const item of logs) {
    map.set(item.date, item);
  }
  return map;
}

/**
 * 统计以 endDate 结尾、长度为 days 的区间（含 endDate）。
 * 传入的 logs 可以包含区间外的数据（本函数会自己过滤）。
 */
export function buildRangeReport(logs: StatsLog[], endDate: string, days: number): RangeReport {
  const safeDays: number = days > 0 ? days : 7;
  const from: string = DateUtils.addDays(endDate, -(safeDays - 1));
  const prevFrom: string = DateUtils.addDays(from, -safeDays);
  const prevTo: string = DateUtils.addDays(endDate, -safeDays);

  const within: StatsLog[] = [];
  const prevDates: Set<string> = new Set();
  for (const item of logs) {
    if (item.date >= from && item.date <= endDate) {
      within.push(item);
    }
    if (item.date >= prevFrom && item.date <= prevTo) {
      prevDates.add(item.date);
    }
  }

  const dates: Set<string> = new Set();
  const moodCounter: Map<string, number> = new Map();
  const charsByDate: Map<string, number> = new Map();
  let chars: number = 0;

  for (const item of within) {
    dates.add(item.date);
    chars += item.chars;
    const prevMood: number | undefined = moodCounter.get(item.mood);
    moodCounter.set(item.mood, (prevMood === undefined ? 0 : prevMood) + 1);
    const prevChars: number | undefined = charsByDate.get(item.date);
    charsByDate.set(item.date, (prevChars === undefined ? 0 : prevChars) + item.chars);
  }

  const moods: ReportMood[] = [];
  moodCounter.forEach((count: number, label: string) => {
    moods.push({ label: label, count: count });
  });
  moods.sort((a: ReportMood, b: ReportMood): number => b.count - a.count);

  let busiestDate: string = '';
  let busiestChars: number = -1;
  charsByDate.forEach((value: number, date: string) => {
    if (value > busiestChars) {
      busiestChars = value;
      busiestDate = date;
    }
  });

  const recordedDays: number = dates.size;
  const topMood: string = moods.length > 0 ? moods[0].label : '';
  const daysDelta: number = recordedDays - prevDates.size;

  const report: RangeReport = {
    from: from,
    to: endDate,
    days: safeDays,
    recordedDays: recordedDays,
    entries: within.length,
    chars: chars,
    avgChars: within.length > 0 ? Math.round(chars / within.length) : 0,
    moods: moods,
    topMood: topMood,
    busiestDate: busiestDate,
    daysDelta: daysDelta,
    summary: ''
  };
  report.summary = buildSummary(report, safeDays);
  return report;
}

/** 规则式一句话总结 —— 不依赖任何模型，纯本地计算 */
function buildSummary(report: RangeReport, days: number): string {
  const unit: string = days <= 7 ? '这周' : '这 30 天';
  if (report.recordedDays === 0) {
    return `${unit}还没有记录，写下第一篇吧`;
  }
  const parts: string[] = [];
  parts.push(`${unit}记录了 ${report.recordedDays} 天`);
  if (report.topMood !== '') {
    parts.push(`最常出现的心情是「${report.topMood}」`);
  }
  if (report.avgChars > 0) {
    parts.push(`平均每次写 ${report.avgChars} 字`);
  }
  let line: string = parts.join('，');
  if (report.daysDelta > 0) {
    line += `；比上一个同样长的周期多记了 ${report.daysDelta} 天`;
  } else if (report.daysDelta < 0) {
    line += `；比上一个同样长的周期少记了 ${-report.daysDelta} 天`;
  } else {
    line += '；与上一个同样长的周期持平';
  }
  return line;
}

/** 近 7 天周报 */
export function buildWeeklyReport(logs: StatsLog[], todayStr: string): RangeReport {
  return buildRangeReport(logs, todayStr, 7);
}

/** 近 30 天月度回顾 */
export function buildMonthlyReport(logs: StatsLog[], todayStr: string): RangeReport {
  return buildRangeReport(logs, todayStr, 30);
}

/** 每格代表一天的心情色条数据（供回顾页画条带） */
export interface ReportDay {
  date: string;
  /** 有记录时是该天的心情标签，没记录为空串 */
  mood: string;
  /** 该天字数 */
  chars: number;
}

/** 把区间铺成「一天一格」的序列，按日期升序 */
export function buildReportDays(logs: StatsLog[], endDate: string, days: number): ReportDay[] {
  const safeDays: number = days > 0 ? days : 7;
  const byDate: Map<string, StatsLog> = indexByDate(logs);
  const out: ReportDay[] = [];
  for (let i: number = safeDays - 1; i >= 0; i--) {
    const date: string = DateUtils.addDays(endDate, -i);
    const hit: StatsLog | undefined = byDate.get(date);
    out.push({
      date: date,
      mood: hit === undefined ? '' : hit.mood,
      chars: hit === undefined ? 0 : hit.chars
    });
  }
  return out;
}
