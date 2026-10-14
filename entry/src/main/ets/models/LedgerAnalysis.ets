import { DateUtils } from '../common/utils/DateUtils';
import { LedgerRecord, LedgerType, monthOf } from './Ledger';

/**
 * 消费智能分析（本机部分 + 给 AI 的载荷构造）。
 *
 * 设计要点：
 * 1. 本机先把账目算成结构化统计，**再把聚合结果**交给 AI；原始明细、备注、日记、心情一律不出本机。
 * 2. 本文件全部是纯函数，不碰存储、不碰网络、不碰 UI，可直接单元测试。
 * 3. 数据不足时**不编结论**：样本不够的分类不进异常检测，笔数不够不报小额高频。
 */

/** 单笔不超过这个金额算「小额」 */
export const SMALL_TICKET_AMOUNT: number = 30;
/** 小额支出至少这么多笔才值得说 */
export const SMALL_TICKET_MIN_COUNT: number = 5;
/** 异常检测：该分类本月至少这么多笔才判断 */
export const ANOMALY_MIN_SAMPLES: number = 3;
/** 异常检测：超过均值这个倍数才算异常（恰好等于不算） */
export const ANOMALY_FACTOR: number = 2;
/** 分类涨跌、异常、建议最多各输出几条 */
export const MAX_CATEGORY_CHANGES: number = 3;
export const MAX_ANOMALIES: number = 3;

export interface ForecastPart {
  /** 本月已花 */
  spent: number;
  /** 本月已经过去几天（含今天） */
  elapsedDays: number;
  daysInMonth: number;
  /** 单日均支出 */
  dailyAverage: number;
  /** 按当前速度预计月底会花多少 */
  projectedTotal: number;
  /** 月度预算，0 表示未设置 */
  budget: number;
  /** 预计会超出预算多少，不会超为 0 */
  overBy: number;
}

export interface CategoryChange {
  name: string;
  current: number;
  previous: number;
  /** current - previous，正数表示这个月多花了 */
  delta: number;
}

export interface Anomaly {
  date: string;
  category: string;
  amount: number;
  /** 该分类本月除这笔以外的均值 */
  usual: number;
  /** 是均值的多少倍 */
  times: number;
}

export interface ConsumptionAnalysis {
  month: string;
  forecast: ForecastPart;
  currentTotal: number;
  previousTotal: number;
  /** currentTotal - previousTotal */
  deltaAmount: number;
  /** 环比百分比；上月为 0 时返回 -1（页面不显示百分比） */
  deltaPercent: number;
  /** 分类涨跌，按变化绝对值降序，最多 3 条 */
  categoryChanges: CategoryChange[];
  /** 本月金额最大的一笔，没有则为 null */
  maxSingle: LedgerRecord | null;
  smallTicketCount: number;
  smallTicketAmount: number;
  /** 小额合计占本月支出的百分比，0~100 */
  smallTicketPercent: number;
  /** 本月已过天数里没有支出的天数 */
  noSpendDays: number;
  /** 异常支出，最多 3 条 */
  anomalies: Anomaly[];
}

/** 取 'yyyy-MM' 的年份 */
export function yearOf(month: string): number {
  return Number(month.slice(0, 4));
}

/** 上一个自然月 */
export function previousMonthOf(month: string): string {
  const y: number = yearOf(month);
  const m: number = Number(month.slice(5, 7));
  if (m === 1) {
    return `${y - 1}-12`;
  }
  return `${y}-${m < 11 ? '0' : ''}${m - 1}`;
}

/**
 * 本月的「已过天数」（含今天）。
 * 分析的是当前月就用今天是几号；分析历史月份或未来月份则整月都算已过，
 * 这样切换月份时预测值不会失真。
 */
