import { describe, it, expect } from '@ohos/hypium';
import {
  DayPlan,
  PlanReminderSettings,
  buildReminderPlan,
  formatTime,
  isValidTime,
  parseReminderIds,
  planReminderStatusLabel,
  reminderContent,
  serializeReminderIds,
  shouldPublish
} from '../main/ets/models/PlanReminder';

/**
 * 「今日提醒」纯函数测试。
 *
 * 全部数据都在用例里现构造，不读数据库、不读 preferences、不碰界面：
 * models/PlanReminder.ets 是纯函数模型，所以这些用例在任何环境下都能跑。
 */

/** 造一组「某天要做的事」；只有 date 与 plan 是用例关心的 */
function makePlans(): DayPlan[] {
  return [
    { date: '2026-10-20', plan: '买菜' },
    { date: '2026-10-21', plan: '   ' },
    { date: '2026-10-22', plan: '写周报\n取快递' },
    { date: '2026-10-23', plan: '' }
  ];
}

function makeSettings(enabled: boolean, hour: number, minute: number): PlanReminderSettings {
  return { enabled: enabled, hour: hour, minute: minute };
}

/** 数组拼成字符串再断言，避免依赖深比较 API */
function joined(values: string[]): string {
  return values.join('|');
}

/** 计划列表里的日期串 */
function datesOf(plans: DayPlan[]): string {
  const out: string[] = [];
  for (const item of plans) {
    out.push(item.date);
  }
  return joined(out);
}

/** 计划列表里的内容串 */
function plansOf(plans: DayPlan[]): string {
  const out: string[] = [];
  for (const item of plans) {
    out.push(item.plan);
  }
  return joined(out);
}

/** 数字列表拼串 */
function numbersOf(values: number[]): string {
  const out: string[] = [];
  for (const value of values) {
    out.push(`${value}`);
  }
  return joined(out);
}

