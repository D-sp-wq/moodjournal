/**
 * 账本数据模型（与每日心情记录**完全独立**）
 *
 * 记一笔：日期 + 支出/收入 + 金额 + 分类 + 备注。
 * 汇总按自然月统计支出、收入、结余与分类占比，并对比月度预算。
 *
 * 账本的创意点：支出可以标记"感受"（值得/一般/后悔），
 * 从而算出月度「值得指数」，并与日记的心情数据交叉出花费洞察 —— 这是纯记账应用做不到的。
 */
import { DateUtils } from '../common/utils/DateUtils';

export enum LedgerType {
  EXPENSE = 0,
  INCOME = 1
}

/**
 * 这笔支出给你的"感受"。
 *
 * 这是账本最有创意的地方：主流记账应用只知道你花了多少，
 * 而这个应用同时装着你的心情日记，所以能回答"这笔钱花得值不值"。
 * 未标记是最常见的状态，不参与值得指数计算。
 */
export enum LedgerFeeling {
  NONE = 0,
  WORTH = 1,
  NEUTRAL = 2,
  REGRET = 3
}

/** 感受的可选项（用于 UI 渲染，顺序即展示顺序） */
export interface FeelingOption {
  value: LedgerFeeling;
  label: string;
}

export const FEELING_OPTIONS: FeelingOption[] = [
  { value: LedgerFeeling.WORTH, label: '值得' },
  { value: LedgerFeeling.NEUTRAL, label: '一般' },
  { value: LedgerFeeling.REGRET, label: '后悔' }
];

export function feelingLabel(value: LedgerFeeling): string {
  if (value === LedgerFeeling.WORTH) {
    return '值得';
  }
  if (value === LedgerFeeling.NEUTRAL) {
    return '一般';
  }
  if (value === LedgerFeeling.REGRET) {
    return '后悔';
  }
  return '未标记';
}

export interface LedgerRecord {
  id: string;
  /** 'yyyy-MM-dd' */
  date: string;
  type: LedgerType;
  /** 金额，正数，单位元 */
  amount: number;
  category: string;
  note: string;
  /** 只对支出有意义；收入恒为 NONE */
  feeling: LedgerFeeling;
  createdAt: number;
}

export const EXPENSE_CATEGORIES: string[] = [
  '餐饮', '交通', '购物', '居住', '娱乐', '医疗', '学习', '其他'
];

export const INCOME_CATEGORIES: string[] = [
  '工资', '兼职', '红包', '理财', '其他'
];

export interface CategoryAmount {
  name: string;
  amount: number;
  /** 占同类合计的百分比，0~100 */
  percent: number;
}

export interface LedgerSummary {
  expense: number;
  income: number;
  /** 结余 = 收入 - 支出，可为负 */
  balance: number;
  count: number;
  /** 支出分类占比，按金额降序 */
  byCategory: CategoryAmount[];
  /** 预算使用百分比 0~100；未设预算时为 0 */
  budgetPercent: number;
  /** 预算剩余，可为负；未设预算时为 0 */
  budgetLeft: number;
  /** 是否已超预算 */
  overBudget: boolean;
  /** 三档感受的笔数（只统计支出） */
  worthCount: number;
  neutralCount: number;
  regretCount: number;
  /** 已标记感受的支出笔数 */
  markedCount: number;
  /** 值得指数 0~100；没有任何标记时为 -1（不显示分数） */
  worthScore: number;
  /** 最后悔的支出，按金额降序，最多 3 条 */
  regretTop: LedgerRecord[];
}

/** 金额清洗：取绝对值、保留两位小数 */
export function normalizeAmount(value: number): number {
  if (Number.isNaN(value)) {
    return 0;
  }
  const abs: number = Math.abs(value);
  return Math.round(abs * 100) / 100;
}

/** 金额展示：整数不带小数，非整数保留两位 */
export function formatAmount(value: number): string {
  const v: number = Math.round(value * 100) / 100;
  if (v === Math.floor(v)) {
    return `${Math.floor(v)}`;
  }
  return v.toFixed(2);
}

/** 取日期所属月份 'yyyy-MM' */
export function monthOf(date: string): string {
  return date.slice(0, 7);
}

