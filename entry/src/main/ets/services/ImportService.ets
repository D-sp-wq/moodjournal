import { common } from '@kit.AbilityKit';
import { DailyLog } from '../models/DailyLog';
import { LedgerRecord } from '../models/Ledger';
import { Habit, HabitCheck } from '../models/Habit';
import { TaskPlan } from '../models/TaskPlan';
import { Anniversary } from '../models/Anniversary';
import {
  ImportBundle,
  ImportResult,
  COUNT_DAILY_LOGS,
  COUNT_HABIT_CHECKS,
  COUNT_HABITS,
  COUNT_IMPORTANT_DAYS,
  COUNT_LEDGER_RECORDS,
  COUNT_TASK_PLANS,
  describeCounts,
  describeError,
  emptyImportResult,
  parseImportJson,
  totalCount
} from '../models/Import';
import { pickBackupFile, readTextFromUri } from './ExportService';
import { Repository } from './data/Repository';
import { RepositoryFactory } from './data/RepositoryFactory';

/**
 * 从备份恢复。
 *
 * 覆盖策略（先清空现有数据，再逐条写入备份内容）：
 *  - 界面上必须先有二次确认，且明确写出"会覆盖多少条现有数据、无法撤销"；
 *  - 这里只用 Repository 已有的 upsert / delete 方法，不加新接口、不写裸 SQL；
 *  - 任何一步失败都返回 ok=false + 中文原因，界面照实提示。
 *
 * 已知取舍：先清后写期间如果中断（进程被杀、磁盘写满），本机数据会是不完整的。
 * 之所以仍选"先清后写"：日记按 date 唯一天一条，若先写再清就会把刚恢复的同一天记录
 * 一起删掉。所以更要紧的是在确认弹窗里把风险说清楚，并建议用户先导出一次当前数据。
 */

/** 恢复结果，给界面直接显示 */
export interface RestoreOutcome {
  ok: boolean;
  message: string;
}

/** 各类现有数据的条数，用于二次确认文案里的 N / M */
export interface ExistingCounts {
  logs: number;
  ledger: number;
  habits: number;
  checks: number;
  plans: number;
  importantDays: number;
}

function outcome(ok: boolean, message: string): RestoreOutcome {
  return { ok: ok, message: message };
}

/**
 * 第一步：选文件 + 读取 + 解析校验。
 * 返回 null 表示用户取消了选择（不是错误，界面不用提示）。
 * 解析失败时 result.ok 为 false，error 是中文原因。
 */
export async function pickAndParseBackup(context: common.Context): Promise<ImportResult | null> {
  let uri: string = '';
  try {
    uri = await pickBackupFile(context);
  } catch (err) {
    return emptyImportResult('打开文件选择器失败，请重试');
  }
  if (uri === '') {
    return null;
  }

  let text: string = '';
  try {
    text = readTextFromUri(uri);
  } catch (err) {
    return emptyImportResult(`读取文件失败：${describeError(err)}`);
  }
  return parseImportJson(text);
}

/** 第二步：统计现有数据，供二次确认文案使用 */
export async function countExisting(): Promise<ExistingCounts> {
  const repo: Repository = RepositoryFactory.getRepository();
  const logs: DailyLog[] = await repo.getDailyLogs();
  const ledger: LedgerRecord[] = await repo.getLedgerRecords();
  const habits: Habit[] = await repo.getHabits();
  const checks: HabitCheck[] = await repo.getHabitChecks();
  const plans: TaskPlan[] = await repo.getTaskPlans();
  const days: Anniversary[] = await repo.getImportantDays();
  return {
    logs: logs.length,
    ledger: ledger.length,
    habits: habits.length,
    checks: checks.length,
    plans: plans.length,
    importantDays: days.length
  };
}

/** 把现有条数拼成确认文案里的一句：「12 篇记录 / 30 笔账目 / …」 */
export function describeExisting(counts: ExistingCounts): string {
  const parts: string[] = [];
  if (counts.logs > 0) {
    parts.push(`${counts.logs} 篇记录`);
  }
  if (counts.ledger > 0) {
    parts.push(`${counts.ledger} 笔账目`);
  }
  if (counts.habits > 0) {
    parts.push(`${counts.habits} 个习惯`);
  }
  if (counts.checks > 0) {
    parts.push(`${counts.checks} 次打卡`);
  }
  if (counts.plans > 0) {
    parts.push(`${counts.plans} 个任务`);
  }
  if (counts.importantDays > 0) {
    parts.push(`${counts.importantDays} 个重要日子`);
  }
  return parts.length === 0 ? '当前没有任何数据' : parts.join(' / ');
}

