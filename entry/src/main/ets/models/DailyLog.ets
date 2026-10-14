/**
 * 每日心情记录数据模型与心情枚举
 *
 * 一天一条记录（date 唯一）：
 *  - mood       今天的心情（6 个固定心情，或 CUSTOM 表示由用户自己填写）
 *  - customMood 用户自己填写的心情文字（仅 mood === CUSTOM 时有意义）
 *  - journal    今天发生了什么（手写）
 *  - plan       明天要做的事
 *
 * 界面用渐变色点 + 中文标签表达心情，不使用 emoji。
 */
export enum Mood {
  HAPPY = 0,
  SWEET = 1,
  NORMAL = 2,
  SAD = 3,
  ANGRY = 4,
  MISS = 5,
  /** 用户自己填写的心情，文字存在 DailyLog.customMood */
  CUSTOM = 6
}

export interface MoodOption {
  mood: Mood;
  label: string;
  /** 色点渐变起始色 */
  colorStart: string;
  /** 色点渐变结束色 */
  colorEnd: string;
}

/** 自定义心情的兜底标签（用户没填文字时显示） */
export const CUSTOM_MOOD_LABEL: string = '自定义';
/** 自定义心情统一使用的青绿渐变，与 6 个暖色明显区分 */
export const CUSTOM_MOOD_COLOR_START: string = '#9CC7B6';
export const CUSTOM_MOOD_COLOR_END: string = '#5F8F7B';
/** 自定义心情文字长度上限 */
export const MAX_CUSTOM_MOOD_LENGTH: number = 8;

/** 心情配色：暖色系内取六种固定心情，深浅两套主题下都能互相区分 */
export const MOOD_OPTIONS: MoodOption[] = [
  { mood: Mood.HAPPY, label: '开心', colorStart: '#FFC978', colorEnd: '#F0A13C' },
  { mood: Mood.SWEET, label: '甜蜜', colorStart: '#F5A9A0', colorEnd: '#E0726A' },
  { mood: Mood.NORMAL, label: '平淡', colorStart: '#C8C2B6', colorEnd: '#9E9689' },
  { mood: Mood.SAD, label: '低落', colorStart: '#A8BED4', colorEnd: '#7595B4' },
  { mood: Mood.ANGRY, label: '生气', colorStart: '#E59A7A', colorEnd: '#C4643E' },
  { mood: Mood.MISS, label: '想念', colorStart: '#C5AEDA', colorEnd: '#9075B4' }
];

export interface DailyLog {
  id: string;
  /** 'yyyy-MM-dd'，一天一条 */
  date: string;
  mood: Mood;
  /** 用户自己填写的心情文字；mood 不是 CUSTOM 时保留但不用 */
  customMood: string;
  /** 今天发生了什么 */
  journal: string;
  /** 明天要做的事 */
  plan: string;
  /** 今天的照片（应用私有目录里的 file:// 路径），最多 MAX_LOG_PHOTOS 张 */
  photoUris: string[];
  /** 这条记录带的标签，最多 MAX_LOG_TAGS 个；规范化规则见 models/Tag.ets */
  tags: string[];
  /**
   * 这一天是不是"真的记录过"。
   *
   * 为未来日期安排计划时，只会在那天的记录里写入 plan（见 DayPlanPage），
   * 这种"计划存根"的 mood 是默认值，光靠内容分辨不出它和"只选了心情的记录"，
   * 所以必须显式标记：正常保存为 true，只写计划的存根为 false。
   */
  hasEntry: boolean;
  createdAt: number;
  updatedAt: number;
}

/**
 * 这一天是否算一条真正的记录。
 * 计划存根（hasEntry = false）不算：不进连续天数、累计篇数、日历心情色、统计与时间轴。
 */
export function hasEntry(log: DailyLog): boolean {
  return log.hasEntry;
}

/** 每条记录最多能带几张照片 */
export const MAX_LOG_PHOTOS: number = 3;

/**
 * 照片列表 → 存库字符串。
 * 用 JSON 而不是逗号分隔：URI 里可能出现分隔符，JSON 能安全转义。
 */
export function serializePhotoUris(list: string[]): string {
  if (list.length === 0) {
    return '';
  }
  return JSON.stringify(list);
}