/** 统计某个月：支出 / 收入 / 结余 / 分类占比 / 预算进度 */
export function summarizeLedger(records: LedgerRecord[], month: string, budget: number): LedgerSummary {
  let expense: number = 0;
  let income: number = 0;
  let count: number = 0;
  const categoryMap: Map<string, number> = new Map();

  for (const r of records) {
    if (monthOf(r.date) !== month) {
      continue;
    }
    count += 1;
    if (r.type === LedgerType.INCOME) {
      income += r.amount;
    } else {
      expense += r.amount;
      const current: number = categoryMap.get(r.category) ?? 0;
      categoryMap.set(r.category, current + r.amount);
    }
  }

  const byCategory: CategoryAmount[] = [];
  categoryMap.forEach((amount: number, name: string) => {
    byCategory.push({
      name: name,
      amount: Math.round(amount * 100) / 100,
      percent: expense > 0 ? Math.round(amount * 100 / expense) : 0
    });
  });
  byCategory.sort((a: CategoryAmount, b: CategoryAmount): number => b.amount - a.amount);

  const safeBudget: number = budget > 0 ? budget : 0;
  const budgetPercent: number = safeBudget > 0
    ? Math.min(100, Math.round(expense * 100 / safeBudget))
    : 0;

  // 感受统计：只统计支出
  let worthCount: number = 0;
  let neutralCount: number = 0;
  let regretCount: number = 0;
  const regretAll: LedgerRecord[] = [];
  for (const r of records) {
    if (monthOf(r.date) !== month || r.type !== LedgerType.EXPENSE) {
      continue;
    }
    if (r.feeling === LedgerFeeling.WORTH) {
      worthCount += 1;
    } else if (r.feeling === LedgerFeeling.NEUTRAL) {
      neutralCount += 1;
    } else if (r.feeling === LedgerFeeling.REGRET) {
      regretCount += 1;
      // 0 元的支出没什么可后悔的，不进 Top3
      if (r.amount > 0) {
        regretAll.push(r);
      }
    }
  }
  const markedCount: number = worthCount + neutralCount + regretCount;
  regretAll.sort((a: LedgerRecord, b: LedgerRecord): number => b.amount - a.amount);

  return {
    expense: Math.round(expense * 100) / 100,
    income: Math.round(income * 100) / 100,
    balance: Math.round((income - expense) * 100) / 100,
    count: count,
    byCategory: byCategory,
    budgetPercent: budgetPercent,
    budgetLeft: safeBudget > 0 ? Math.round((safeBudget - expense) * 100) / 100 : 0,
    overBudget: safeBudget > 0 && expense > safeBudget,
    worthCount: worthCount,
    neutralCount: neutralCount,
    regretCount: regretCount,
    markedCount: markedCount,
    worthScore: computeWorthScore(worthCount, neutralCount, regretCount, expense, safeBudget),
    regretTop: regretAll.slice(0, 3)
  };
}

/**
 * 月度「值得指数」0~100；没有任何标记时返回 -1（页面不显示分数）。
 * 公式刻意做得透明可解释：值得占比 70 分 + 预算达成度 30 分。
 */
export function computeWorthScore(
  worthCount: number,
  neutralCount: number,
  regretCount: number,
  expense: number,
  budget: number
): number {
  const marked: number = worthCount + neutralCount + regretCount;
  if (marked <= 0) {
    return -1;
  }
  const worthRatio: number = (worthCount + neutralCount * 0.5) / marked;
  let budgetRatio: number = 1;
  if (budget > 0 && expense > budget) {
    budgetRatio = Math.max(0, 1 - (expense - budget) / budget);
  }
  const score: number = worthRatio * 70 + budgetRatio * 30;
  return Math.max(0, Math.min(100, Math.round(score)));
}

/** 今天还能花多少：预算剩余按本月剩余天数（含今天）摊平；未设预算返回 -1 */
export function computeDailyLeft(expense: number, budget: number, dayOfMonth: number, daysInMonth: number): number {
  if (budget <= 0) {
    return -1;
  }
  const leftDays: number = daysInMonth - dayOfMonth + 1;
  if (leftDays <= 0) {
    return -1;
  }
  return Math.floor((budget - expense) / leftDays);
}

/** 本月每日支出条：一天一格，0 表示当天没有支出 */
export function buildDailySpendStrip(records: LedgerRecord[], month: string, daysInMonth: number): number[] {
  const out: number[] = [];
  for (let i: number = 0; i < daysInMonth; i++) {
    out.push(0);
  }
  for (const r of records) {
    if (monthOf(r.date) !== month || r.type !== LedgerType.EXPENSE) {
      continue;
    }
    const day: number = Number(r.date.slice(8, 10));
    if (day >= 1 && day <= daysInMonth) {
      out[day - 1] = Math.round((out[day - 1] + r.amount) * 100) / 100;
    }
  }
  return out;
}

/** 一条花费洞察 */
export interface SpendInsight {
  text: string;
}

/** 输出洞察时每个对比组至少要有多少天有记录，样本太少说出来是误导 */
export const MIN_GROUP_DAYS: number = 3;

/**
 * 心情 × 花费 的关联洞察 —— 只有同时装着日记的应用才能说这些话。
 *
 * moodByDate 来自日记（日期 → 心情标签），spend 来自账本，两边在本机汇合，不联网。
 */
