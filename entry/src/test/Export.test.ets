import { describe, it, expect } from '@ohos/hypium';
import { buildExportJson, buildExportText } from '../main/ets/services/ExportService';
import {
  COUNT_DAILY_LOGS,
  COUNT_HABIT_CHECKS,
  COUNT_HABITS,
  COUNT_IMPORTANT_DAYS,
  COUNT_LEDGER_RECORDS,
  COUNT_TASK_PLANS,
  ImportResult,
  looksLikeTextExport,
  parseImportJson
} from '../main/ets/models/Import';
import { DailyLog, Mood } from '../main/ets/models/DailyLog';
import { LedgerFeeling, LedgerRecord, LedgerType } from '../main/ets/models/Ledger';
import { Habit, HabitCheck } from '../main/ets/models/Habit';
import { TaskPlan } from '../main/ets/models/TaskPlan';
import { Anniversary } from '../main/ets/models/Anniversary';

/**
 * 导出 ↔ 恢复 的闭环测试。
 *
 * 存在的理由很具体：应用市场审核反馈「导出的是 TXT，而恢复需要 JSON，导致无法恢复」。
 * 根因是导出侧**从来没有接线** JSON —— buildExportJson 写了却没有任何调用点，
 * 于是用户永远拿不到可恢复的备份文件。
 *
 * 所以这里最重要的一条不是"JSON 能序列化"，而是：
 *   **App 自己导出的 JSON，必须能被 App 自己的解析器读回来。**
 * 两侧只要有一处不匹配，这条用例就会红。
 */

// 注意：ArkTS 严格模式禁用 Object.assign（arkts-limited-stdlib），
// 所以固定数据一律显式构造，不用"基础对象 + 覆盖字段"的写法。
function logFixture(): DailyLog {
  return {
    id: 'L1',
    date: '2026-01-01',
    mood: Mood.SWEET,
    customMood: '',
    journal: '今天很好',
    plan: '明天继续',
    photoUris: [],
    tags: [],
    hasEntry: true,
    createdAt: 1,
    updatedAt: 2
  };
}

/** 带标签的记录（标签是 1.7.0 新增字段，往返里最容易丢） */
function logWithTags(): DailyLog {
  return {
    id: 'L1',
    date: '2026-01-01',
    mood: Mood.SWEET,
    customMood: '',
    journal: '今天很好',
    plan: '明天继续',
    photoUris: [],
    tags: ['工作', '家人'],
    hasEntry: true,
    createdAt: 1,
    updatedAt: 2
  };
}

/** 标签 + 照片都有的记录 */
function logWithTagsAndPhotos(): DailyLog {
  return {
    id: 'L1',
    date: '2026-01-01',
    mood: Mood.SWEET,
    customMood: '',
    journal: '今天很好',
    plan: '明天继续',
    photoUris: ['file://a.jpg'],
    tags: ['工作', '家人'],
    hasEntry: true,
    createdAt: 1,
    updatedAt: 2
  };
}

function ledgerFixture(): LedgerRecord {
  return {
    id: 'G1',
    date: '2026-01-01',
    type: LedgerType.EXPENSE,
    amount: 25.5,
    category: '餐饮',
    note: '午饭',
    feeling: LedgerFeeling.WORTH,
    createdAt: 3
  };
}

function habitFixture(): Habit {
  return {
    id: 'H1',
    name: '早起',
    sortOrder: 0,
    createdAt: 4,
    timesPerDay: 1,
    slotTimes: [],
    reminderEnabled: false
  };
}

function checkFixture(): HabitCheck {
  return { id: 'C1', habitId: 'H1', date: '2026-01-01', createdAt: 5, slotIndex: 0 };
}

function planFixture(): TaskPlan {
  return {
    id: 'P1',
    title: '读完一本书',
    startDate: '2026-01-01',
    plannedDays: 30,
    completed: false,
    completedAt: 0,
    createdAt: 6
  };
}

function dayFixture(): Anniversary {
  return {
    id: 'A1',
    title: '纪念日',
    type: 'anniversary',
    date: '2026-05-20',
    reminderEnabled: true,
    createdAt: 7
  };
}

/** 一份六类数据齐全的备份 */
function fullExportJson(): string {
  return buildExportJson(
    [logWithTagsAndPhotos()],
    [ledgerFixture()],
    [habitFixture()],
    [checkFixture()],
    [planFixture()],
    [dayFixture()]
  );
}

