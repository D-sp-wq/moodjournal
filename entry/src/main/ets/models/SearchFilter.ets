import { DailyLog, MOOD_OPTIONS, hasEntry, matchLog, moodLabel } from './DailyLog';
import { hasTag } from './Tag';
import { DateUtils } from '../common/utils/DateUtils';

/**
 * 搜索筛选：纯函数模型（无数据库、无界面依赖，可直接单元测试）。
 *
 * 搜索页在这之前只能按关键词找记录；这里把「心情 / 时间范围 / 只看有照片 / 标签」
 * 四种条件抽成数据 + 判定函数，界面只负责收集条件与渲染结果。
 *
 * 约定：
 *  - 所有条件都是「与」关系，全部命中才留下；
 *  - 空串 / 0 / false 表示该项不限，因此默认条件等于不筛选；
 *  - 只保留**真正的记录**（hasEntry = true），计划存根（DayPlanPage 写的空壳）不算；
 *  - 全部本机计算，不联网、不申请任何权限。
 */

/** 搜索筛选条件（界面上的筛选栏与之一一对应） */
export interface SearchFilters {
  keyword: string;
  /** 心情标签；空串表示不限。用 moodLabel 产出的标签值（含自定义心情） */
  mood: string;
  /** 时间范围：0=不限 7=近7天 30=近30天 365=近一年 */
  rangeDays: number;
  /** 只看带照片的记录 */
  photoOnly: boolean;
  /** 标签筛选；空串表示不限 */
  tag: string;
}

/** 默认筛选条件：全部不限，等价于「不做筛选」 */
export const EMPTY_FILTERS: SearchFilters = {
  keyword: '',
  mood: '',
  rangeDays: 0,
  photoOnly: false,
  tag: ''
};

/** 时间范围「不限」 */
export const RANGE_ALL: number = 0;
/** 时间范围「近 7 天」 */
export const RANGE_7: number = 7;
/** 时间范围「近 30 天」 */
export const RANGE_30: number = 30;
/** 时间范围「近一年」 */
export const RANGE_365: number = 365;

/** 筛选栏上时间范围的可选项，顺序固定（不限 → 近7天 → 近30天 → 近一年） */
export const RANGE_OPTIONS: number[] = [RANGE_ALL, RANGE_7, RANGE_30, RANGE_365];

/** 时间范围 → 界面文案。只有这里一处映射，界面按它渲染胶囊 */
export function rangeLabel(rangeDays: number): string {
  if (rangeDays === RANGE_7) {
    return '近 7 天';
  }
  if (rangeDays === RANGE_30) {
    return '近 30 天';
  }
  if (rangeDays === RANGE_365) {
    return '近一年';
  }
  return '不限';
}

/** 记录的照片列表；脏数据里缺字段时当空数组，避免整页崩掉 */
function photosOf(log: DailyLog): string[] {
  const uris: string[] = log.photoUris;
  if (uris === undefined || uris === null) {
    return [];
  }
  return uris;
}

/**
 * 某条记录是否命中全部条件。
 *
 * 关键词非空时用与既有搜索一致的 matchLog（匹配心情标签、正文、明日计划）；
 * 关键词为空时不做关键词过滤，只看其它条件。
 */
export function matchesFilters(log: DailyLog, filters: SearchFilters, todayStr: string): boolean {
  if (!hasEntry(log)) {
    return false;
  }
  const keyword: string = filters.keyword.trim();
  if (keyword !== '' && !matchLog(log, keyword)) {
    return false;
  }
  const mood: string = filters.mood.trim();
  if (mood !== '' && moodLabel(log.mood, log.customMood) !== mood) {
    return false;
  }
  if (filters.rangeDays > 0) {
    // 区间为 [today - (rangeDays - 1), today]，含首尾
    const back: number = DateUtils.daysBetween(log.date, todayStr);
    const lastBack: number = filters.rangeDays - 1;
    if (back < 0) {
      // 未来日期不算「最近 N 天」
      return false;
    }
    // 写成「必须落在 [0, lastBack] 里」而不是「back > lastBack 就丢」：
    // daysBetween 拿不到合法日期时会给出 NaN，而 NaN 的大小比较恒为 false，
    // 那样就会把记录误放行，这里先挡掉
    const withinRange: boolean = back <= lastBack;
    if (!withinRange) {
      return false;
    }
  }
  if (filters.photoOnly && photosOf(log).length === 0) {
    return false;
  }
  const tag: string = filters.tag.trim();
  if (tag !== '' && !hasTag(log, tag)) {
    return false;
  }
  return true;
}

