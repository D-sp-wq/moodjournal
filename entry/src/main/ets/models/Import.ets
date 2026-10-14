import { DateUtils } from '../common/utils/DateUtils';
import { DailyLog } from './DailyLog';
import { LedgerRecord, LedgerFeeling, LedgerType } from './Ledger';
import { Habit, HabitCheck } from './Habit';
import { TaskPlan, clampPlannedDays } from './TaskPlan';
import { Anniversary } from './Anniversary';

/**
 * 备份导入：解析 + 校验（纯函数，可直接单元测试）。
 *
 * 解析的对象是 ExportService.buildExportJson() 产出的 JSON。
 * 这里的每一条规则都对应一种真实会发生的事故：备份文件被改坏、被别的应用改写过、
 * 传到手机上时被截断、或者是更老版本导出的（缺字段）。
 *
 * 三条总原则：
 *  1. **绝不抛异常**：任何非法输入都返回 ok=false + 中文原因，界面只负责显示。
 *  2. **能不报错就不报错**：数组字段缺失 = 空数组；单条记录坏了 = 跳过这一条，
 *     而不是整份备份作废 —— 用户往往是丢了手机才来恢复的，能救回多少算多少。
 *  3. **返回的对象一定补齐默认值**：老备份没有 hasEntry / feeling，
 *     补默认值比让下游各处判空更安全。
 */

/** 应用标识：备份 JSON 根部的 app 字段必须等于这个值 */
export const IMPORT_APP_NAME: string = '心情手记';

/** counts 的键，与导出 JSON 里的数组字段名一致 */
export const COUNT_DAILY_LOGS: string = 'dailyLogs';
export const COUNT_LEDGER_RECORDS: string = 'ledgerRecords';
export const COUNT_HABITS: string = 'habits';
export const COUNT_HABIT_CHECKS: string = 'habitChecks';
export const COUNT_TASK_PLANS: string = 'taskPlans';
export const COUNT_IMPORTANT_DAYS: string = 'importantDays';

/** 六类数据在 counts 里的固定顺序（界面按此顺序展示） */
export const COUNT_KEYS: string[] = [
  COUNT_DAILY_LOGS,
  COUNT_LEDGER_RECORDS,
  COUNT_HABITS,
  COUNT_HABIT_CHECKS,
  COUNT_TASK_PLANS,
  COUNT_IMPORTANT_DAYS
];

/** counts 键 → 中文名（用于"将导入 N 篇记录"这类提示） */
export function countLabel(key: string): string {
  if (key === COUNT_DAILY_LOGS) {
    return '记录';
  }
  if (key === COUNT_LEDGER_RECORDS) {
    return '账目';
  }
  if (key === COUNT_HABITS) {
    return '习惯';
  }
  if (key === COUNT_HABIT_CHECKS) {
    return '打卡';
  }
  if (key === COUNT_TASK_PLANS) {
    return '任务';
  }
  if (key === COUNT_IMPORTANT_DAYS) {
    return '重要日子';
  }
  return key;
}

/** 一份备份里的全部数据 */
export interface ImportBundle {
  dailyLogs: DailyLog[];
  ledgerRecords: LedgerRecord[];
  habits: Habit[];
  habitChecks: HabitCheck[];
  taskPlans: TaskPlan[];
  importantDays: Anniversary[];
}

/** 解析结果 */
export interface ImportResult {
  ok: boolean;
  /** 失败原因，ok 为 true 时为空串 */
  error: string;
  /** 失败时各项为空数组 */
  bundle: ImportBundle;
  /** 各类数据实际解析成功的条数，用于给用户看"将导入 N 条记录" */
  counts: Map<string, number>;
}

function emptyBundle(): ImportBundle {
  return {
    dailyLogs: [],
    ledgerRecords: [],
    habits: [],
    habitChecks: [],
    taskPlans: [],
    importantDays: []
  };
}

function emptyCounts(): Map<string, number> {
  const counts: Map<string, number> = new Map();
  for (const key of COUNT_KEYS) {
    counts.set(key, 0);
  }
  return counts;
}

