import { describe, it, expect } from '@ohos/hypium';
import {
  COUNT_DAILY_LOGS,
  COUNT_HABIT_CHECKS,
  COUNT_HABITS,
  COUNT_IMPORTANT_DAYS,
  COUNT_LEDGER_RECORDS,
  COUNT_TASK_PLANS,
  IMPORT_APP_NAME,
  ImportResult,
  countLabel,
  describeCounts,
  describeError,
  parseImportJson,
  totalCount
} from '../main/ets/models/Import';
import { LedgerFeeling, LedgerType } from '../main/ets/models/Ledger';

/**
 * 备份导入解析器测试。
 *
 * 全部输入都在测试里现构造成字符串，不读任何真实文件：
 * 解析器本来就是纯函数，测试也不该依赖文件系统。
 */

const HEAD: string = '{"app":"心情手记","bundleName":"com.datelog.couple","exportedAt":"2026-01-01"';

const ALL_ARRAY_KEYS: string[] = [
  'dailyLogs', 'ledgerRecords', 'habits', 'habitChecks', 'taskPlans', 'importantDays'
];

/**
 * 拼一份完整备份。
 * body 只写自己关心的数组字段，**没写到的**数组字段由这里补成空数组
 * （真实导出一定带全部数组字段）；已经在 body 里出现过的字段不会重复添加。
 */
function backup(body: string): string {
  const parts: string[] = [];
  if (body !== '') {
    parts.push(body);
  }
  for (const key of ALL_ARRAY_KEYS) {
    if (body.indexOf(`"${key}"`) < 0) {
      parts.push(`"${key}":[]`);
    }
  }
  return `${HEAD},${parts.join(',')}}`;
}

/** 一条字段齐全的日记 JSON */
function logJson(date: string): string {
  return `{"id":"L${date}","date":"${date}","mood":1,"customMood":"","journal":"今天很好",`
    + `"plan":"明天继续","photoUris":[],"hasEntry":true,"createdAt":1,"updatedAt":2}`;
}