export default function exportBackupTest() {
  describe('ExportBackup', () => {

    // ── 闭环：导出 → 解析 ──────────────────────────────

    it('exported_json_can_be_parsed_back', 0, () => {
      // 这一条就是审核反馈的那个 bug 的守门用例
      const r: ImportResult = parseImportJson(fullExportJson());
      expect(r.ok).assertTrue();
      expect(r.error).assertEqual('');
    });

    it('roundtrip_keeps_every_category_count', 0, () => {
      const r: ImportResult = parseImportJson(fullExportJson());
      expect(r.ok).assertTrue();
      expect(r.counts.get(COUNT_DAILY_LOGS) ?? 0).assertEqual(1);
      expect(r.counts.get(COUNT_LEDGER_RECORDS) ?? 0).assertEqual(1);
      expect(r.counts.get(COUNT_HABITS) ?? 0).assertEqual(1);
      expect(r.counts.get(COUNT_HABIT_CHECKS) ?? 0).assertEqual(1);
      expect(r.counts.get(COUNT_TASK_PLANS) ?? 0).assertEqual(1);
      expect(r.counts.get(COUNT_IMPORTANT_DAYS) ?? 0).assertEqual(1);
    });

    it('roundtrip_keeps_log_fields', 0, () => {
      // 1.7.0 新增的 tags 是重点：往返里丢了它，恢复后标签就没了
      const r: ImportResult = parseImportJson(fullExportJson());
      expect(r.ok).assertTrue();
      expect(r.bundle.dailyLogs.length).assertEqual(1);
      const back: DailyLog = r.bundle.dailyLogs[0];
      expect(back.date).assertEqual('2026-01-01');
      expect(back.mood).assertEqual(Mood.SWEET);
      expect(back.journal).assertEqual('今天很好');
      expect(back.plan).assertEqual('明天继续');
      expect(back.hasEntry).assertTrue();
      expect(back.tags.length).assertEqual(2);
      expect(back.tags[0]).assertEqual('工作');
      expect(back.tags[1]).assertEqual('家人');
      expect(back.photoUris.length).assertEqual(1);
    });

    it('roundtrip_keeps_ledger_and_others', 0, () => {
      const r: ImportResult = parseImportJson(fullExportJson());
      expect(r.ok).assertTrue();
      expect(r.bundle.ledgerRecords[0].amount).assertEqual(25.5);
      expect(r.bundle.ledgerRecords[0].feeling).assertEqual(LedgerFeeling.WORTH);
      expect(r.bundle.habits[0].name).assertEqual('早起');
      expect(r.bundle.habitChecks[0].habitId).assertEqual('H1');
      expect(r.bundle.taskPlans[0].title).assertEqual('读完一本书');
      expect(r.bundle.importantDays[0].title).assertEqual('纪念日');
    });

    it('empty_export_still_parses', 0, () => {
      const r: ImportResult = parseImportJson(buildExportJson([], [], [], [], [], []));
      expect(r.ok).assertTrue();
      expect(r.bundle.dailyLogs.length).assertEqual(0);
    });

    // ── 安全：备份里不能出现应用锁凭据 ──────────────────

    it('export_contains_no_lock_credentials', 0, () => {
      // 4 位数字密码的哈希一旦进了明文备份，等于给出可离线暴力破解的材料。
      // 备份只应包含六类业务数据，本机设置（含应用锁）一律不导出。
      const json: string = fullExportJson();
      expect(json.indexOf('lockHash')).assertEqual(-1);
      expect(json.indexOf('lockSalt')).assertEqual(-1);
      expect(json.indexOf('lockEnabled')).assertEqual(-1);
      expect(json.indexOf('nickname')).assertEqual(-1);
    });

    // ── 文本导出 ───────────────────────────────────────

    it('text_export_has_all_sections', 0, () => {
      const text: string = buildExportText(
        [logWithTags()], [ledgerFixture()], [habitFixture()],
        [checkFixture()], [planFixture()], [dayFixture()]
      );
      expect(text.indexOf('心情手记 · 数据导出') >= 0).assertTrue();
      expect(text.indexOf('===== 每日记录') >= 0).assertTrue();
      expect(text.indexOf('===== 账本') >= 0).assertTrue();
      expect(text.indexOf('===== 习惯打卡') >= 0).assertTrue();
      expect(text.indexOf('===== 任务规划') >= 0).assertTrue();
      expect(text.indexOf('===== 重要日子') >= 0).assertTrue();
    });

    it('text_export_lists_tags', 0, () => {
      const text: string = buildExportText(
        [logWithTags()], [], [], [], [], []
      );
      expect(text.indexOf('标签：工作、家人') >= 0).assertTrue();
    });

    // ── 认错文件时的指引（审核场景）────────────────────

    it('detects_text_export_content', 0, () => {
      const text: string = buildExportText([logFixture()], [], [], [], [], []);
      expect(looksLikeTextExport(text)).assertTrue();
    });

    it('does_not_mistake_json_for_text_export', 0, () => {
      expect(looksLikeTextExport(fullExportJson())).assertFalse();
    });

    it('rejects_empty_and_random_text', 0, () => {
      expect(looksLikeTextExport('')).assertFalse();
      expect(looksLikeTextExport('随手记的一点东西')).assertFalse();
      // 只有标题、没有分区标题：不判为导出文件（避免误判）
      expect(looksLikeTextExport('心情手记 · 数据导出')).assertFalse();
    });

    it('parsing_text_export_gives_actionable_error', 0, () => {
      // 用户拿 TXT 导出文件来恢复时，必须告诉他去哪生成正确的备份，
      // 而不是笼统的"不是有效的 JSON"
      const text: string = buildExportText([logFixture()], [], [], [], [], []);
      const r: ImportResult = parseImportJson(text);
      expect(r.ok).assertFalse();
      expect(r.error.indexOf('可读文本') >= 0).assertTrue();
      expect(r.error.indexOf('备份文件（JSON）') >= 0).assertTrue();
    });
  });
}