function failure(reason: string): ImportResult {
  return { ok: false, error: reason, bundle: emptyBundle(), counts: emptyCounts() };
}

/** 失败 / 空结果：给服务层在解析之外出错时复用 */
export function emptyImportResult(reason: string): ImportResult {
  return failure(reason);
}

/**
 * 从异常里取一句能看的错误文案。
 * 只要第一行：系统抛出的错误往往带换行与堆栈，整段显示会撑爆弹窗。
 */
export function describeError(err: Object | null): string {
  if (err === null) {
    return '';
  }
  const raw: string = `${err}`;
  const firstLine: string = raw.split('\n')[0].replace(/\r/g, '').trim();
  return firstLine;
}

/** 字符串字段，缺失或类型不对时退回默认值 */
function safeString(raw: string | undefined, fallback: string): string {
  return typeof raw === 'string' ? raw : fallback;
}

/** 数字字段，缺失、类型不对或不是有限数时退回默认值 */
function safeNumber(raw: number | undefined, fallback: number): number {
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    return raw;
  }
  return fallback;
}

/** 布尔字段，缺失或类型不对时退回默认值 */
function safeBoolean(raw: boolean | undefined, fallback: boolean): boolean {
  return typeof raw === 'boolean' ? raw : fallback;
}

/** 日期字段：合法的 'yyyy-MM-dd' 才接受，否则返回 null */
function safeDate(raw: string | undefined): string | null {
  if (typeof raw !== 'string') {
    return null;
  }
  return DateUtils.isValidDateStr(raw) ? raw : null;
}

/** 照片列表：只留非空字符串，其余（含 null）丢弃 */
function safeStringArray(raw: Array<string> | undefined): string[] {
  const out: string[] = [];
  if (!Array.isArray(raw)) {
    return out;
  }
  for (const item of raw) {
    if (typeof item === 'string' && item !== '') {
      out.push(item);
    }
  }
  return out;
}

/**
 * 标签列表：只留非空字符串并去首尾空白（只有空白的脏项算空项）。
 *
 * 老备份没有 tags 字段、或者 tags 类型不对（不是数组）时一律当空数组，
 * **绝不因此判定这条记录非法** —— 丢标签远好过丢一整篇日记。
 */
function safeTagArray(raw: Array<string> | undefined): string[] {
  const out: string[] = [];
  if (!Array.isArray(raw)) {
    return out;
  }
  for (const item of raw) {
    if (typeof item !== 'string') {
      continue;
    }
    const text: string = item.trim();
    if (text !== '') {
      out.push(text);
    }
  }
  return out;
}

/**
 * 心情字段：必须是 0..6 的数字。
 *
 * 这里**不能**像别的字段那样"缺失就补默认值"：心情是日记的核心字段，
 * 补成"开心"等于凭空造出一条用户没写过的记录。缺失或类型不对一律跳过这一条。
 */
function safeMood(raw: number | undefined): number | null {
  if (typeof raw !== 'number' || !Number.isFinite(raw)) {
    return null;
  }
  if (raw < 0 || raw > 6) {
    return null;
  }
  return raw;
}

/** 解析一条日记；返回 null 表示这条不合法，应当跳过 */
function parseDailyLog(raw: Object | null): DailyLog | null {
  if (raw === null || raw === undefined) {
    return null;
  }
  const item: DailyLog = raw as DailyLog;
  const mood: number | null = safeMood(item.mood);
  if (mood === null) {
    return null;
  }
  const date: string | null = safeDate(item.date);
  if (date === null) {
    return null;
  }
  const createdAt: number = safeNumber(item.createdAt, 0);
  return {
    id: safeString(item.id, ''),
    date: date,
    mood: mood,
    customMood: safeString(item.customMood, ''),
    journal: safeString(item.journal, ''),
    plan: safeString(item.plan, ''),
    photoUris: safeStringArray(item.photoUris),
    // 标签是后加的字段：老备份没有它（空数组），类型不对也当空数组
    tags: safeTagArray(item.tags),
    // 老备份没有这个字段；那时候所有记录都是正常记录
    hasEntry: safeBoolean(item.hasEntry, true),
    createdAt: createdAt,
    updatedAt: safeNumber(item.updatedAt, createdAt)
  };
}

