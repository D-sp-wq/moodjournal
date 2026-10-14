import { DateUtils } from '../common/utils/DateUtils';
import { ReportMood } from './Report';
import { StatsLog } from './Stats';

/**
 * 年度报告的纯函数模型。
 *
 * 与 Report.ets 的「等长周期」口径的区别（这是刻意的，不是重复造轮子）：
 *   - 周报 / 月度回顾是**滚动窗口**：以 endDate 结尾、往回数固定 7 / 30 天，
 *     好处是任意天都能立刻出报告，代价是窗口会把两个自然月甚至两个自然年切开，
 *     「2026 年 1 月 1 日写的那篇」既可能算进"去年最后 30 天"，也可能被漏掉。
 *   - 年度报告是**自然年**：严格按 1/1–12/31 分桶。
 *     跨年对比是这个功能的全部意义（"今年比去年多写了多少"），
 *     而滚动 365 天窗口既对齐不了「年」，也拿不到 12 个自然月的逐月分布。
 *
 * 关于天数表：自然年分桶只看 'yyyy-MM' 前缀，连续性只看 DateUtils.daysBetween，
 * 所以本文件里没有任何手写月份天数表，闰年 2 月是 28 还是 29 天完全由
 * DateUtils 的日历运算决定（跨闰年 2/29 → 3/1 也算连续）。
 *
 * 本文件不访问任何存储，输入输出都是纯数据，可直接单元测试。
 */
export interface AnnualMonth {
  /** 1-12 */
  month: number;
  /** 这个月有记录的天数（同一天多条只算一天） */
  recordedDays: number;
  /** 这个月的总字数 */
  chars: number;
}

export interface AnnualReport {
  year: number;
  /** 这一年有记录的天数 */
  recordedDays: number;
  /** 记录篇数 */
  entries: number;
  /** 总字数 */
  chars: number;
  /** 平均每篇字数 */
  avgChars: number;
  /** 出现最多的心情标签，无记录时空串 */
  topMood: string;
  /** 各心情出现次数，次数降序；次数相同时按名称升序（保证顺序稳定可测） */
  moodCounts: ReportMood[];
  /** 记录天数最多的月份（1-12）；无记录时 0；并列时取较小的月份 */
  busiestMonth: number;
  /** 12 个月逐月统计，按 1-12 升序，没有记录的月份也在，值为 0 */
  months: AnnualMonth[];
  /** 这一年最长的连续记录天数 */
  longestStreak: number;
  /** 这一年第一条记录的日期 'yyyy-MM-dd'，无记录时空串 */
  firstDate: string;
  /** 这一年最后一条记录的日期 'yyyy-MM-dd'，无记录时空串 */
  lastDate: string;
  /** 规则式一句话总结，不依赖任何模型 */
  summary: string;
}

/** 月份总数，固定 12：缺的月份也要出现在 months 里 */
const MONTHS_PER_YEAR: number = 12;
/** 空数据时的引导文案（也是 summary 的前缀，测试按「还没有记录」匹配） */
const EMPTY_GUIDE: string = '这一年还没有记录，写下第一篇吧';

/** 该记录是否属于目标自然年（只看 'yyyy-MM' 前缀，不做日期合法性校验） */
function inYear(item: StatsLog, prefix: string): boolean {
  // 坏日期（过短）直接丢掉，绝不抛错
  if (item.date.length < 10) {
    return false;
  }
  // 取 'yyyy-MM' 前缀做自然年比对。
  // 说明：这里用 substring 只是本文件的一致写法，slice 同样正确 ——
  // 曾怀疑 slice 前缀比较在 ArkTS 运行时不成立，已用 12 条诊断用例实测推翻
  // （'2026-01-01'.slice(0,4) === '2026' 为 true），不要把这条当成必须规避的坑。
  return item.date.substring(0, 5) === prefix;
}

/** 月份相同时，次数按名称升序；这是「顺序稳定」的保证 */
function compareMood(a: ReportMood, b: ReportMood): number {
  if (b.count !== a.count) {
    return b.count - a.count;
  }
  if (a.label === b.label) {
    return 0;
  }
  return a.label < b.label ? -1 : 1;
}

/** 把字数说成人话：12345 -> 1.2 万字 */
function charsLabel(chars: number): string {
  if (chars >= 10000) {
    return `${Math.round(chars / 1000) / 10} 万字`;
  }
  return `${chars} 字`;
}

/**
 * 汇总某一自然年的数据；month 口径为 1-12，只统计 hasEntry 为真的记录。
 *
 * hasEntry 的处理方式和 services/StatsService.ets 的 loadRecords 一致，
 * 并且**严格**照 models/DailyLog.ets 的 hasEntry(log) === true 判定：
 * 计划存根（hasEntry 为 false 或该字段缺失）不算记录，
 * 不进天数、篇数、字数、心情分布，也不进连续天数。
 */
