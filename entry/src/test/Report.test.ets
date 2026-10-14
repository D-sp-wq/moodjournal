import { describe, it, expect } from '@ohos/hypium';
import { StatsLog } from '../main/ets/models/Stats';
import {
  RangeReport,
  ReportDay,
  buildMonthlyReport,
  buildRangeReport,
  buildReportDays,
  buildWeeklyReport
} from '../main/ets/models/Report';

function rec(date: string, mood: string, chars: number): StatsLog {
  return { date: date, mood: mood, chars: chars };
}

export default function reportTest() {
  describe('Report', () => {
    it('empty_range_has_guide_summary', 0, () => {
      const r: RangeReport = buildWeeklyReport([], '2026-10-10');
      expect(r.days).assertEqual(7);
      expect(r.from).assertEqual('2026-10-04');
      expect(r.to).assertEqual('2026-10-10');
      expect(r.recordedDays).assertEqual(0);
      expect(r.entries).assertEqual(0);
      expect(r.summary.indexOf('还没有记录') >= 0).assertTrue();
    });

    it('counts_days_entries_and_chars', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-10-08', '开心', 100),
        rec('2026-10-09', '开心', 50),
        rec('2026-10-10', '低落', 30),
        rec('2026-09-01', '开心', 999) // 区间外，应被忽略
      ];
      const r: RangeReport = buildWeeklyReport(logs, '2026-10-10');
      expect(r.recordedDays).assertEqual(3);
      expect(r.entries).assertEqual(3);
      expect(r.chars).assertEqual(180);
      expect(r.avgChars).assertEqual(60);
      expect(r.topMood).assertEqual('开心');
      expect(r.busiestDate).assertEqual('2026-10-08');
    });

    it('moods_sorted_by_count_desc', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-10-06', '低落', 1),
        rec('2026-10-07', '开心', 1),
        rec('2026-10-08', '开心', 1),
        rec('2026-10-09', '开心', 1)
      ];
      const r: RangeReport = buildWeeklyReport(logs, '2026-10-10');
      expect(r.moods.length).assertEqual(2);
      expect(r.moods[0].label).assertEqual('开心');
      expect(r.moods[0].count).assertEqual(3);
      expect(r.moods[1].label).assertEqual('低落');
    });

    it('compares_with_previous_period', 0, () => {
      // 本周（10-04~10-10）记 3 天；上周（09-27~10-03）记 1 天 -> 多 2 天
      const logs: StatsLog[] = [
        rec('2026-10-05', '开心', 1),
        rec('2026-10-06', '开心', 1),
        rec('2026-10-07', '开心', 1),
        rec('2026-09-30', '平淡', 1)
      ];
      const r: RangeReport = buildWeeklyReport(logs, '2026-10-10');
      expect(r.recordedDays).assertEqual(3);
      expect(r.daysDelta).assertEqual(2);
      expect(r.summary.indexOf('多记了 2 天') >= 0).assertTrue();
    });

    it('negative_delta_reported', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-09-28', '开心', 1),
        rec('2026-09-29', '开心', 1),
        rec('2026-10-10', '开心', 1)
      ];
      const r: RangeReport = buildWeeklyReport(logs, '2026-10-10');
      expect(r.daysDelta).assertEqual(-1);
      expect(r.summary.indexOf('少记了 1 天') >= 0).assertTrue();
    });

    it('monthly_report_uses_30_days', 0, () => {
      const r: RangeReport = buildMonthlyReport([], '2026-10-30');
      expect(r.days).assertEqual(30);
      expect(r.from).assertEqual('2026-10-01');
    });

    it('range_crosses_month_boundary', 0, () => {
      const r: RangeReport = buildRangeReport([], '2026-03-03', 7);
      expect(r.from).assertEqual('2026-02-25');
      expect(r.to).assertEqual('2026-03-03');
    });

    it('report_days_strip_is_ascending', 0, () => {
      const logs: StatsLog[] = [rec('2026-10-08', '开心', 20)];
      const days: ReportDay[] = buildReportDays(logs, '2026-10-10', 5);
      expect(days.length).assertEqual(5);
      expect(days[0].date).assertEqual('2026-10-06');
      expect(days[4].date).assertEqual('2026-10-10');
      expect(days[2].mood).assertEqual('开心');
      expect(days[2].chars).assertEqual(20);
      expect(days[0].mood).assertEqual('');
    });
  });
}
