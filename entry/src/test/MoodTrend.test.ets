import { describe, it, expect } from '@ohos/hypium';
import { MoodTrend, StatsLog, TrendPoint, computeMoodTrend } from '../main/ets/models/Stats';
import { moodScoreByLabel } from '../main/ets/models/DailyLog';

export default function moodTrendTest() {
  describe('MoodTrend', () => {
    it('score_mapping', 0, () => {
      expect(moodScoreByLabel('开心')).assertEqual(5);
      expect(moodScoreByLabel('甜蜜')).assertEqual(5);
      expect(moodScoreByLabel('平淡')).assertEqual(3);
      expect(moodScoreByLabel('低落')).assertEqual(2);
      expect(moodScoreByLabel('生气')).assertEqual(1);
      // 自定义心情统一记 3
      expect(moodScoreByLabel('元气满满')).assertEqual(3);
    });

    it('fills_every_day_in_range', 0, () => {
      const logs: StatsLog[] = [{ date: '2026-10-10', mood: '开心', chars: 100 }];
      const trend: MoodTrend = computeMoodTrend(logs, '2026-10-10', 7);
      expect(trend.points.length).assertEqual(7);
      expect(trend.points[0].date).assertEqual('2026-10-04');
      expect(trend.points[0].score).assertEqual(0);
      expect(trend.points[6].date).assertEqual('2026-10-10');
      expect(trend.points[6].score).assertEqual(5);
      expect(trend.recordedDays).assertEqual(1);
      expect(trend.avgChars).assertEqual(100);
      expect(trend.topMood).assertEqual('开心');
    });

    it('top_mood_and_avg_chars', 0, () => {
      const logs: StatsLog[] = [
        { date: '2026-10-09', mood: '低落', chars: 10 },
        { date: '2026-10-10', mood: '低落', chars: 30 }
      ];
      const trend: MoodTrend = computeMoodTrend(logs, '2026-10-10', 3);
      expect(trend.recordedDays).assertEqual(2);
      expect(trend.topMood).assertEqual('低落');
      expect(trend.avgChars).assertEqual(20);
    });

    it('empty_logs', 0, () => {
      const trend: MoodTrend = computeMoodTrend([], '2026-10-10', 5);
      expect(trend.points.length).assertEqual(5);
      expect(trend.recordedDays).assertEqual(0);
      expect(trend.topMood).assertEqual('');
      expect(trend.avgChars).assertEqual(0);
    });

    it('ignores_records_outside_range', 0, () => {
      const logs: StatsLog[] = [{ date: '2026-01-01', mood: '开心', chars: 999 }];
      const trend: MoodTrend = computeMoodTrend(logs, '2026-10-10', 3);
      expect(trend.recordedDays).assertEqual(0);
      const first: TrendPoint = trend.points[0];
      expect(first.score).assertEqual(0);
    });
  });
}