/**
 * 按筛选条件过滤记录。
 *
 * 返回保持传入顺序；条件全为默认值时返回全部真正的记录（存根仍然排除）。
 */
export function applyFilters(logs: DailyLog[], filters: SearchFilters, todayStr: string): DailyLog[] {
  const result: DailyLog[] = [];
  for (const log of logs) {
    if (matchesFilters(log, filters, todayStr)) {
      result.push(log);
    }
  }
  return result;
}

/**
 * 当前生效的筛选条件摘要，用于界面上回显。
 *
 * 顺序固定为：心情 → 时间 → 照片 → 标签；没有筛选时返回空数组。
 */
export function describeFilters(filters: SearchFilters): string[] {
  const parts: string[] = [];
  const mood: string = filters.mood.trim();
  if (mood !== '') {
    parts.push(`心情：${mood}`);
  }
  if (filters.rangeDays > 0) {
    parts.push(`时间：${rangeLabel(filters.rangeDays)}`);
  }
  if (filters.photoOnly) {
    parts.push('有照片');
  }
  const tag: string = filters.tag.trim();
  if (tag !== '') {
    parts.push(`标签：${tag}`);
  }
  return parts;
}

/** 筛选条件是否为空（心情/时间/照片/标签全部为默认值；关键词不算筛选） */
export function isFilterEmpty(filters: SearchFilters): boolean {
  if (filters.mood.trim() !== '') {
    return false;
  }
  if (filters.rangeDays > 0) {
    return false;
  }
  if (filters.photoOnly) {
    return false;
  }
  if (filters.tag.trim() !== '') {
    return false;
  }
  return true;
}

/**
 * 可选的心情标签列表：来自记录里实际出现过的心情，按出现次数降序。
 *
 * 次数相同时读取顺序稳定（6 个固定心情在前，顺序同首页选择器；自定义心情按首次出现顺序排在后面），
 * 这样界面上胶囊的先后不会因数据顺序抖动。
 * 计划存根不算；空输入返回空数组。
 */
export function availableMoods(logs: DailyLog[]): string[] {
  const names: string[] = [];
  const counts: number[] = [];

  // 先把 6 个固定心情按首页的顺序占好位置，保证同次数时的先后稳定
  for (const option of MOOD_OPTIONS) {
    names.push(option.label);
    counts.push(0);
  }

  for (const log of logs) {
    if (!hasEntry(log)) {
      continue;
    }
    const label: string = moodLabel(log.mood, log.customMood);
    if (label === '') {
      continue;
    }
    const index: number = names.indexOf(label);
    if (index >= 0) {
      counts[index] = counts[index] + 1;
    } else {
      names.push(label);
      counts.push(1);
    }
  }

  const used: string[] = [];
  const usedCounts: number[] = [];
  for (let i: number = 0; i < names.length; i++) {
    if (counts[i] > 0) {
      used.push(names[i]);
      usedCounts.push(counts[i]);
    }
  }

  // 用「索引 + 次数」一起排序：次数降序；次数相同按原有顺序（稳定）
  const order: number[] = [];
  for (let i: number = 0; i < used.length; i++) {
    order.push(i);
  }
  order.sort((a: number, b: number): number => {
    if (usedCounts[a] !== usedCounts[b]) {
      return usedCounts[b] - usedCounts[a];
    }
    return a - b;
  });

  const result: string[] = [];
  for (const index of order) {
    result.push(used[index]);
  }
  return result;
}