/** 解析一笔账；返回 null 表示这条不合法，应当跳过 */
function parseLedgerRecord(raw: Object | null): LedgerRecord | null {
  if (raw === null || raw === undefined) {
    return null;
  }
  const item: LedgerRecord = raw as LedgerRecord;
  const date: string | null = safeDate(item.date);
  if (date === null) {
    return null;
  }
  return {
    id: safeString(item.id, ''),
    date: date,
    type: safeNumber(item.type, LedgerType.EXPENSE) === LedgerType.INCOME
      ? LedgerType.INCOME
      : LedgerType.EXPENSE,
    amount: safeNumber(item.amount, 0),
    category: safeString(item.category, '其他'),
    note: safeString(item.note, ''),
    // 感受是后加的字段；老账目一律"未标记"
    feeling: safeNumber(item.feeling, LedgerFeeling.NONE),
    createdAt: safeNumber(item.createdAt, 0)
  };
}

/** 解析一个习惯；返回 null 表示这条不合法，应当跳过 */
function parseHabit(raw: Object | null): Habit | null {
  if (raw === null || raw === undefined) {
    return null;
  }
  const item: Habit = raw as Habit;
  const name: string = safeString(item.name, '').trim();
  if (name === '') {
    return null;
  }
  return {
    id: safeString(item.id, ''),
    name: name,
    sortOrder: safeNumber(item.sortOrder, 0),
    createdAt: safeNumber(item.createdAt, 0)
  };
}

/** 解析一条打卡；返回 null 表示这条不合法，应当跳过 */
function parseHabitCheck(raw: Object | null): HabitCheck | null {
  if (raw === null || raw === undefined) {
    return null;
  }
  const item: HabitCheck = raw as HabitCheck;
  const habitId: string = safeString(item.habitId, '');
  if (habitId === '') {
    return null;
  }
  const date: string | null = safeDate(item.date);
  if (date === null) {
    return null;
  }
  return {
    id: safeString(item.id, ''),
    habitId: habitId,
    date: date,
    createdAt: safeNumber(item.createdAt, 0)
  };
}

/** 解析一个任务规划；返回 null 表示这条不合法，应当跳过 */
function parseTaskPlan(raw: Object | null): TaskPlan | null {
  if (raw === null || raw === undefined) {
    return null;
  }
  const item: TaskPlan = raw as TaskPlan;
  const title: string = safeString(item.title, '').trim();
  if (title === '') {
    return null;
  }
  const startDate: string | null = safeDate(item.startDate);
  if (startDate === null) {
    return null;
  }
  return {
    id: safeString(item.id, ''),
    title: title,
    startDate: startDate,
    plannedDays: clampPlannedDays(safeNumber(item.plannedDays, 1)),
    completed: safeBoolean(item.completed, false),
    completedAt: safeNumber(item.completedAt, 0),
    createdAt: safeNumber(item.createdAt, 0)
  };
}

/** 解析一个重要日子；返回 null 表示这条不合法，应当跳过 */
function parseAnniversary(raw: Object | null): Anniversary | null {
  if (raw === null || raw === undefined) {
    return null;
  }
  const item: Anniversary = raw as Anniversary;
  const title: string = safeString(item.title, '').trim();
  if (title === '') {
    return null;
  }
  const date: string | null = safeDate(item.date);
  if (date === null) {
    return null;
  }
  return {
    id: safeString(item.id, ''),
    title: title,
    type: safeString(item.type, ''),
    date: date,
    reminderEnabled: safeBoolean(item.reminderEnabled, false),
    createdAt: safeNumber(item.createdAt, 0)
  };
}

/**
 * 解析并校验导出的 JSON。
 *
 * 任何非法输入都返回 ok=false 而不是抛异常；单条记录不合法只跳过这一条。
 */
