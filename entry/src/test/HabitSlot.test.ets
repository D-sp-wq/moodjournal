import { describe, it, expect } from '@ohos/hypium';
import {
  Habit,
  HabitCheck,
  HabitProgress,
  HabitReminderSlot,
  MAX_HABIT_TIMES,
  buildReminderSlots,
  computeHabitProgress,
  countDoneSlots,
  formatSlotTime,
  fullyDoneDates,
  groupChecksByHabit,
  isHabitFullyDone,
  isValidSlotTime,
  normalizeSlotTimes,
  normalizeTimesPerDay,
  parseSlotTimes,
  serializeSlotTimes
} from '../main/ets/models/Habit';

/** 测试用的习惯（timesPerDay / slotTimes / reminderEnabled 显式给全，避免依赖默认值） */
function makeHabit(id: string, name: string, timesPerDay: number, slotTimes: string[],
  reminderEnabled: boolean): Habit {
  return {
    id: id,
    name: name,
    sortOrder: 0,
    createdAt: 0,
    timesPerDay: timesPerDay,
    slotTimes: slotTimes,
    reminderEnabled: reminderEnabled
  };
}

function makeCheck(id: string, habitId: string, date: string, slotIndex: number): HabitCheck {
  return {
    id: id,
    habitId: habitId,
    date: date,
    createdAt: 0,
    slotIndex: slotIndex
  };
}

/** Map 里取某个习惯的日期列表；没有就当空数组，测试里少写判空 */
function datesOf(map: Map<string, string[]>, habitId: string): string[] {
  const list: string[] | undefined = map.get(habitId);
  return list === undefined ? [] : list;
}