export default function importTest() {
  describe('Import', () => {
    it('empty_text_is_rejected', 0, () => {
      const r: ImportResult = parseImportJson('');
      expect(r.ok).assertFalse();
      expect(r.error.length > 0).assertTrue();
    });

    it('blank_text_is_rejected', 0, () => {
      expect(parseImportJson('   \n\t  ').ok).assertFalse();
      expect(parseImportJson('   \n\t  ').error).assertContain('空');
    });

    it('broken_json_is_rejected', 0, () => {
      const r: ImportResult = parseImportJson('{"app":"心情手记",');
      expect(r.ok).assertFalse();
      expect(r.error).assertContain('JSON');
      expect(totalCount(r)).assertEqual(0);
    });

    it('json_primitive_is_rejected', 0, () => {
      const arr: ImportResult = parseImportJson('[1,2,3]');
      expect(arr.ok).assertFalse();
      expect(arr.error).assertContain('备份');
      expect(parseImportJson('123').ok).assertFalse();
      expect(parseImportJson('"心情手记"').ok).assertFalse();
      expect(parseImportJson('null').ok).assertFalse();
    });

    it('other_app_backup_is_rejected', 0, () => {
      const r: ImportResult = parseImportJson('{"app":"别的应用","dailyLogs":[]}');
      expect(r.ok).assertFalse();
      expect(r.error).assertContain('备份');
      expect(parseImportJson('{"dailyLogs":[]}').ok).assertFalse();
      expect(parseImportJson('{"dailyLogs":[]}').error).assertContain('备份');
    });

    it('missing_arrays_become_empty', 0, () => {
      const r: ImportResult = parseImportJson(backup(''));
      expect(r.ok).assertTrue();
      expect(r.error).assertEqual('');
      expect(r.bundle.dailyLogs.length).assertEqual(0);
      expect(r.bundle.ledgerRecords.length).assertEqual(0);
      expect(r.bundle.habits.length).assertEqual(0);
      expect(r.bundle.habitChecks.length).assertEqual(0);
      expect(r.bundle.taskPlans.length).assertEqual(0);
      expect(r.bundle.importantDays.length).assertEqual(0);
      expect(totalCount(r)).assertEqual(0);
      expect(describeCounts(r)).assertEqual('没有任何数据');
    });

    it('backup_with_only_app_field_is_ok', 0, () => {
      // 最精简的"本应用备份"：除 app 外一个数组字段都没有
      const r: ImportResult = parseImportJson('{"app":"心情手记"}');
      expect(r.ok).assertTrue();
      expect(totalCount(r)).assertEqual(0);
      expect(r.counts.get(COUNT_DAILY_LOGS)).assertEqual(0);
      expect(r.counts.get(COUNT_IMPORTANT_DAYS)).assertEqual(0);
    });

    it('arrays_of_wrong_type_become_empty', 0, () => {
      const r: ImportResult = parseImportJson(backup('"dailyLogs":"不是数组","ledgerRecords":123'));
      expect(r.ok).assertTrue();
      expect(r.bundle.dailyLogs.length).assertEqual(0);
      expect(r.bundle.ledgerRecords.length).assertEqual(0);
    });

    it('null_items_in_arrays_are_skipped', 0, () => {
      const body: string = `"dailyLogs":[null,${logJson('2026-05-01')},null],`
        + '"habits":[null,null],'
        + '"importantDays":[null,{"id":"d1","title":"生日","type":"birthday","date":"2026-02-01",'
        + '"reminderEnabled":true,"createdAt":1}]';
      const r: ImportResult = parseImportJson(backup(body));
      expect(r.ok).assertTrue();
      expect(r.counts.get(COUNT_DAILY_LOGS)).assertEqual(1);
      expect(r.counts.get(COUNT_HABITS)).assertEqual(0);
      expect(r.counts.get(COUNT_IMPORTANT_DAYS)).assertEqual(1);
      expect(r.bundle.dailyLogs[0].date).assertEqual('2026-05-01');
    });

    it('broken_log_is_skipped_others_kept', 0, () => {
      const body: string = `"dailyLogs":[${logJson('2026-05-01')},{"journal":"没有日期"},`
        + '{"date":"2026-05-02"},'
        + `{"date":"2026-05-03","mood":"开心"},`
        + `${logJson('2026-05-04')}]`;
      const r: ImportResult = parseImportJson(backup(body));
      expect(r.ok).assertTrue();
      // 无日期、无心情、心情类型不对的三条都被跳过，只留两条
      expect(r.counts.get(COUNT_DAILY_LOGS)).assertEqual(2);
      expect(r.bundle.dailyLogs[0].date).assertEqual('2026-05-01');
      expect(r.bundle.dailyLogs[1].date).assertEqual('2026-05-04');
    });

    it('illegal_date_log_is_skipped', 0, () => {
      const body: string = `"dailyLogs":[${logJson('2026-02-30')},${logJson('not a date')},`
        + `${logJson('2026-13-01')},${logJson('2026-1-1')},${logJson('2026-06-06')}]`;
      const r: ImportResult = parseImportJson(backup(body));
      expect(r.ok).assertTrue();
      expect(r.counts.get(COUNT_DAILY_LOGS)).assertEqual(1);
      expect(r.bundle.dailyLogs[0].date).assertEqual('2026-06-06');
    });

    it('old_log_without_has_entry_defaults_true', 0, () => {
      const body: string = '"dailyLogs":[{"id":"old","date":"2025-12-31","mood":2,'
        + '"journal":"","plan":"存根？","photoUris":[],"createdAt":1,"updatedAt":1}]';
      const r: ImportResult = parseImportJson(backup(body));
      expect(r.ok).assertTrue();
      expect(r.counts.get(COUNT_DAILY_LOGS)).assertEqual(1);
      expect(r.bundle.dailyLogs[0].hasEntry).assertTrue();
      // 缺失的字符串字段一律补空串，下游不用再判空
      expect(r.bundle.dailyLogs[0].customMood).assertEqual('');
      expect(r.bundle.dailyLogs[0].journal).assertEqual('');
      expect(r.bundle.dailyLogs[0].photoUris.length).assertEqual(0);
    });

    it('has_entry_false_is_kept', 0, () => {
      const body: string = '"dailyLogs":[{"id":"stub","date":"2026-07-01","mood":0,'
        + '"journal":"","plan":"给明天留的话","photoUris":[],"hasEntry":false,'
        + '"createdAt":1,"updatedAt":1}]';
      const r: ImportResult = parseImportJson(backup(body));
      expect(r.ok).assertTrue();
      expect(r.bundle.dailyLogs[0].hasEntry).assertFalse();
    });

    it('log_photo_uris_drops_non_string', 0, () => {
      const body: string = '"dailyLogs":[{"id":"p","date":"2026-05-05","mood":3,'
        + '"journal":"","plan":"","photoUris":["file:///a.jpg",3,"","file:///b.jpg",null],'
        + '"hasEntry":true,"createdAt":1,"updatedAt":1}]';
      const r: ImportResult = parseImportJson(backup(body));
      expect(r.ok).assertTrue();
      expect(r.bundle.dailyLogs[0].photoUris.length).assertEqual(2);
      expect(r.bundle.dailyLogs[0].photoUris[0]).assertEqual('file:///a.jpg');
      expect(r.bundle.dailyLogs[0].photoUris[1]).assertEqual('file:///b.jpg');
    });

    it('ledger_without_feeling_defaults_none', 0, () => {
      const body: string = '"ledgerRecords":[{"id":"g1","date":"2026-05-01","type":0,'
        + '"amount":12.5,"category":"餐饮","note":"午饭","createdAt":7}]';
      const r: ImportResult = parseImportJson(backup(body));
      expect(r.ok).assertTrue();
      expect(r.counts.get(COUNT_LEDGER_RECORDS)).assertEqual(1);
      expect(r.bundle.ledgerRecords[0].feeling).assertEqual(LedgerFeeling.NONE);
      expect(r.bundle.ledgerRecords[0].type).assertEqual(LedgerType.EXPENSE);
      expect(r.bundle.ledgerRecords[0].amount).assertEqual(12.5);
    });

    it('broken_ledger_is_skipped_others_kept', 0, () => {
      const body: string = '"ledgerRecords":[{"id":"a","date":"2026-05-01","type":0,"amount":10,'
        + '"category":"餐饮","note":"","feeling":1,"createdAt":1},'
        + '{"id":"b","type":0,"amount":10},'
        + '{"id":"c","date":"2026-05-32","type":0,"amount":10},'
        + 'null,'
        + '{"id":"d","date":"2026-05-02","type":1,"amount":100,"category":"工资","note":"",'
        + '"feeling":0,"createdAt":2}]';
      const r: ImportResult = parseImportJson(backup(body));
      expect(r.ok).assertTrue();
      expect(r.counts.get(COUNT_LEDGER_RECORDS)).assertEqual(2);
      expect(r.bundle.ledgerRecords[0].feeling).assertEqual(LedgerFeeling.WORTH);
      expect(r.bundle.ledgerRecords[1].type).assertEqual(LedgerType.INCOME);
    });

    it('broken_habits_and_checks_are_skipped', 0, () => {
      const body: string = '"habits":[{"id":"h1","name":"喝水","sortOrder":0,"createdAt":1},'
        + '{"id":"h2","name":"  "},{"name":"没有 id 也算"},null],'
        + '"habitChecks":[{"id":"c1","habitId":"h1","date":"2026-05-01","createdAt":1},'
        + '{"id":"c2","habitId":"","date":"2026-05-01"},'
        + '{"id":"c3","habitId":"h1","date":"昨天"},null]';
      const r: ImportResult = parseImportJson(backup(body));
      expect(r.ok).assertTrue();
      // 名字全空白的跳过；只有 name 的当成合法习惯
      expect(r.counts.get(COUNT_HABITS)).assertEqual(2);
      expect(r.bundle.habits[0].name).assertEqual('喝水');
      expect(r.counts.get(COUNT_HABIT_CHECKS)).assertEqual(1);
      expect(r.bundle.habitChecks[0].habitId).assertEqual('h1');
    });

    it('broken_plans_and_days_are_skipped', 0, () => {
      const body: string = '"taskPlans":[{"id":"t1","title":"读一本书","startDate":"2026-05-01",'
        + '"plannedDays":30,"completed":false,"completedAt":0,"createdAt":1},'
        + '{"id":"t2","startDate":"2026-05-01"},'
        + '{"id":"t3","title":"日期坏了","startDate":"2026-02-30"},null],'
        + '"importantDays":[{"id":"d1","title":"结婚纪念日","type":"anniversary","date":"2021-10-01",'
        + '"reminderEnabled":true,"createdAt":1},'
        + '{"id":"d2","title":"","date":"2021-10-01"},'
        + '{"id":"d3","title":"日期为空"},null]';
      const r: ImportResult = parseImportJson(backup(body));
      expect(r.ok).assertTrue();
      expect(r.counts.get(COUNT_TASK_PLANS)).assertEqual(1);
      expect(r.bundle.taskPlans[0].title).assertEqual('读一本书');
      expect(r.counts.get(COUNT_IMPORTANT_DAYS)).assertEqual(1);
      expect(r.bundle.importantDays[0].reminderEnabled).assertTrue();
    });

    it('counts_summary_and_labels', 0, () => {
      const body: string = `"dailyLogs":[${logJson('2026-05-01')},${logJson('2026-05-02')}],`
        + '"ledgerRecords":[{"id":"g1","date":"2026-05-01","type":0,"amount":1,"category":"餐饮",'
        + '"note":"","feeling":0,"createdAt":1}],'
        + '"habits":[{"id":"h1","name":"早睡","sortOrder":0,"createdAt":1}],'
        + '"habitChecks":[{"id":"c1","habitId":"h1","date":"2026-05-01","createdAt":1}]';
      const r: ImportResult = parseImportJson(backup(body));
      expect(r.ok).assertTrue();
      expect(r.counts.get(COUNT_DAILY_LOGS)).assertEqual(2);
      expect(r.counts.get(COUNT_LEDGER_RECORDS)).assertEqual(1);
      expect(r.counts.get(COUNT_HABITS)).assertEqual(1);
      expect(r.counts.get(COUNT_HABIT_CHECKS)).assertEqual(1);
      expect(r.counts.get(COUNT_TASK_PLANS)).assertEqual(0);
      expect(r.counts.get(COUNT_IMPORTANT_DAYS)).assertEqual(0);
      expect(totalCount(r)).assertEqual(5);
      expect(describeCounts(r)).assertEqual('2 条记录、1 条账目、1 条习惯、1 条打卡');
      expect(countLabel(COUNT_TASK_PLANS)).assertEqual('任务');
      expect(countLabel(COUNT_IMPORTANT_DAYS)).assertEqual('重要日子');
      expect(countLabel('unknown')).assertEqual('unknown');
      expect(IMPORT_APP_NAME).assertEqual('心情手记');
    });

    it('round_trip_with_export_shape', 0, () => {
      // 与 buildExportJson() 同形状的一段完整备份（含未标记感受的老账目）
      const text: string = '{"app":"心情手记","bundleName":"com.datelog.couple",'
        + '"exportedAt":"2026-06-01","note":"数据仅来自本机，未经过任何服务器",'
        + '"dailyLogs":[{"id":"L1","date":"2026-05-31","mood":6,"customMood":"平静",'
        + '"journal":"散步","plan":"","photoUris":["file:///p.jpg"],"hasEntry":true,'
        + '"createdAt":10,"updatedAt":20}],'
        + '"ledgerRecords":[],"habits":[],"habitChecks":[],"taskPlans":[],"importantDays":[]}';
      const r: ImportResult = parseImportJson(text);
      expect(r.ok).assertTrue();
      expect(totalCount(r)).assertEqual(1);
      expect(r.bundle.dailyLogs[0].mood).assertEqual(6);
      expect(r.bundle.dailyLogs[0].customMood).assertEqual('平静');
      expect(r.bundle.dailyLogs[0].photoUris.length).assertEqual(1);
      expect(r.bundle.dailyLogs[0].updatedAt).assertEqual(20);
    });

    it('describe_error_keeps_first_line_only', 0, () => {
      const err: Error = new Error('读取失败');
      expect(describeError(err)).assertContain('读取失败');
      expect(describeError(null)).assertEqual('');
    });
  });
}
