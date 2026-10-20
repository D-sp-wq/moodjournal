import { describe, it, expect } from '@ohos/hypium';
import {
  HABIT_WINDOW_DAYS,
  HabitDay,
  HabitProgress,
  MAX_HABITS,
  MAX_HABIT_NAME_LENGTH,
  buildHabitDays,
  computeHabitProgress,
  computeHabitStreak,
  groupChecksByHabit,
  normalizeHabitName,
  remainingHabitSlots
} from '../main/ets/models/Habit';

export default function habitTest() {
  describe('Habit', () => {
    it('normalize_name', 0, () => {
      expect(normalizeHabitName('  读书  ')).assertEqual('读书');
      expect(normalizeHabitName('   ')).assertEqual('');
      expect(normalizeHabitName('一二三四五六七八九十').length).assertEqual(MAX_HABIT_NAME_LENGTH);
    });

    it('remaining_slots', 0, () => {
      expect(MAX_HABITS).assertEqual(6);
      expect(remainingHabitSlots(0)).assertEqual(6);
      expect(remainingHabitSlots(5)).assertEqual(1);
      expect(remainingHabitSlots(6)).assertEqual(0);
      expect(remainingHabitSlots(9)).assertEqual(0);
    });

    it('streak_counts_backwards', 0, () => {
      expect(computeHabitStreak(['2026-10-08', '2026-10-09', '2026-10-10'], '2026-10-10')).assertEqual(3);
    });

    it('streak_uses_yesterday_when_today_missing', 0, () => {
      // 今天还没打卡，昨天建立的连续记录不该被清零
      expect(computeHabitStreak(['2026-10-08', '2026-10-09'], '2026-10-10')).assertEqual(2);
    });

    it('streak_breaks_on_gap', 0, () => {
      expect(computeHabitStreak(['2026-10-05', '2026-10-09', '2026-10-10'], '2026-10-10')).assertEqual(2);
    });

    it('streak_empty', 0, () => {
      expect(computeHabitStreak([], '2026-10-10')).assertEqual(0);
    });

    it('progress_window_and_rate', 0, () => {
      const p: HabitProgress = computeHabitProgress('h1', ['2026-10-10', '2026-10-09', '2026-10-01'],
        '2026-10-10', 10);
      expect(p.habitId).assertEqual('h1');
      expect(p.doneToday).assertTrue();
      expect(p.doneDays).assertEqual(3);
      expect(p.window).assertEqual(10);
      expect(p.rate).assertEqual(30);
    });

    it('progress_today_not_done', 0, () => {
      const p: HabitProgress = computeHabitProgress('h1', ['2026-10-09'], '2026-10-10', 7);
      expect(p.doneToday).assertFalse();
      expect(p.streak).assertEqual(1);
      expect(p.rate).assertEqual(Math.round(100 / 7));
    });

    it('window_defaults_to_30', 0, () => {
      expect(HABIT_WINDOW_DAYS).assertEqual(30);
      expect(computeHabitProgress('h1', [], '2026-10-10', 0).window).assertEqual(30);
    });

    it('habit_days_strip', 0, () => {
      const days: HabitDay[] = buildHabitDays(['2026-10-09'], '2026-10-10', 3);
      expect(days.length).assertEqual(3);
      expect(days[0].date).assertEqual('2026-10-08');
      expect(days[0].done).assertFalse();
      expect(days[1].done).assertTrue();
      expect(days[2].done).assertFalse();
    });

    it('group_checks_by_habit', 0, () => {
      const map: Map<string, string[]> = groupChecksByHabit([
        { id: 'c1', habitId: 'h1', date: '2026-10-10', createdAt: 0, slotIndex: 0 },
        { id: 'c2', habitId: 'h1', date: '2026-10-09', createdAt: 0, slotIndex: 0 },
        { id: 'c3', habitId: 'h2', date: '2026-10-10', createdAt: 0, slotIndex: 0 }
      ]);
      const h1: string[] | undefined = map.get('h1');
      const h2: string[] | undefined = map.get('h2');
      expect(h1 === undefined ? 0 : h1.length).assertEqual(2);
      expect(h2 === undefined ? 0 : h2.length).assertEqual(1);
      expect(map.get('h3') === undefined).assertTrue();
    });
  });
}