export default function planReminderTest() {
  describe('PlanReminder', () => {
    // ---------------- formatTime ----------------

    it('format_time_pads_zero', 0, () => {
      expect(formatTime(9, 0)).assertEqual('09:00');
      expect(formatTime(0, 0)).assertEqual('00:00');
      expect(formatTime(0, 5)).assertEqual('00:05');
      expect(formatTime(7, 8)).assertEqual('07:08');
    });

    it('format_time_keeps_two_digit_values', 0, () => {
      expect(formatTime(12, 30)).assertEqual('12:30');
      expect(formatTime(23, 59)).assertEqual('23:59');
      expect(formatTime(10, 10)).assertEqual('10:10');
    });

    // ---------------- isValidTime ----------------

    it('valid_time_accepts_full_range', 0, () => {
      expect(isValidTime(0, 0)).assertTrue();
      expect(isValidTime(9, 0)).assertTrue();
      expect(isValidTime(23, 59)).assertTrue();
    });

    it('invalid_time_rejects_out_of_range', 0, () => {
      expect(isValidTime(-1, 0)).assertFalse();
      expect(isValidTime(24, 0)).assertFalse();
      expect(isValidTime(9, 60)).assertFalse();
      expect(isValidTime(9, -1)).assertFalse();
    });

    it('invalid_time_rejects_non_integer', 0, () => {
      expect(isValidTime(9.5, 0)).assertFalse();
      expect(isValidTime(9, 0.5)).assertFalse();
      expect(isValidTime(Number.NaN, 0)).assertFalse();
      expect(isValidTime(9, Number.NaN)).assertFalse();
    });

    // ---------------- reminderContent ----------------

    it('reminder_content_trims_whitespace', 0, () => {
      expect(reminderContent('  买菜  ', 10)).assertEqual('买菜');
      expect(reminderContent('\n\t写周报  ', 20)).assertEqual('写周报');
    });

    it('reminder_content_empty_returns_empty', 0, () => {
      expect(reminderContent('', 10)).assertEqual('');
      expect(reminderContent('   ', 10)).assertEqual('');
      expect(reminderContent('\n\t ', 10)).assertEqual('');
    });

    it('reminder_content_keeps_short_text', 0, () => {
      expect(reminderContent('买菜', 10)).assertEqual('买菜');
    });

    it('reminder_content_truncates_with_ellipsis', 0, () => {
      expect(reminderContent('一二三四五六', 4)).assertEqual('一二三四…');
      // 先 trim 再截断：前导空白不占名额
      expect(reminderContent('  一二三四五六', 4)).assertEqual('一二三四…');
    });

    it('reminder_content_keeps_text_at_exact_limit', 0, () => {
      expect(reminderContent('一二三四', 4)).assertEqual('一二三四');
      expect(reminderContent('一二三四', 4).length).assertEqual(4);
    });

    it('reminder_content_rejects_non_positive_limit', 0, () => {
      expect(reminderContent('买菜', 0)).assertEqual('');
      expect(reminderContent('买菜', -3)).assertEqual('');
    });

    // ---------------- buildReminderPlan ----------------

    it('build_plan_drops_blank_plans', 0, () => {
      const kept: DayPlan[] = buildReminderPlan(makePlans());
      expect(kept.length).assertEqual(2);
      expect(datesOf(kept)).assertEqual('2026-10-20|2026-10-22');
      expect(plansOf(kept)).assertEqual('买菜|写周报\n取快递');
    });

    it('build_plan_empty_input_returns_empty', 0, () => {
      expect(buildReminderPlan([]).length).assertEqual(0);
    });

    it('build_plan_all_blank_returns_empty', 0, () => {
      const all: DayPlan[] = [
        { date: '2026-10-20', plan: '' },
        { date: '2026-10-21', plan: '  ' },
        { date: '2026-10-22', plan: '\n\t' }
      ];
      expect(buildReminderPlan(all).length).assertEqual(0);
    });

    it('build_plan_keeps_order_and_trims_plans', 0, () => {
      const input: DayPlan[] = [
        { date: '2026-10-22', plan: '  第三  ' },
        { date: '2026-10-21', plan: '第二' },
        { date: '2026-10-20', plan: '第一' }
      ];
      const kept: DayPlan[] = buildReminderPlan(input);
      expect(kept.length).assertEqual(3);
      // 保持传入顺序，不改排序（排期顺序由调用方决定）
      expect(datesOf(kept)).assertEqual('2026-10-22|2026-10-21|2026-10-20');
      expect(plansOf(kept)).assertEqual('第三|第二|第一');
    });

    it('build_plan_keeps_multiline_plan', 0, () => {
      const kept: DayPlan[] = buildReminderPlan([{ date: '2026-10-22', plan: '  买菜\n取快递  ' }]);
      expect(kept.length).assertEqual(1);
      expect(kept[0].plan).assertEqual('买菜\n取快递');
    });

    // ---------------- shouldPublish：设置关闭时不应发布 ----------------

    it('disabled_settings_never_publish', 0, () => {
      // 有安排也不发：开关关着的时候，计划再多也不排提醒
      const plans: DayPlan[] = buildReminderPlan(makePlans());
      expect(plans.length).assertEqual(2);
      expect(shouldPublish(makeSettings(false, 9, 0))).assertFalse();
      expect(shouldPublish(makeSettings(false, 23, 59))).assertFalse();
    });

    it('enabled_settings_publish', 0, () => {
      expect(shouldPublish(makeSettings(true, 9, 0))).assertTrue();
      expect(shouldPublish(makeSettings(true, 0, 0))).assertTrue();
      expect(shouldPublish(makeSettings(true, 23, 59))).assertTrue();
    });

    it('invalid_time_never_publishes', 0, () => {
      // 开着但时间脏了（比如被写坏成 24:00）→ 一样不排，免得排到错误的时间
      expect(shouldPublish(makeSettings(true, 24, 0))).assertFalse();
      expect(shouldPublish(makeSettings(true, 9, 60))).assertFalse();
      expect(shouldPublish(makeSettings(true, 9.5, 0))).assertFalse();
    });

    // ---------------- 状态文案 ----------------

    it('status_label_shows_time_or_off', 0, () => {
      expect(planReminderStatusLabel(true, 9, 0)).assertEqual('09:00');
      expect(planReminderStatusLabel(true, 21, 5)).assertEqual('21:05');
      expect(planReminderStatusLabel(false, 9, 0)).assertEqual('已关闭');
      // 开着但时间非法 = 实际不会排期，也按"已关闭"显示
      expect(planReminderStatusLabel(true, 24, 0)).assertEqual('已关闭');
    });

    // ---------------- reminderId 存取的序列化 ----------------

    it('serialize_parse_ids_round_trip', 0, () => {
      const ids: number[] = [3001, 3002, 3003];
      const restored: number[] = parseReminderIds(serializeReminderIds(ids));
      expect(restored.length).assertEqual(3);
      expect(numbersOf(restored)).assertEqual('3001|3002|3003');
    });

    it('serialize_empty_ids_returns_empty_string', 0, () => {
      expect(serializeReminderIds([])).assertEqual('');
      expect(parseReminderIds('').length).assertEqual(0);
    });

    it('parse_ids_drops_dirty_items', 0, () => {
      const restored: number[] = parseReminderIds('[3001,"3002",3003.5,-1,null,3004]');
      expect(restored.length).assertEqual(2);
      expect(numbersOf(restored)).assertEqual('3001|3004');
    });

    it('parse_ids_broken_text_returns_empty', 0, () => {
      expect(parseReminderIds('不是 JSON').length).assertEqual(0);
      expect(parseReminderIds('{"a":1}').length).assertEqual(0);
    });
  });
}