export function buildAnnualReport(records: StatsLog[], year: number): AnnualReport {
  const prefix: string = `${year}-`;

  const months: AnnualMonth[] = [];
  for (let m: number = 1; m <= MONTHS_PER_YEAR; m++) {
    months.push({ month: m, recordedDays: 0, chars: 0 });
  }

  const moodCounter: Map<string, number> = new Map();
  const dayMonths: Map<string, number> = new Map();
  let chars: number = 0;
  let entries: number = 0;
  let firstDate: string = '';
  let lastDate: string = '';

  for (const item of records) {
    if (item.hasEntry !== true || !inYear(item, prefix)) {
      continue;
    }
    const monthIndex: number = Number(item.date.substring(5, 7)) - 1;
    if (monthIndex < 0 || monthIndex >= MONTHS_PER_YEAR) {
      continue;
    }

    entries += 1;
    chars += item.chars;
    months[monthIndex].chars += item.chars;
    dayMonths.set(item.date, monthIndex);

    // 心情为空的记录不参与「最常出现的心情」，但照样算天/篇/字数
    if (item.mood !== '') {
      const prev: number | undefined = moodCounter.get(item.mood);
      moodCounter.set(item.mood, (prev === undefined ? 0 : prev) + 1);
    }

    if (firstDate === '' || item.date < firstDate) {
      firstDate = item.date;
    }
    if (lastDate === '' || item.date > lastDate) {
      lastDate = item.date;
    }
  }

  // 同一天多条记录只算一天，所以去重后再摊到月份上
  const usedDates: string[] = [];
  for (const monthIndex of dayMonths.values()) {
    months[monthIndex].recordedDays += 1;
  }
  dayMonths.forEach((monthIndex: number, date: string) => {
    usedDates.push(date);
  });

  const moodCounts: ReportMood[] = [];
  moodCounter.forEach((count: number, label: string) => {
    moodCounts.push({ label: label, count: count });
  });
  moodCounts.sort(compareMood);

  let busiestMonth: number = 0;
  let busiestDays: number = 0;
  for (const item of months) {
    if (item.recordedDays > busiestDays) {
      busiestDays = item.recordedDays;
      busiestMonth = item.month;
    }
  }

  const recordedDays: number = dayMonths.size;
  const topMood: string = moodCounts.length > 0 ? moodCounts[0].label : '';

  const report: AnnualReport = {
    year: year,
    recordedDays: recordedDays,
    entries: entries,
    chars: chars,
    avgChars: entries > 0 ? Math.round(chars / entries) : 0,
    topMood: topMood,
    moodCounts: moodCounts,
    busiestMonth: busiestMonth,
    months: months,
    longestStreak: longestStreakOfDates(usedDates),
    firstDate: firstDate,
    lastDate: lastDate,
    summary: ''
  };
  report.summary = buildAnnualSummary(report);
  return report;
}

/** 规则式一句话总结 —— 不依赖任何模型，纯本地计算 */
function buildAnnualSummary(report: AnnualReport): string {
  if (report.recordedDays === 0) {
    return EMPTY_GUIDE;
  }
  const counts: string[] = [];
  counts.push(`记录了 ${report.recordedDays} 天`);
  counts.push(`${report.entries} 篇`);
  counts.push(charsLabel(report.chars));

  // 前三个数字用顿号连成一组，后面两个补充信息用逗号接上，
  // 例：这一年记录了 248 天、312 篇、12.4 万字，最常出现的心情是「开心」，最长连续 31 天
  const parts: string[] = [`这一年${counts.join('、')}`];
  if (report.topMood !== '') {
    parts.push(`最常出现的心情是「${report.topMood}」`);
  }
  if (report.longestStreak > 1) {
    parts.push(`最长连续 ${report.longestStreak} 天`);
  }
  return parts.join('，');
}

/**
 * 可选年份列表：从最早记录年到今年，降序；没有任何记录时只有今年。
 * currentYear 由调用方传（不要在模型里读系统时间，否则没法单测）。
 */
export function availableYears(records: StatsLog[], currentYear: number): number[] {
  let earliest: number = currentYear;
  let found: boolean = false;
  for (const item of records) {
    if (item.hasEntry !== true || item.date.length < 10) {
      continue;
    }
    // 取年份数字（substring 只是本文件的一致写法，见 inYear 的说明）
    const year: number = Number(item.date.substring(0, 4));
    if (Number.isNaN(year)) {
      continue;
    }
    if (!found || year < earliest) {
      earliest = year;
      found = true;
    }
  }
  const out: number[] = [];
  for (let y: number = currentYear; y >= earliest; y--) {
    out.push(y);
  }
  return out;
}

/**
 * 最长连续记录天数（按日期升序、去重后计算「日期连续」）。
 *
 * 与 buildAnnualReport 同一口径：计划存根（hasEntry 不是 true）不参与。
 *
 * 1/31 与 2/1 算连续：连续性用 DateUtils.daysBetween 判定，
 * 不手写天数表、也不受闰年 2 月天数影响。
 */
export function longestStreakOf(records: StatsLog[]): number {
  const dates: string[] = [];
  for (const item of records) {
    if (item.hasEntry !== true) {
      continue;
    }
    dates.push(item.date);
  }
  return longestStreakOfDates(dates);
}

/** longestStreakOf 的日期串版本：buildAnnualReport 手上已经是去重后的日期 */
function longestStreakOfDates(raw: string[]): number {
  const seen: Set<string> = new Set();
  const dates: string[] = [];
  for (const date of raw) {
    if (date.length < 10 || seen.has(date)) {
      continue;
    }
    seen.add(date);
    dates.push(date);
  }
  if (dates.length === 0) {
    return 0;
  }
  dates.sort((a: string, b: string): number => {
    if (a === b) {
      return 0;
    }
    return a < b ? -1 : 1;
  });

  let best: number = 1;
  let run: number = 1;
  for (let i: number = 1; i < dates.length; i++) {
    if (DateUtils.daysBetween(dates[i - 1], dates[i]) === 1) {
      run += 1;
    } else {
      run = 1;
    }
    if (run > best) {
      best = run;
    }
  }
  return best;
}
