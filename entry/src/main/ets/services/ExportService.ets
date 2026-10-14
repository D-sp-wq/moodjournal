import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { DateUtils } from '../common/utils/DateUtils';
import { DailyLog, countChars, moodLabel } from '../models/DailyLog';
import { LedgerRecord, LedgerType, feelingLabel, formatAmount } from '../models/Ledger';
import { Habit, HabitCheck } from '../models/Habit';
import { TaskPlan } from '../models/TaskPlan';
import { Anniversary } from '../models/Anniversary';

/**
 * 数据导出。
 *
 * 所有数据本来就在本机，导出是"数据自主掌控"的最后一环：换机、留档、自己看。
 * 走系统文件选择器，**不申请任何权限**，也不经过网络。
 *
 * buildExportText / buildExportJson 是纯函数，可直接单元测试；
 * 只有 saveExport 会碰系统文件选择器。
 */

/** 一段可读的纯文本导出 */
export function buildExportText(
  logs: DailyLog[],
  ledger: LedgerRecord[],
  habits: Habit[],
  checks: HabitCheck[],
  plans: TaskPlan[],
  days: Anniversary[]
): string {
  const lines: string[] = [];
  lines.push('心情手记 · 数据导出');
  lines.push(`导出时间：${DateUtils.today()}`);
  lines.push('这些数据全部来自本机，未经过任何服务器。');
  lines.push('');

  lines.push(`===== 每日记录（${logs.length} 篇）=====`);
  if (logs.length === 0) {
    lines.push('（暂无记录）');
  }
  for (const item of logs) {
    lines.push('');
    lines.push(`【${item.date}】${moodLabel(item.mood, item.customMood)}`);
    if (item.journal.trim() !== '') {
      lines.push(`今天发生了什么：${item.journal.trim()}`);
    }
    if (item.plan.trim() !== '') {
      lines.push(`明天要做的事：${item.plan.trim()}`);
    }
    const tags: string[] = item.tags === undefined ? [] : item.tags;
    if (tags.length > 0) {
      lines.push(`标签：${tags.join('、')}`);
    }
    lines.push(`字数：${countChars(item)}${item.photoUris.length > 0 ? ` · 照片 ${item.photoUris.length} 张` : ''}`);
  }

  lines.push('');
  lines.push(`===== 账本（${ledger.length} 笔）=====`);
  if (ledger.length === 0) {
    lines.push('（暂无账目）');
  }
  for (const item of ledger) {
    const kind: string = item.type === LedgerType.INCOME ? '收入' : '支出';
    const feeling: string = item.type === LedgerType.EXPENSE ? ` · ${feelingLabel(item.feeling)}` : '';
    lines.push(`${item.date} ${kind} ${item.category} ${formatAmount(item.amount)} 元${feeling}`
      + (item.note.trim() === '' ? '' : ` · ${item.note.trim()}`));
  }

  lines.push('');
  lines.push(`===== 习惯打卡（${habits.length} 个习惯 / ${checks.length} 次打卡）=====`);
  if (habits.length === 0) {
    lines.push('（暂无习惯）');
  }
  for (const habit of habits) {
    const own: string[] = [];
    for (const check of checks) {
      if (check.habitId === habit.id) {
        own.push(check.date);
      }
    }
    own.sort();
    lines.push(`${habit.name}：${own.length} 次${own.length > 0 ? `（最近 ${own[own.length - 1]}）` : ''}`);
  }

  lines.push('');
  lines.push(`===== 任务规划（${plans.length} 个）=====`);
  if (plans.length === 0) {
    lines.push('（暂无任务）');
  }
  for (const plan of plans) {
    lines.push(`${plan.title} · 开始 ${plan.startDate} · 计划 ${plan.plannedDays} 天`);
  }

  lines.push('');
  lines.push(`===== 重要日子（${days.length} 个）=====`);
  if (days.length === 0) {
    lines.push('（暂无重要日子）');
  }
  for (const day of days) {
    lines.push(`${day.date} ${day.title}`);
  }

  lines.push('');
  return lines.join('\n');
}

/** 结构化导出，便于以后导入恢复或其他工具处理 */
export function buildExportJson(
  logs: DailyLog[],
  ledger: LedgerRecord[],
  habits: Habit[],
  checks: HabitCheck[],
  plans: TaskPlan[],
  days: Anniversary[]
): string {
  const root: ExportRoot = {
    app: '心情手记',
    bundleName: 'com.datelog.couple',
    exportedAt: DateUtils.today(),
    note: '数据仅来自本机，未经过任何服务器',
    dailyLogs: logs,
    ledgerRecords: ledger,
    habits: habits,
    habitChecks: checks,
    taskPlans: plans,
    importantDays: days
  };
  const text: string | undefined = JSON.stringify(root);
  return text === undefined ? '{}' : text;
}

interface ExportRoot {
  app: string;
  bundleName: string;
  exportedAt: string;
  note: string;
  dailyLogs: DailyLog[];
  ledgerRecords: LedgerRecord[];
  habits: Habit[];
  habitChecks: HabitCheck[];
  taskPlans: TaskPlan[];
  importantDays: Anniversary[];
}

/**
 * 弹出系统文件选择器让用户选保存位置并写入。
 * 返回 true 表示已保存；false 表示用户取消。
 */
export async function saveExport(context: common.Context, fileName: string, content: string): Promise<boolean> {
  const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
  options.newFileNames = [fileName];
  const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
  const uris: string[] = await documentPicker.save(options);
  if (uris.length === 0) {
    return false;
  }
  const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
  fileIo.writeSync(file.fd, content);
  fileIo.closeSync(file);
  return true;
}

/**
 * 弹出系统文件选择器让用户挑一个备份文件。
 *
 * 与 saveExport 对称：同样走系统选择器、同样零权限。
 * 返回选中的 URI；用户取消时返回空串（取消不是错误，不该弹错误提示）。
 */
export async function pickBackupFile(context: common.Context): Promise<string> {
  const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
  // 只让用户挑 JSON，减少"选错文件"的机会；手机端不支持该参数时系统会忽略它
  options.fileSuffixFilters = ['备份文件|.json'];
  options.maxSelectNumber = 1;
  const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
  try {
    const uris: string[] = await documentPicker.select(options);
    if (uris.length === 0) {
      return '';
    }
    return uris[0];
  } catch (err) {
    // 用户在系统选择器里点了返回，系统会抛异常，这里按"取消"处理
    return '';
  }
}

/**
 * 读出用户选中的备份文件内容。
 *
 * 注意：选择器给的是 URI（如 file://docs/storage/...），fileIo.readTextSync 只接受
 * 沙箱路径，因此必须先 openSync 拿到 fd 再按 fd 读 —— 这与 FileUtils.copyIntoDir
 * 里踩过的坑是同一个。
 *
 * 读失败（文件被删、不是文本等）会向上抛，交给调用方提示；这里刻意不吞异常，
 * 否则用户只会看到"导入失败"而不知道是文件的问题。
 */
export function readTextFromUri(uri: string): string {
  const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
  try {
    const size: number = fileIo.statSync(file.fd).size;
    if (size <= 0) {
      return '';
    }
    const buffer: ArrayBuffer = new ArrayBuffer(size);
    const readLen: number = fileIo.readSync(file.fd, buffer);
    const bytes: Uint8Array = new Uint8Array(buffer, 0, readLen);
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(bytes);
  } finally {
    fileIo.closeSync(file);
  }
}