export function parseImportJson(text: string): ImportResult {
  if (typeof text !== 'string' || text.trim() === '') {
    return failure('备份文件是空的');
  }

  let parsed: Object | null = null;
  try {
    parsed = JSON.parse(text) as Object;
  } catch (err) {
    return failure('文件内容不是有效的 JSON，可能不是备份文件');
  }
  if (parsed === null || typeof parsed !== 'object') {
    return failure('文件内容不是一个备份对象，可能不是备份文件');
  }

  const root: Record<string, Object> = parsed as Record<string, Object>;

  // 根对象的 app 字段就是"这是不是本应用导出的"的唯一凭据
  const app: string = safeString(root.app as string, '');
  if (app !== IMPORT_APP_NAME) {
    return failure('这不是心情手记的备份文件');
  }

  const counts: Map<string, number> = emptyCounts();

  const logsRaw: Array<Object> = root.dailyLogs as Array<Object>;
  const logs: DailyLog[] = [];
  if (Array.isArray(logsRaw)) {
    for (const raw of logsRaw) {
      const item: DailyLog | null = parseDailyLog(raw);
      if (item !== null) {
        logs.push(item);
      }
    }
  }

  const ledgerRaw: Array<Object> = root.ledgerRecords as Array<Object>;
  const ledger: LedgerRecord[] = [];
  if (Array.isArray(ledgerRaw)) {
    for (const raw of ledgerRaw) {
      const item: LedgerRecord | null = parseLedgerRecord(raw);
      if (item !== null) {
        ledger.push(item);
      }
    }
  }

  const habitsRaw: Array<Object> = root.habits as Array<Object>;
  const habits: Habit[] = [];
  if (Array.isArray(habitsRaw)) {
    for (const raw of habitsRaw) {
      const item: Habit | null = parseHabit(raw);
      if (item !== null) {
        habits.push(item);
      }
    }
  }

  const checksRaw: Array<Object> = root.habitChecks as Array<Object>;
  const checks: HabitCheck[] = [];
  if (Array.isArray(checksRaw)) {
    for (const raw of checksRaw) {
      const item: HabitCheck | null = parseHabitCheck(raw);
      if (item !== null) {
        checks.push(item);
      }
    }
  }

  const plansRaw: Array<Object> = root.taskPlans as Array<Object>;
  const plans: TaskPlan[] = [];
  if (Array.isArray(plansRaw)) {
    for (const raw of plansRaw) {
      const item: TaskPlan | null = parseTaskPlan(raw);
      if (item !== null) {
        plans.push(item);
      }
    }
  }

  const daysRaw: Array<Object> = root.importantDays as Array<Object>;
  const days: Anniversary[] = [];
  if (Array.isArray(daysRaw)) {
    for (const raw of daysRaw) {
      const item: Anniversary | null = parseAnniversary(raw);
      if (item !== null) {
        days.push(item);
      }
    }
  }

  counts.set(COUNT_DAILY_LOGS, logs.length);
  counts.set(COUNT_LEDGER_RECORDS, ledger.length);
  counts.set(COUNT_HABITS, habits.length);
  counts.set(COUNT_HABIT_CHECKS, checks.length);
  counts.set(COUNT_TASK_PLANS, plans.length);
  counts.set(COUNT_IMPORTANT_DAYS, days.length);

  const bundle: ImportBundle = {
    dailyLogs: logs,
    ledgerRecords: ledger,
    habits: habits,
    habitChecks: checks,
    taskPlans: plans,
    importantDays: days
  };
  return { ok: true, error: '', bundle: bundle, counts: counts };
}

/** 各类数据合计条数（用于"共 N 条"提示） */
export function totalCount(result: ImportResult): number {
  let total: number = 0;
  result.counts.forEach((value: number) => {
    total += value;
  });
  return total;
}

/** 把 counts 拼成「3 条记录、2 条账目」这样的一句话 */
export function describeCounts(result: ImportResult): string {
  const parts: string[] = [];
  for (const key of COUNT_KEYS) {
    const value: number = result.counts.get(key) ?? 0;
    if (value > 0) {
      parts.push(`${value} 条${countLabel(key)}`);
    }
  }
  return parts.length === 0 ? '没有任何数据' : parts.join('、');
}