/** 存库字符串 → 照片列表。空串或坏数据一律回退为空数组，绝不抛错。 */
export function parsePhotoUris(raw: string): string[] {
  const out: string[] = [];
  if (raw === '') {
    return out;
  }
  try {
    const parsed = JSON.parse(raw) as string[];
    if (!parsed || !Array.isArray(parsed)) {
      return out;
    }
    for (const item of parsed) {
      if (typeof item === 'string' && item !== '') {
        out.push(item);
      }
    }
  } catch (err) {
    return out;
  }
  return out;
}

/**
 * 标签列表 → 存库字符串。
 * 与照片同一套做法：用 JSON 而不是逗号分隔，标签里出现分隔符也能安全转义。
 */
export function serializeTags(tags: string[]): string {
  if (tags.length === 0) {
    return '';
  }
  return JSON.stringify(tags);
}

/**
 * 存库字符串 → 标签列表。空串或坏数据一律回退为空数组，绝不抛错。
 *
 * 比 parsePhotoUris 多一步：只有空白的脏项（如 " "）也算空项，直接丢掉；
 * 留下来的标签去首尾空白（正常写库的标签本来就是 trim 过的，这里只是兜底）。
 */
export function parseTags(raw: string): string[] {
  const out: string[] = [];
  if (raw === '') {
    return out;
  }
  try {
    const parsed = JSON.parse(raw) as string[];
    if (!parsed || !Array.isArray(parsed)) {
      return out;
    }
    for (const item of parsed) {
      if (typeof item !== 'string') {
        continue;
      }
      const text: string = item.trim();
      if (text !== '') {
        out.push(text);
      }
    }
  } catch (err) {
    return out;
  }
  return out;
}

/** 按上限算还能再加几张照片（负数一律当 0） */
export function remainingPhotoSlots(current: number): number {
  const left: number = MAX_LOG_PHOTOS - current;
  return left > 0 ? left : 0;
}

/**
 * 根据心情枚举获取展示信息。
 * 6 个固定心情返回内置配色；CUSTOM（以及任何未知值）返回青绿渐变的合成项，
 * 这样 MoodDot 只靠 mood 就能取到正确颜色。
 */
export function getMoodOption(mood: Mood): MoodOption {
  for (let i: number = 0; i < MOOD_OPTIONS.length; i++) {
    if (MOOD_OPTIONS[i].mood === mood) {
      return MOOD_OPTIONS[i];
    }
  }
  return {
    mood: Mood.CUSTOM,
    label: CUSTOM_MOOD_LABEL,
    colorStart: CUSTOM_MOOD_COLOR_START,
    colorEnd: CUSTOM_MOOD_COLOR_END
  };
}

/** 按标签取心情配色，供只有标签字符串的场景（如统计页）使用 */
export function moodColorsByLabel(label: string): string[] {
  for (let i: number = 0; i < MOOD_OPTIONS.length; i++) {
    if (MOOD_OPTIONS[i].label === label) {
      return [MOOD_OPTIONS[i].colorStart, MOOD_OPTIONS[i].colorEnd];
    }
  }
  // 不是 6 个固定心情之一 → 判为用户自定义，用青绿
  // （原来是灰米 #C8C2B6，会和「平淡」撞色）
  return [CUSTOM_MOOD_COLOR_START, CUSTOM_MOOD_COLOR_END];
}

/** 心情配色 [start, end]；CUSTOM 统一用青绿渐变 */
export function moodColors(mood: Mood): string[] {
  if (mood === Mood.CUSTOM) {
    return [CUSTOM_MOOD_COLOR_START, CUSTOM_MOOD_COLOR_END];
  }
  const option: MoodOption = getMoodOption(mood);
  return [option.colorStart, option.colorEnd];
}

/** 清洗自定义心情：去掉首尾空白并截断到上限 */
export function normalizeCustomMood(text: string): string {
  const trimmed: string = text.trim();
  return trimmed.length <= MAX_CUSTOM_MOOD_LENGTH
    ? trimmed
    : trimmed.slice(0, MAX_CUSTOM_MOOD_LENGTH);
}

/**
 * 心情展示文字。
 * 6 个固定心情用内置标签；CUSTOM 用用户填写的文字，为空时回退为「自定义」。
 */