export function elapsedDaysOf(month: string, todayStr: string, daysInMonth: number): number {
  if (monthOf(todayStr) !== month) {
    return daysInMonth;
  }
  const day: number = Number(todayStr.slice(8, 10));
  if (day < 1) {
    return 1;
  }
  return day > daysInMonth ? daysInMonth : day;
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

/** 主入口：本机消费分析 */
export function analyzeConsumption(
  records: LedgerRecord[],
  month: string,
  budget: number,
  todayStr: string
): ConsumptionAnalysis {
  const year: number = yearOf(month);
  const monthNum: number = Number(month.slice(5, 7));
  const daysInMonth: number = DateUtils.daysInMonth(year, monthNum);
  const elapsed: number = elapsedDaysOf(month, todayStr, daysInMonth);
  const previous: string = previousMonthOf(month);
  const safeBudget: number = budget > 0 ? budget : 0;

  // 本月支出（按分类、按天）
  let currentTotal: number = 0;
  let previousTotal: number = 0;
  const currentByCategory: Map<string, number> = new Map();
  const previousByCategory: Map<string, number> = new Map();
  const currentCategoryRecords: Map<string, LedgerRecord[]> = new Map();
  const spendByDay: Map<number, number> = new Map();
  let maxSingle: LedgerRecord | null = null;

  for (const r of records) {
    if (r.type !== LedgerType.EXPENSE) {
      continue;
    }
    const head: string = monthOf(r.date);
    if (head === month) {
      currentTotal += r.amount;
      currentByCategory.set(r.category, (currentByCategory.get(r.category) ?? 0) + r.amount);
      const list: LedgerRecord[] | undefined = currentCategoryRecords.get(r.category);
      if (list === undefined) {
        currentCategoryRecords.set(r.category, [r]);
      } else {
        list.push(r);
      }
      const day: number = Number(r.date.slice(8, 10));
      spendByDay.set(day, (spendByDay.get(day) ?? 0) + r.amount);
      if (r.amount > 0 && (maxSingle === null || r.amount > maxSingle.amount)) {
        maxSingle = r;
      }
    } else if (head === previous) {
      previousTotal += r.amount;
      previousByCategory.set(r.category, (previousByCategory.get(r.category) ?? 0) + r.amount);
    }
  }
  currentTotal = round2(currentTotal);
  previousTotal = round2(previousTotal);

  // 预算预测
  const dailyAverage: number = elapsed > 0 ? round2(currentTotal / elapsed) : 0;
  const projectedTotal: number = round2(dailyAverage * daysInMonth);
  const overBy: number = safeBudget > 0 && projectedTotal > safeBudget
    ? round2(projectedTotal - safeBudget)
    : 0;
  const forecast: ForecastPart = {
    spent: currentTotal,
    elapsedDays: elapsed,
    daysInMonth: daysInMonth,
    dailyAverage: dailyAverage,
    projectedTotal: projectedTotal,
    budget: safeBudget,
    overBy: overBy
  };

  // 环比
  const deltaAmount: number = round2(currentTotal - previousTotal);
  const deltaPercent: number = previousTotal > 0
    ? Math.round(deltaAmount * 100 / previousTotal)
    : -1;

  // 分类涨跌
  const names: Set<string> = new Set();
  currentByCategory.forEach((amount: number, name: string) => {
    names.add(name);
  });
  previousByCategory.forEach((amount: number, name: string) => {
    names.add(name);
  });
  const changes: CategoryChange[] = [];
  names.forEach((name: string) => {
    const current: number = round2(currentByCategory.get(name) ?? 0);
    const prev: number = round2(previousByCategory.get(name) ?? 0);
    changes.push({ name: name, current: current, previous: prev, delta: round2(current - prev) });
  });
  changes.sort((a: CategoryChange, b: CategoryChange): number =>
    Math.abs(b.delta) - Math.abs(a.delta));
  const categoryChanges: CategoryChange[] = changes.slice(0, MAX_CATEGORY_CHANGES);

  // 小额高频
  let smallCount: number = 0;
  let smallAmount: number = 0;
  for (const r of records) {
    if (r.type !== LedgerType.EXPENSE || monthOf(r.date) !== month || r.amount <= 0) {
      continue;
    }
    if (r.amount <= SMALL_TICKET_AMOUNT) {
      smallCount += 1;
      smallAmount += r.amount;
    }
  }
  smallAmount = round2(smallAmount);

  // 无消费天数
  let noSpendDays: number = 0;
  for (let d: number = 1; d <= elapsed; d++) {
    const spent: number | undefined = spendByDay.get(d);
    if (spent === undefined || spent <= 0) {
      noSpendDays += 1;
    }
  }

  // 异常支出：同分类本月样本 >= 3，且单笔 > 该分类除它以外均值 × 2
  const anomalies: Anomaly[] = [];
  currentCategoryRecords.forEach((list: LedgerRecord[], category: string) => {
    if (list.length < ANOMALY_MIN_SAMPLES) {
      return;
    }
    let total: number = 0;
    for (const item of list) {
      total += item.amount;
    }
    for (const item of list) {
      if (item.amount <= 0) {
        continue;
      }
      const others: number = list.length - 1;
      if (others <= 0) {
        continue;
      }
      const usual: number = round2((total - item.amount) / others);
      if (usual > 0 && item.amount > usual * ANOMALY_FACTOR) {
        anomalies.push({
          date: item.date,
          category: category,
          amount: item.amount,
          usual: usual,
          times: Math.round(item.amount / usual * 10) / 10
        });
      }
    }
  });
  anomalies.sort((a: Anomaly, b: Anomaly): number => b.times - a.times);

  return {
    month: month,
    forecast: forecast,
    currentTotal: currentTotal,
    previousTotal: previousTotal,
    deltaAmount: deltaAmount,
    deltaPercent: deltaPercent,
    categoryChanges: categoryChanges,
    maxSingle: maxSingle,
    smallTicketCount: smallCount,
    smallTicketAmount: smallAmount,
    smallTicketPercent: currentTotal > 0 ? Math.round(smallAmount * 100 / currentTotal) : 0,
    noSpendDays: noSpendDays,
    anomalies: anomalies.slice(0, MAX_ANOMALIES)
  };
}

/**
 * 构造发给 AI 的载荷 —— **这是隐私边界所在，只允许放聚合统计**。
 *
 * 明确不包含：备注文本、日记正文、心情、照片、习惯、任务、重要日子、单笔之外的任何明细。
 * 单笔只以「分类 + 日期 + 金额」的形式出现在异常条目里（异常分析必须要有具体条目才说得清）。
 */
export function buildAnalysisPayload(analysis: ConsumptionAnalysis): string {
  const parts: string[] = [];
  parts.push(`{"month":"${analysis.month}"`);
  parts.push(`,"支出合计":${analysis.currentTotal}`);
  parts.push(`,"上月支出合计":${analysis.previousTotal}`);
  parts.push(`,"已过天数":${analysis.forecast.elapsedDays}`);
  parts.push(`,"本月天数":${analysis.forecast.daysInMonth}`);
  parts.push(`,"单日均支出":${analysis.forecast.dailyAverage}`);
  parts.push(`,"预计月底支出":${analysis.forecast.projectedTotal}`);
  parts.push(`,"月度预算":${analysis.forecast.budget}`);
  parts.push(`,"预计超出预算":${analysis.forecast.overBy}`);
  parts.push(`,"无消费天数":${analysis.noSpendDays}`);
  parts.push(`,"小额笔数":${analysis.smallTicketCount}`);
  parts.push(`,"小额合计":${analysis.smallTicketAmount}`);

  parts.push(',"分类涨跌":[');
  for (let i: number = 0; i < analysis.categoryChanges.length; i++) {
    const c: CategoryChange = analysis.categoryChanges[i];
    if (i > 0) {
      parts.push(',');
    }
    parts.push(`{"分类":"${c.name}","本月":${c.current},"上月":${c.previous}}`);
  }
  parts.push(']');

  parts.push(',"异常支出":[');
  for (let i: number = 0; i < analysis.anomalies.length; i++) {
    const a: Anomaly = analysis.anomalies[i];
    if (i > 0) {
      parts.push(',');
    }
    parts.push(`{"日期":"${a.date}","分类":"${a.category}","金额":${a.amount},"平时":${a.usual}}`);
  }
  parts.push(']}');

  return parts.join('');
}