/** 第三步：清空现有数据 + 写入备份内容 */
export async function restoreFromBackup(bundle: ImportBundle): Promise<RestoreOutcome> {
  const repo: Repository = RepositoryFactory.getRepository();
  try {
    await clearAll(repo);
  } catch (err) {
    return outcome(false, `清空现有数据失败：${describeError(err)}`);
  }
  try {
    await writeAll(repo, bundle);
  } catch (err) {
    return outcome(false, `写入备份数据失败：${describeError(err)}。当前数据可能不完整，建议再导入一次`);
  }
  const written: ImportResult = {
    ok: true,
    error: '',
    bundle: bundle,
    counts: buildCounts(bundle)
  };
  return outcome(true, `已恢复 ${totalCount(written)} 条数据（${describeCounts(written)}）`);
}

/** 备份内容 → counts（写回完成后给用户看结果用） */
function buildCounts(bundle: ImportBundle): Map<string, number> {
  const counts: Map<string, number> = new Map();
  counts.set(COUNT_DAILY_LOGS, bundle.dailyLogs.length);
  counts.set(COUNT_LEDGER_RECORDS, bundle.ledgerRecords.length);
  counts.set(COUNT_HABITS, bundle.habits.length);
  counts.set(COUNT_HABIT_CHECKS, bundle.habitChecks.length);
  counts.set(COUNT_TASK_PLANS, bundle.taskPlans.length);
  counts.set(COUNT_IMPORTANT_DAYS, bundle.importantDays.length);
  return counts;
}

/**
 * 清空本机全部数据。
 * 只用 Repository 现有的查询 / 删除方法：打卡记录是「习惯+日期」联合定位的，
 * 没法按 id 删，所以必须先按 habitId + date 删干净，再删习惯本身。
 */
async function clearAll(repo: Repository): Promise<void> {
  const checks: HabitCheck[] = await repo.getHabitChecks();
  for (const check of checks) {
    await repo.deleteHabitCheck(check.habitId, check.date);
  }

  const logs: DailyLog[] = await repo.getDailyLogs();
  for (const log of logs) {
    await repo.deleteDailyLog(log.id);
  }

  const ledger: LedgerRecord[] = await repo.getLedgerRecords();
  for (const record of ledger) {
    await repo.deleteLedgerRecord(record.id);
  }

  const plans: TaskPlan[] = await repo.getTaskPlans();
  for (const plan of plans) {
    await repo.deleteTaskPlan(plan.id);
  }

  const habits: Habit[] = await repo.getHabits();
  for (const habit of habits) {
    await repo.deleteHabit(habit.id);
  }

  const days: Anniversary[] = await repo.getImportantDays();
  for (const day of days) {
    await repo.deleteImportantDay(day.id);
  }
}

/** 把备份内容逐条写回 */
async function writeAll(repo: Repository, bundle: ImportBundle): Promise<void> {
  // 习惯要先写：打卡记录通过 habitId 指向习惯
  const habitIds: string[] = [];
  for (const habit of bundle.habits) {
    await repo.upsertHabit(habit);
    habitIds.push(habit.id);
  }

  for (const log of bundle.dailyLogs) {
    await repo.upsertDailyLog(log);
  }

  for (const record of bundle.ledgerRecords) {
    await repo.upsertLedgerRecord(record);
  }

  for (const plan of bundle.taskPlans) {
    await repo.upsertTaskPlan(plan);
  }

  for (const day of bundle.importantDays) {
    await repo.upsertImportantDay(day);
  }

  for (const check of bundle.habitChecks) {
    // 备份里一个习惯都没有（比如只导出过日记）时照样写入，不做额外猜测
    if (bundle.habits.length === 0 || habitIds.indexOf(check.habitId) >= 0) {
      await repo.upsertHabitCheck(check);
    }
  }
}