export default function habitSlotTest() {
  describe('HabitSlot', () => {

    // ── normalizeTimesPerDay ──────────────────────────────

    it('normalize_times_clamps_out_of_range', 0, () => {
      expect(MAX_HABIT_TIMES).assertEqual(4);
      expect(normalizeTimesPerDay(0)).assertEqual(1);
      expect(normalizeTimesPerDay(-3)).assertEqual(1);
      expect(normalizeTimesPerDay(1)).assertEqual(1);
      expect(normalizeTimesPerDay(2)).assertEqual(2);
      expect(normalizeTimesPerDay(4)).assertEqual(4);
      expect(normalizeTimesPerDay(5)).assertEqual(4);
      expect(normalizeTimesPerDay(99)).assertEqual(4);
    });

    it('normalize_times_rejects_non_integer', 0, () => {
      expect(normalizeTimesPerDay(2.5)).assertEqual(1);
      expect(normalizeTimesPerDay(0.1)).assertEqual(1);
      expect(normalizeTimesPerDay(Number.NaN)).assertEqual(1);
      expect(normalizeTimesPerDay(Number.POSITIVE_INFINITY)).assertEqual(1);
    });

    // ── isValidSlotTime / formatSlotTime ──────────────────

    it('slot_time_accepts_boundaries', 0, () => {
      expect(isValidSlotTime('00:00')).assertTrue();
      expect(isValidSlotTime('23:59')).assertTrue();
      expect(isValidSlotTime('09:30')).assertTrue();
      expect(isValidSlotTime('12:00')).assertTrue();
    });

    it('slot_time_rejects_out_of_range', 0, () => {
      // 24:00 是非法的（一天最后一分钟是 23:59）
      expect(isValidSlotTime('24:00')).assertFalse();
      expect(isValidSlotTime('23:60')).assertFalse();
      expect(isValidSlotTime('99:99')).assertFalse();
      expect(isValidSlotTime('29:00')).assertFalse();
    });

    it('slot_time_rejects_bad_format', 0, () => {
      expect(isValidSlotTime('')).assertFalse();
      expect(isValidSlotTime('9:00')).assertFalse();
      expect(isValidSlotTime('09:0')).assertFalse();
      expect(isValidSlotTime('0900')).assertFalse();
      expect(isValidSlotTime('09-00')).assertFalse();
      expect(isValidSlotTime('09:00 ')).assertFalse();
      expect(isValidSlotTime('aa:bb')).assertFalse();
      // 全角数字/冒号也不算
      expect(isValidSlotTime('０９:００')).assertFalse();
    });

    it('format_slot_time_pads_to_two_digits', 0, () => {
      expect(formatSlotTime(0, 0)).assertEqual('00:00');
      expect(formatSlotTime(9, 5)).assertEqual('09:05');
      expect(formatSlotTime(12, 0)).assertEqual('12:00');
      expect(formatSlotTime(23, 59)).assertEqual('23:59');
    });

    // ── normalizeSlotTimes ────────────────────────────────

    it('normalize_slot_times_pads_missing_entries', 0, () => {
      const out: string[] = normalizeSlotTimes(3, ['08:00']);
      expect(out.length).assertEqual(3);
      expect(out[0]).assertEqual('08:00');
      expect(out[1]).assertEqual('');
      expect(out[2]).assertEqual('');
    });

    it('normalize_slot_times_truncates_extra_entries', 0, () => {
      const out: string[] = normalizeSlotTimes(1, ['08:00', '12:00', '18:00']);
      expect(out.length).assertEqual(1);
      expect(out[0]).assertEqual('08:00');
    });

    it('normalize_slot_times_blanks_invalid_entries', 0, () => {
      const out: string[] = normalizeSlotTimes(3, ['8:00', '23:59', '24:00']);
      expect(out.length).assertEqual(3);
      expect(out[0]).assertEqual('');
      expect(out[1]).assertEqual('23:59');
      expect(out[2]).assertEqual('');
    });

    it('normalize_slot_times_uses_normalized_count', 0, () => {
      // timesPerDay 脏了（0 或超过上限）也要产出合法长度
      expect(normalizeSlotTimes(0, ['08:00']).length).assertEqual(1);
      expect(normalizeSlotTimes(9, ['01:00', '02:00', '03:00', '04:00', '05:00']).length)
        .assertEqual(MAX_HABIT_TIMES);
    });

    // ── countDoneSlots / isHabitFullyDone ─────────────────

    it('count_done_slots_counts_distinct_slots', 0, () => {
      const checks: HabitCheck[] = [
        makeCheck('c1', 'h1', '2026-10-10', 0),
        makeCheck('c2', 'h1', '2026-10-10', 1),
        // 同一个时段重复记录（脏数据）只能算一次
        makeCheck('c3', 'h1', '2026-10-10', 1)
      ];
      expect(countDoneSlots(checks, 'h1', '2026-10-10', 2)).assertEqual(2);
      expect(countDoneSlots(checks, 'h1', '2026-10-10', 4)).assertEqual(2);
    });

    it('count_done_slots_ignores_out_of_range_and_other_scope', 0, () => {
      const checks: HabitCheck[] = [
        makeCheck('c1', 'h1', '2026-10-10', 0),
        // 超出 timesPerDay 的时段不算
        makeCheck('c2', 'h1', '2026-10-10', 2),
        // 负数时段不算
        makeCheck('c3', 'h1', '2026-10-10', -1),
        // 别的习惯 / 别的日期不算
        makeCheck('c4', 'h2', '2026-10-10', 1),
        makeCheck('c5', 'h1', '2026-10-09', 1)
      ];
      expect(countDoneSlots(checks, 'h1', '2026-10-10', 2)).assertEqual(1);
      expect(countDoneSlots(checks, 'h1', '2026-10-10', 3)).assertEqual(2);
      expect(countDoneSlots(checks, 'h1', '2026-10-09', 2)).assertEqual(1);
      expect(countDoneSlots(checks, 'h2', '2026-10-10', 2)).assertEqual(1);
    });

    it('fully_done_single_slot', 0, () => {
      const done: HabitCheck[] = [makeCheck('c1', 'h1', '2026-10-10', 0)];
      expect(isHabitFullyDone(done, 'h1', '2026-10-10', 1)).assertTrue();
      expect(isHabitFullyDone([], 'h1', '2026-10-10', 1)).assertFalse();
      expect(isHabitFullyDone(done, 'h1', '2026-10-11', 1)).assertFalse();
    });

    it('fully_done_multi_slots', 0, () => {
      const one: HabitCheck[] = [makeCheck('c1', 'h1', '2026-10-10', 0)];
      const two: HabitCheck[] = [
        makeCheck('c1', 'h1', '2026-10-10', 0),
        makeCheck('c2', 'h1', '2026-10-10', 1)
      ];
      expect(isHabitFullyDone(one, 'h1', '2026-10-10', 2)).assertFalse();
      expect(isHabitFullyDone(two, 'h1', '2026-10-10', 2)).assertTrue();
    });

    it('fully_done_ignores_extra_slots', 0, () => {
      // 一天 1 次，但记录里有个 slotIndex=1 的脏数据：不能算「已完成」
      const checks: HabitCheck[] = [makeCheck('c1', 'h1', '2026-10-10', 1)];
      expect(isHabitFullyDone(checks, 'h1', '2026-10-10', 1)).assertFalse();
      expect(isHabitFullyDone(checks, 'h1', '2026-10-10', 2)).assertFalse();
    });

    // ── fullyDoneDates ────────────────────────────────────

    it('fully_done_dates_single_time_matches_old_semantics', 0, () => {
      const habits: Habit[] = [makeHabit('h1', '读书', 1, [], false)];
      const checks: HabitCheck[] = [
        makeCheck('c1', 'h1', '2026-10-10', 0),
        makeCheck('c2', 'h1', '2026-10-09', 0),
        makeCheck('c3', 'h1', '2026-10-01', 0),
        // 越界时段不影响「一天一次」的判定
        makeCheck('c4', 'h1', '2026-10-02', 3)
      ];
      const dates: string[] = datesOf(fullyDoneDates(habits, checks), 'h1');
      expect(dates.length).assertEqual(3);
      expect(dates.indexOf('2026-10-10') >= 0).assertTrue();
      expect(dates.indexOf('2026-10-09') >= 0).assertTrue();
      expect(dates.indexOf('2026-10-01') >= 0).assertTrue();
      expect(dates.indexOf('2026-10-02')).assertEqual(-1);
      // 与旧的「按 habitId 分组日期」语义逐日一致
      const legacy: string[] | undefined = groupChecksByHabit(
        checks.filter((item: HabitCheck) => item.slotIndex === 0)).get('h1');
      const legacyDates: string[] = legacy === undefined ? [] : legacy;
      expect(legacyDates.length).assertEqual(dates.length);
    });

    it('fully_done_dates_multi_time_only_full_days', 0, () => {
      const habits: Habit[] = [makeHabit('h1', '喝水', 2, ['08:00', '20:00'], false)];
      const checks: HabitCheck[] = [
        // 两天都只完成了 1 次 → 都不算完成
        makeCheck('c1', 'h1', '2026-10-09', 0),
        // 这一天两次都完成 → 算
        makeCheck('c2', 'h1', '2026-10-10', 0),
        makeCheck('c3', 'h1', '2026-10-10', 1),
        // 越界时段不算，所以这天仍不完整
        makeCheck('c4', 'h1', '2026-10-08', 0),
        makeCheck('c5', 'h1', '2026-10-08', 2)
      ];
      const dates: string[] = datesOf(fullyDoneDates(habits, checks), 'h1');
      expect(dates.length).assertEqual(1);
      expect(dates[0]).assertEqual('2026-10-10');
    });

    it('fully_done_dates_ignores_unknown_and_empty_habits', 0, () => {
      const habits: Habit[] = [
        makeHabit('h1', '读书', 1, [], false),
        makeHabit('h2', '喝水', 1, [], false)
      ];
      const checks: HabitCheck[] = [
        makeCheck('c1', 'h1', '2026-10-10', 0),
        // 习惯已删除后残留的记录：忽略，不能凭空多出一个 key
        makeCheck('c2', 'ghost', '2026-10-10', 0)
      ];
      const map: Map<string, string[]> = fullyDoneDates(habits, checks);
      expect(datesOf(map, 'h1').length).assertEqual(1);
      expect(datesOf(map, 'h2').length).assertEqual(0);
      expect(map.get('ghost') === undefined).assertTrue();
    });

    // ── buildReminderSlots ────────────────────────────────

    it('build_reminder_slots_only_enabled_habits', 0, () => {
      const habits: Habit[] = [
        makeHabit('h1', '读书', 1, ['08:00'], true),
        makeHabit('h2', '喝水', 1, ['08:00'], false)
      ];
      const slots: HabitReminderSlot[] = buildReminderSlots(habits);
      expect(slots.length).assertEqual(1);
      expect(slots[0].habitId).assertEqual('h1');
      expect(slots[0].name).assertEqual('读书');
      expect(slots[0].slotIndex).assertEqual(0);
      expect(slots[0].hour).assertEqual(8);
      expect(slots[0].minute).assertEqual(0);
      expect(slots[0].total).assertEqual(1);
    });

    it('build_reminder_slots_skips_invalid_times', 0, () => {
      const habits: Habit[] = [
        makeHabit('h1', '喝水', 3, ['8:00', '23:59', '24:00'], true)
      ];
      const slots: HabitReminderSlot[] = buildReminderSlots(habits);
      expect(slots.length).assertEqual(1);
      expect(slots[0].slotIndex).assertEqual(1);
      expect(slots[0].hour).assertEqual(23);
      expect(slots[0].minute).assertEqual(59);
    });

    it('build_reminder_slots_dedupes_same_time_same_habit', 0, () => {
      // 同一习惯两个时段设成同一时刻：只排一条（弹两次没有意义）
      const habits: Habit[] = [
        makeHabit('h1', '读书', 2, ['08:00', '08:00'], true)
      ];
      const slots: HabitReminderSlot[] = buildReminderSlots(habits);
      expect(slots.length).assertEqual(1);
      expect(slots[0].slotIndex).assertEqual(0);
      // 文案里的总数仍然是 2
      expect(slots[0].total).assertEqual(2);
    });

    it('build_reminder_slots_keeps_same_time_for_different_habits', 0, () => {
      const habits: Habit[] = [
        makeHabit('h1', '读书', 1, ['08:00'], true),
        makeHabit('h2', '喝水', 1, ['08:00'], true)
      ];
      const slots: HabitReminderSlot[] = buildReminderSlots(habits);
      expect(slots.length).assertEqual(2);
      expect(slots[0].habitId).assertEqual('h1');
      expect(slots[1].habitId).assertEqual('h2');
    });

    it('build_reminder_slots_ignores_slots_beyond_times_per_day', 0, () => {
      // slotTimes 比 timesPerDay 长（脏数据/改少了次数）：多出来的时段不能排
      const habits: Habit[] = [
        makeHabit('h1', '读书', 1, ['08:00', '12:00'], true)
      ];
      const slots: HabitReminderSlot[] = buildReminderSlots(habits);
      expect(slots.length).assertEqual(1);
      expect(slots[0].slotIndex).assertEqual(0);
      expect(slots[0].hour).assertEqual(8);
    });

    it('build_reminder_slots_empty_input', 0, () => {
      expect(buildReminderSlots([]).length).assertEqual(0);
      expect(buildReminderSlots([makeHabit('h1', '读书', 2, ['08:00', '20:00'], false)]).length)
        .assertEqual(0);
    });

    // ── 兼容性守门：timesPerDay=1 时统计结果与旧语义一致 ──

    it('compat_single_time_progress_matches_date_array', 0, () => {
      const habits: Habit[] = [makeHabit('h1', '读书', 1, [], false)];
      const checks: HabitCheck[] = [
        makeCheck('c1', 'h1', '2026-10-10', 0),
        makeCheck('c2', 'h1', '2026-10-09', 0),
        makeCheck('c3', 'h1', '2026-10-01', 0)
      ];
      const dates: string[] = datesOf(fullyDoneDates(habits, checks), 'h1');
      const viaSlots: HabitProgress = computeHabitProgress('h1', dates, '2026-10-10', 10);
      const viaDates: HabitProgress = computeHabitProgress('h1',
        ['2026-10-10', '2026-10-09', '2026-10-01'], '2026-10-10', 10);
      // 逐字段一致：这就是「多时段折算不能改变单次习惯语义」的守门断言
      expect(viaSlots.doneToday).assertEqual(viaDates.doneToday);
      expect(viaSlots.streak).assertEqual(viaDates.streak);
      expect(viaSlots.doneDays).assertEqual(viaDates.doneDays);
      expect(viaSlots.rate).assertEqual(viaDates.rate);
      expect(viaSlots.window).assertEqual(viaDates.window);
      // 值本身也确认一下，避免两边都算错还相等
      expect(viaSlots.doneToday).assertTrue();
      expect(viaSlots.doneDays).assertEqual(3);
      expect(viaSlots.rate).assertEqual(30);
    });

    // ── 时段存库的序列化 / 反序列化 ───────────────────────

    it('slot_times_round_trip', 0, () => {
      const times: string[] = ['08:00', '', '20:30'];
      const raw: string = serializeSlotTimes(times);
      const back: string[] = parseSlotTimes(raw);
      expect(back.length).assertEqual(3);
      expect(back[0]).assertEqual('08:00');
      expect(back[1]).assertEqual('');
      expect(back[2]).assertEqual('20:30');
      expect(serializeSlotTimes([])).assertEqual('');
    });

    it('parse_slot_times_keeps_positions', 0, () => {
      // 非法项补空串而不是丢掉，否则后面的时间会整体前移
      const back: string[] = parseSlotTimes('["08:00", 3, null, "20:00"]');
      expect(back.length).assertEqual(4);
      expect(back[0]).assertEqual('08:00');
      expect(back[1]).assertEqual('');
      expect(back[2]).assertEqual('');
      expect(back[3]).assertEqual('20:00');
    });

    it('parse_slot_times_broken_text_returns_empty', 0, () => {
      expect(parseSlotTimes('').length).assertEqual(0);
      expect(parseSlotTimes('oops').length).assertEqual(0);
      expect(parseSlotTimes('{"a":1}').length).assertEqual(0);
    });
  });
}