export function moodLabel(mood: Mood, customMood: string): string {
  if (mood === Mood.CUSTOM) {
    const text: string = normalizeCustomMood(customMood);
    return text === '' ? CUSTOM_MOOD_LABEL : text;
  }
  return getMoodOption(mood).label;
}

/**
 * 心情对应的情绪值（1~5），供心情趋势图使用。
 *
 * 说明：这是把离散心情画成折线而做的**固定映射**，不代表对心情好坏的评判；
 * 平淡 / 想念 / 自定义 统一记为 3。
 */
export function moodScoreByLabel(label: string): number {
  if (label === '开心' || label === '甜蜜') {
    return 5;
  }
  if (label === '低落') {
    return 2;
  }
  if (label === '生气') {
    return 1;
  }
  return 3;
}

/** 一条记录是否命中搜索关键词（匹配心情标签、今天发生了什么、明天要做的事） */
export function matchLog(log: DailyLog, keyword: string): boolean {
  const kw: string = keyword.trim();
  if (kw === '') {
    return false;
  }
  if (moodLabel(log.mood, log.customMood).indexOf(kw) >= 0) {
    return true;
  }
  return log.journal.indexOf(kw) >= 0 || log.plan.indexOf(kw) >= 0;
}

/** 搜索：返回命中的记录（保持传入顺序） */
export function searchLogs(logs: DailyLog[], keyword: string): DailyLog[] {
  const kw: string = keyword.trim();
  const result: DailyLog[] = [];
  if (kw === '') {
    return result;
  }
  for (const log of logs) {
    if (matchLog(log, kw)) {
      result.push(log);
    }
  }
  return result;
}

/** 高亮用的文字分段：hit 为 true 表示这段是命中的关键词 */
export interface TextSegment {
  text: string;
  hit: boolean;
}

/** 按关键词把一段文字切成「命中/未命中」交替的分段，供界面高亮 */
export function splitByKeyword(text: string, keyword: string): TextSegment[] {
  const kw: string = keyword.trim();
  const segments: TextSegment[] = [];
  if (kw === '') {
    segments.push({ text: text, hit: false });
    return segments;
  }
  let cursor: number = 0;
  while (cursor < text.length) {
    const idx: number = text.indexOf(kw, cursor);
    if (idx < 0) {
      segments.push({ text: text.slice(cursor), hit: false });
      break;
    }
    if (idx > cursor) {
      segments.push({ text: text.slice(cursor, idx), hit: false });
    }
    segments.push({ text: kw, hit: true });
    cursor = idx + kw.length;
  }
  return segments;
}

/**
 * 取出命中位置附近的一段文字，用于搜索结果列表展示；
 * 命中的是心情标签、或都没命中时，退回普通摘要。
 */
export function matchSnippet(log: DailyLog, keyword: string, maxChars: number): string {
  const kw: string = keyword.trim();
  const fields: string[] = [log.journal, log.plan];
  for (const field of fields) {
    const idx: number = field.indexOf(kw);
    if (idx >= 0) {
      const start: number = idx > 8 ? idx - 8 : 0;
      let text: string = field.slice(start, start + maxChars);
      if (start > 0) {
        text = `…${text}`;
      }
      if (start + maxChars < field.length) {
        text = `${text}…`;
      }
      return text.replace(/\n/g, ' ');
    }
  }
  return logSummary(log, maxChars);
}

/** 记录正文与计划的总字数（不含空白） */
export function countChars(log: DailyLog): number {
  const text: string = `${log.journal}${log.plan}`;
  return text.replace(/\s/g, '').length;
}

/**
 * 取列表用的单行摘要：优先日记，日记为空则退而取明日计划。
 * 只取**第一个非空行**（避免把整篇正文铺进列表），超长截断并加省略号。
 */
export function logSummary(log: DailyLog, maxChars: number): string {
  const source: string = log.journal.trim() !== '' ? log.journal : log.plan;
  const lines: string[] = source.split('\n');
  let firstLine: string = '';
  for (const line of lines) {
    const trimmed: string = line.trim();
    if (trimmed !== '') {
      firstLine = trimmed;
      break;
    }
  }
  if (firstLine === '') {
    return '（无正文）';
  }
  return firstLine.length <= maxChars ? firstLine : `${firstLine.slice(0, maxChars)}…`;
}