export function buildSpendingInsights(
  records: LedgerRecord[],
  moodByDate: Map<string, string>,
  month: string
): SpendInsight[] {
  const spendByDate: Map<string, number> = new Map();
  for (const r of records) {
    if (monthOf(r.date) !== month || r.type !== LedgerType.EXPENSE) {
      continue;
    }
    const current: number = spendByDate.get(r.date) ?? 0;
    spendByDate.set(r.date, current + r.amount);
  }

  const out: SpendInsight[] = [];

  // 洞察 1：低落的日子 vs 开心的日子
  const lowDates: string[] = [];
  const happyDates: string[] = [];
  spendByDate.forEach((amount: number, date: string) => {
    const mood: string = moodByDate.get(date) ?? '';
    if (mood.indexOf('低落') >= 0 || mood.indexOf('难过') >= 0 || mood.indexOf('烦') >= 0) {
      lowDates.push(date);
    } else if (mood.indexOf('开心') >= 0 || mood.indexOf('快乐') >= 0 || mood.indexOf('高兴') >= 0) {
      happyDates.push(date);
    }
  });
  if (lowDates.length >= MIN_GROUP_DAYS && happyDates.length >= MIN_GROUP_DAYS) {
    const lowAvg: number = averageSpend(spendByDate, lowDates);
    const happyAvg: number = averageSpend(spendByDate, happyDates);
    if (Math.abs(lowAvg - happyAvg) >= 1) {
      out.push({
        text: lowAvg > happyAvg
          ? `心情不好的日子平均花 ${formatAmount(lowAvg)} 元，比开心的日子多 ${formatAmount(lowAvg - happyAvg)} 元`
          : `心情好的日子平均花 ${formatAmount(happyAvg)} 元，比低落的日子多 ${formatAmount(happyAvg - lowAvg)} 元`
      });
    }
  }

  // 洞察 2：周末 vs 工作日
  const weekend: string[] = [];
  const weekday: string[] = [];
  spendByDate.forEach((amount: number, date: string) => {
    const dow: number = DateUtils.parseDate(date).getDay();
    if (dow === 0 || dow === 6) {
      weekend.push(date);
    } else {
      weekday.push(date);
    }
  });
  if (weekend.length >= 1 && weekday.length >= MIN_GROUP_DAYS) {
    const weekAvg: number = averageSpend(spendByDate, weekend);
    const workAvg: number = averageSpend(spendByDate, weekday);
    if (Math.abs(weekAvg - workAvg) >= 1) {
      out.push({
        text: weekAvg > workAvg
          ? `周末平均花 ${formatAmount(weekAvg)} 元，比工作日多 ${formatAmount(weekAvg - workAvg)} 元`
          : `工作日平均花 ${formatAmount(workAvg)} 元，比周末多 ${formatAmount(workAvg - weekAvg)} 元`
      });
    }
  }

  // 洞察 3：后悔最集中的分类
  const regretByCategory: Map<string, number> = new Map();
  for (const r of records) {
    if (monthOf(r.date) !== month || r.type !== LedgerType.EXPENSE) {
      continue;
    }
    if (r.feeling !== LedgerFeeling.REGRET || r.amount <= 0) {
      continue;
    }
    const current: number = regretByCategory.get(r.category) ?? 0;
    regretByCategory.set(r.category, current + 1);
  }
  let topCategory: string = '';
  let topCount: number = 0;
  regretByCategory.forEach((count: number, name: string) => {
    if (count > topCount) {
      topCount = count;
      topCategory = name;
    }
  });
  if (topCategory !== '') {
    out.push({ text: `标记「后悔」的支出里，最多的是「${topCategory}」，共 ${topCount} 笔` });
  }

  return out.slice(0, 3);
}

function averageSpend(spendByDate: Map<string, number>, dates: string[]): number {
  if (dates.length === 0) {
    return 0;
  }
  let total: number = 0;
  for (const d of dates) {
    total += spendByDate.get(d) ?? 0;
  }
  return Math.round(total / dates.length * 100) / 100;
}

/** 本月小结：与日历、本周回顾同款口吻的规则式总结 */
export function buildLedgerSummaryLine(summary: LedgerSummary): string {
  if (summary.count === 0) {
    return '这个月还没有记账，在上面记下第一笔吧';
  }
  let line: string = `这个月花了 ${formatAmount(summary.expense)} 元、收入 ${formatAmount(summary.income)} 元`
    + `，结余 ${formatAmount(summary.balance)} 元`;
  if (summary.byCategory.length > 0) {
    line += `；花得最多的是「${summary.byCategory[0].name}」，占 ${summary.byCategory[0].percent}%`;
  }
  if (summary.overBudget) {
    line += `；已超预算 ${formatAmount(-summary.budgetLeft)} 元`;
  }
  return line;
}
