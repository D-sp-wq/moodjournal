import { DailyLog, hasEntry } from './DailyLog';

/**
 * 标签：纯函数模型（无数据库、无界面依赖，可直接单元测试）。
 *
 * 一条记录最多 MAX_LOG_TAGS 个标签，单个标签最长 MAX_TAG_LENGTH 个字。
 * 标签只存在本机数据库的 daily_logs.tags 这一列里（JSON 字符串），
 * 不联网、不申请任何权限。
 */

/** 一条记录最多几个标签 */
export const MAX_LOG_TAGS: number = 3;
/** 单个标签最长几个字 */
export const MAX_TAG_LENGTH: number = 8;

/** 标签 + 出现次数（出现次数 = 用过这个标签的记录条数） */
export interface TagCount {
  name: string;
  count: number;
}

/**
 * 标签分隔符：空白（空格/制表/换行）、半角逗号、全角逗号、顿号。
 * 用户顺手敲的几种写法都要能切开。
 */
const TAG_SEPARATORS: RegExp = /[\s,，、]+/;

/** 单个标签规范化：去首尾空白 + 截断到 MAX_TAG_LENGTH */
function cleanTag(raw: string): string {
  const text: string = raw.trim();
  return text.length <= MAX_TAG_LENGTH ? text : text.slice(0, MAX_TAG_LENGTH);
}

/**
 * 清洗调用方传进来的已有标签：丢弃空串、截断超长、去掉重复、最多保留 MAX_LOG_TAGS 个。
 * 正常路径上它们本来就是规范的，这里只是让 normalizeTagInput 对任何输入都成立。
 */
function cleanExisting(existing: string[]): string[] {
  const out: string[] = [];
  for (const raw of existing) {
    const tag: string = cleanTag(raw);
    if (tag === '' || out.indexOf(tag) >= 0) {
      continue;
    }
    if (out.length >= MAX_LOG_TAGS) {
      break;
    }
    out.push(tag);
  }
  return out;
}

/** 读一条记录的标签数组；脏数据里缺字段时当空数组，避免整页崩掉 */
function tagsOf(log: DailyLog): string[] {
  const tags: string[] = log.tags;
  if (tags === undefined || tags === null) {
    return [];
  }
  return tags;
}

/**
 * 用户输入 → 规范标签数组（含已有标签）。
 *
 * 规则：按空白/中英文逗号/顿号切分 → 去首尾空白 → 丢弃空串 → 截断到 MAX_TAG_LENGTH 字
 * → 与 existing 及自身去重 → 总数最多 MAX_LOG_TAGS 个。
 * 返回值是「已有标签 + 这次新加的」，可直接整体回写到记录上。
 */
export function normalizeTagInput(text: string, existing: string[]): string[] {
  const result: string[] = cleanExisting(existing);
  if (result.length >= MAX_LOG_TAGS) {
    return result;
  }
  const parts: string[] = text.split(TAG_SEPARATORS);
  for (const part of parts) {
    const tag: string = cleanTag(part);
    if (tag === '' || result.indexOf(tag) >= 0) {
      continue;
    }
    if (result.length >= MAX_LOG_TAGS) {
      break;
    }
    result.push(tag);
  }
  return result;
}

/**
 * 汇总所有记录用过的标签，按出现次数降序；次数相同按名称升序（顺序稳定，可单测）。
 *
 * 只统计**真正的记录**（hasEntry = true）：计划存根（DayPlanPage 写的空壳）不算。
 * 同一条记录里重复写了同一个标签只算一次。
 */
export function collectTags(logs: DailyLog[]): TagCount[] {
  const names: string[] = [];
  const counts: number[] = [];
  for (const log of logs) {
    if (!hasEntry(log)) {
      continue;
    }
    const seen: string[] = [];
    for (const raw of tagsOf(log)) {
      const tag: string = cleanTag(raw);
      if (tag === '' || seen.indexOf(tag) >= 0) {
        continue;
      }
      seen.push(tag);
      const index: number = names.indexOf(tag);
      if (index >= 0) {
        counts[index] = counts[index] + 1;
      } else {
        names.push(tag);
        counts.push(1);
      }
    }
  }

  const result: TagCount[] = [];
  for (let i: number = 0; i < names.length; i++) {
    result.push({ name: names[i], count: counts[i] });
  }
  // 次数降序；次数相同按名称升序（用码位比较而不是 localeCompare，跨设备结果一致）
  result.sort((a: TagCount, b: TagCount): number => {
    if (a.count !== b.count) {
      return b.count - a.count;
    }
    if (a.name === b.name) {
      return 0;
    }
    return a.name < b.name ? -1 : 1;
  });
  return result;
}

/** 该记录是否含某标签（精确匹配：'工作' 不会命中 '工作复盘'；空标签一律不算命中） */
export function hasTag(log: DailyLog, tag: string): boolean {
  const target: string = tag.trim();
  if (target === '') {
    return false;
  }
  for (const raw of tagsOf(log)) {
    if (raw === target) {
      return true;
    }
  }
  return false;
}

/** 按标签筛选记录（不带该标签的滤掉，保持传入顺序；空标签返回空数组） */
export function filterByTag(logs: DailyLog[], tag: string): DailyLog[] {
  const target: string = tag.trim();
  const result: DailyLog[] = [];
  if (target === '') {
    return result;
  }
  for (const log of logs) {
    if (hasTag(log, target)) {
      result.push(log);
    }
  }
  return result;
}
