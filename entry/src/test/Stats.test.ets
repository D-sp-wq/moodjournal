import { describe, it, expect } from '@ohos/hypium';
import { computeStats, StatsLog, StatsResult } from '../main/ets/models/Stats';

export default function statsTest() {
  describe('Stats', () => {
    const today: string = '2026-10-08';
    // 2026-10-01 起，已使用 8 天
    const start: string = '2026-10-01';
    const logs: StatsLog[] = [
      { date: '2026-10-08', mood: '甜蜜', chars: 100 },
      { date: '2026-10-07', mood: '甜蜜', chars: 50 },
      { date: '2026-10-06', mood: '开心', chars: 30 },
      { date: '2026-10-01', mood: '开心', chars: 20 },
      { date: '2026-09-30', mood: '', chars: 0 }
    ];

    it('counts_and_rate', 0, () => {
      const r: StatsResult = computeStats(logs, start, today, 2, 3);
      expect(r.total).assertEqual(5);
      expect(r.activeDays).assertEqual(5);
      expect(r.recordDays).assertEqual(8);
      // 5 / 8 = 62.5% → 63
      expect(r.ratePercent).assertEqual(63);
      expect(r.totalChars).assertEqual(200);
      expect(r.importantCount).assertEqual(2);
      expect(r.photoCount).assertEqual(3);
    });

    it('streak_and_today', 0, () => {
      const r: StatsResult = computeStats(logs, start, today, 0, 0);
      // 10-06 / 10-07 / 10-08 连续 3 天
      expect(r.currentStreak).assertEqual(3);
      expect(r.bestStreak).assertEqual(3);
      expect(r.loggedToday).assertTrue();
    });

    it('same_day_multiple_logs', 0, () => {
      const dup: StatsLog[] = [
        { date: '2026-10-08', mood: '甜蜜', chars: 10 },
        { date: '2026-10-08', mood: '开心', chars: 20 }
      ];
      const r: StatsResult = computeStats(dup, start, today, 0, 0);
      // 总篇数按记录数，活跃天数按去重
      expect(r.total).assertEqual(2);
      expect(r.activeDays).assertEqual(1);
      expect(r.totalChars).assertEqual(30);
    });

    it('mood_distribution', 0, () => {
      const r: StatsResult = computeStats(logs, start, today, 0, 0);
      expect(r.moods.length).assertEqual(3);
      expect(r.moods[0].mood).assertEqual('甜蜜');
      expect(r.moods[0].count).assertEqual(2);
      expect(r.moods[0].percent).assertEqual(40);
      expect(r.moods[1].mood).assertEqual('开心');
      expect(r.moods[1].count).assertEqual(2);
      // 空心情归入「未记录」
      expect(r.moods[2].mood).assertEqual('未记录');
      expect(r.moods[2].percent).assertEqual(20);
    });

    it('recent_months', 0, () => {
      const r: StatsResult = computeStats(logs, start, today, 0, 0);
      expect(r.months.length).assertEqual(6);
      expect(r.months[5].label).assertEqual('10月');
      expect(r.months[5].count).assertEqual(4);
      expect(r.months[4].label).assertEqual('9月');
      expect(r.months[4].count).assertEqual(1);
      expect(r.months[0].count).assertEqual(0);
    });

    it('empty_logs', 0, () => {
      const r: StatsResult = computeStats([], start, today, 0, 0);
      expect(r.total).assertEqual(0);
      expect(r.activeDays).assertEqual(0);
      expect(r.ratePercent).assertEqual(0);
      expect(r.totalChars).assertEqual(0);
      expect(r.currentStreak).assertEqual(0);
      expect(r.bestStreak).assertEqual(0);
      expect(r.loggedToday).assertFalse();
      expect(r.moods.length).assertEqual(0);
      expect(r.months.length).assertEqual(6);
    });

    it('record_days_floor_one', 0, () => {
      // 起始日晚于今天时，已使用天数至少为 1
      const r: StatsResult = computeStats([], '2026-12-31', today, 0, 0);
      expect(r.recordDays).assertEqual(1);
    });

    it('logged_today_false_when_yesterday_only', 0, () => {
      const only: StatsLog[] = [{ date: '2026-10-07', mood: '平淡', chars: 5 }];
      const r: StatsResult = computeStats(only, start, today, 0, 0);
      expect(r.loggedToday).assertFalse();
      // 昨天记录过，连续天数仍为 1（computeStreak 会从昨天起算）
      expect(r.currentStreak).assertEqual(1);
    });
  });
}
