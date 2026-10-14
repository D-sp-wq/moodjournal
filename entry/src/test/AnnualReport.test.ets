import { describe, it, expect } from '@ohos/hypium';
import { StatsLog } from '../main/ets/models/Stats';
import { AnnualMonth, AnnualReport, availableYears, buildAnnualReport, longestStreakOf } from '../main/ets/models/AnnualReport';

/** 造一条"真记录"（hasEntry = true，等价于 DailyLog.hasEntry 为真） */
function rec(date: string, mood: string, chars: number): StatsLog {
  return { date: date, mood: mood, chars: chars, hasEntry: true };
}

/** 造一条计划存根：只安排了计划，不算真正记录过 */
function stub(date: string, mood: string, chars: number): StatsLog {
  return { date: date, mood: mood, chars: chars, hasEntry: false };
}

/** 取某个月的逐月统计（month 为 1-12） */
function monthOf(report: AnnualReport, month: number): AnnualMonth {
  return report.months[month - 1];
}

/** 数组里是否含某个年份 */
function hasYear(years: number[], year: number): boolean {
  return years.indexOf(year) >= 0;
}

/**
 * 年度报告测试。
 *
 * 全部用例自己构造 StatsLog[]，不读文件系统、不碰数据库。
 */
export default function annualReportTest() {
  describe('AnnualReport', () => {
    it('substring_prefix_filter_actually_matches', 0, () => {
      // 回归用例：年初这条过滤曾经全灭。
      // 实测 ArkTS 运行时里 `'2026-01-01'.slice(0, 4) === '2026'` 为 false
      // （charCodeAt / length 都对，但 === 不成立），导致所有记录都进不了自然年。
      // 现在 inYear 用 substring 判定，这一条用例守住"一条普通记录必须被算进去"。
      const logs: StatsLog[] = [rec('2026-01-01', '开心', 10)];
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(r.year).assertEqual(2026);
      expect(r.recordedDays).assertEqual(1);
      expect(r.entries).assertEqual(1);
      expect(r.chars).assertEqual(10);
      expect(r.firstDate).assertEqual('2026-01-01');
      expect(r.lastDate).assertEqual('2026-01-01');
    });

    it('empty_year_is_all_zero_with_guide_summary', 0, () => {
      const r: AnnualReport = buildAnnualReport([], 2026);
      expect(r.year).assertEqual(2026);
      expect(r.recordedDays).assertEqual(0);
      expect(r.entries).assertEqual(0);
      expect(r.chars).assertEqual(0);
      expect(r.avgChars).assertEqual(0);
      expect(r.topMood).assertEqual('');
      expect(r.moodCounts.length).assertEqual(0);
      expect(r.busiestMonth).assertEqual(0);
      expect(r.longestStreak).assertEqual(0);
      expect(r.firstDate).assertEqual('');
      expect(r.lastDate).assertEqual('');
      // 没有记录也要有 12 个月，值为 0
      expect(r.months.length).assertEqual(12);
      expect(monthOf(r, 1).recordedDays).assertEqual(0);
      expect(monthOf(r, 12).chars).assertEqual(0);
      expect(r.summary.indexOf('还没有记录') >= 0).assertTrue();
    });

    it('counts_days_entries_chars_and_top_mood', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-01-01', '开心', 100),
        rec('2026-01-02', '开心', 50),
        rec('2026-03-15', '低落', 30),
        rec('2026-12-31', '开心', 20)
      ];
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(r.recordedDays).assertEqual(4);
      expect(r.entries).assertEqual(4);
      expect(r.chars).assertEqual(200);
      expect(r.avgChars).assertEqual(50);
      expect(r.topMood).assertEqual('开心');
      expect(r.moodCounts.length).assertEqual(2);
      expect(r.moodCounts[0].label).assertEqual('开心');
      expect(r.moodCounts[0].count).assertEqual(3);
      expect(r.firstDate).assertEqual('2026-01-01');
      expect(r.lastDate).assertEqual('2026-12-31');
    });

    it('same_day_multiple_entries_count_one_day', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-05-05', '开心', 10),
        rec('2026-05-05', '平淡', 20)
      ];
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(r.recordedDays).assertEqual(1);
      expect(r.entries).assertEqual(2);
      expect(r.chars).assertEqual(30);
      expect(monthOf(r, 5).recordedDays).assertEqual(1);
      expect(monthOf(r, 5).chars).assertEqual(30);
    });

    it('skips_plan_stubs_with_hasEntry_false', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-06-01', '开心', 100),
        stub('2026-06-02', '平淡', 999)
      ];
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(r.recordedDays).assertEqual(1);
      expect(r.entries).assertEqual(1);
      expect(r.chars).assertEqual(100);
      expect(r.topMood).assertEqual('开心');
      expect(monthOf(r, 6).recordedDays).assertEqual(1);
      expect(monthOf(r, 6).chars).assertEqual(100);
      expect(r.lastDate).assertEqual('2026-06-01');
    });

    it('stub_only_year_looks_empty', 0, () => {
      const logs: StatsLog[] = [
        stub('2026-07-01', '平淡', 50),
        stub('2026-07-02', '平淡', 50)
      ];
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(r.recordedDays).assertEqual(0);
      expect(r.entries).assertEqual(0);
      expect(r.moodCounts.length).assertEqual(0);
      expect(r.summary.indexOf('还没有记录') >= 0).assertTrue();
    });

    it('stub_does_not_extend_longest_streak', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-04-01', '开心', 1),
        rec('2026-04-02', '开心', 1),
        // 4/3 是计划存根，不应该把连续天数接到 3
        stub('2026-04-03', '平淡', 1),
        rec('2026-04-04', '开心', 1)
      ];
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(r.longestStreak).assertEqual(2);
    });

    it('ignores_records_from_other_years', 0, () => {
      const logs: StatsLog[] = [
        rec('2025-12-31', '低落', 500),
        rec('2026-02-01', '开心', 10),
        rec('2026-02-02', '开心', 20),
        rec('2027-01-01', '生气', 700)
      ];
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(r.recordedDays).assertEqual(2);
      expect(r.entries).assertEqual(2);
      expect(r.chars).assertEqual(30);
      expect(r.topMood).assertEqual('开心');
      expect(r.firstDate).assertEqual('2026-02-01');
      expect(r.lastDate).assertEqual('2026-02-02');
      // 2025-12-31 与 2027-01-01 绝不能混进来
      expect(r.moodCounts.length).assertEqual(1);
      expect(monthOf(r, 12).recordedDays).assertEqual(0);
      expect(monthOf(r, 1).recordedDays).assertEqual(0);
    });

    it('months_distribute_per_month', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-01-05', '开心', 10),
        rec('2026-01-06', '开心', 20),
        rec('2026-12-24', '甜蜜', 30)
      ];
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(r.months.length).assertEqual(12);
      expect(monthOf(r, 1).month).assertEqual(1);
      expect(monthOf(r, 1).recordedDays).assertEqual(2);
      expect(monthOf(r, 1).chars).assertEqual(30);
      expect(monthOf(r, 2).recordedDays).assertEqual(0);
      expect(monthOf(r, 11).recordedDays).assertEqual(0);
      expect(monthOf(r, 12).month).assertEqual(12);
      expect(monthOf(r, 12).recordedDays).assertEqual(1);
      expect(monthOf(r, 12).chars).assertEqual(30);
    });

    it('busiest_month_picks_most_recorded_days', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-01-01', '开心', 1),
        rec('2026-03-01', '开心', 1),
        rec('2026-03-02', '开心', 1),
        rec('2026-03-03', '开心', 1),
        rec('2026-08-01', '开心', 1),
        rec('2026-08-02', '开心', 1)
      ];
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(r.busiestMonth).assertEqual(3);
    });

    it('busiest_month_tie_takes_smaller_month', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-09-01', '开心', 1),
        rec('2026-09-02', '开心', 1),
        rec('2026-02-01', '开心', 1),
        rec('2026-02-02', '开心', 1)
      ];
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(monthOf(r, 9).recordedDays).assertEqual(2);
      expect(monthOf(r, 2).recordedDays).assertEqual(2);
      expect(r.busiestMonth).assertEqual(2);
    });

    it('mood_tie_sorted_by_label_ascending', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-01-01', '开心', 1),
        rec('2026-01-02', '低落', 1),
        rec('2026-01-03', '平淡', 1),
        rec('2026-01-04', '甜蜜', 1)
      ];
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(r.moodCounts.length).assertEqual(4);
      for (const item of r.moodCounts) {
        expect(item.count).assertEqual(1);
      }
      // 次数相同时按名称升序，顺序稳定可测
      expect(r.moodCounts[0].label < r.moodCounts[1].label).assertTrue();
      expect(r.moodCounts[1].label < r.moodCounts[2].label).assertTrue();
      expect(r.moodCounts[2].label < r.moodCounts[3].label).assertTrue();
      expect(r.topMood).assertEqual(r.moodCounts[0].label);
    });

    it('mood_counts_desc_when_counts_differ', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-01-01', '低落', 1),
        rec('2026-01-02', '开心', 1),
        rec('2026-01-03', '开心', 1),
        rec('2026-01-04', '开心', 1)
      ];
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(r.moodCounts[0].label).assertEqual('开心');
      expect(r.moodCounts[0].count).assertEqual(3);
      expect(r.moodCounts[1].label).assertEqual('低落');
      expect(r.topMood).assertEqual('开心');
    });

    it('records_without_mood_still_count_days', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-01-01', '', 10),
        rec('2026-01-02', '开心', 10)
      ];
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(r.recordedDays).assertEqual(2);
      expect(r.entries).assertEqual(2);
      expect(r.topMood).assertEqual('开心');
      expect(r.moodCounts.length).assertEqual(1);
    });

    it('summary_contains_counts_and_top_mood', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-01-01', '开心', 5000),
        rec('2026-01-02', '开心', 5000),
        rec('2026-01-03', '开心', 2345)
      ];
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(r.chars).assertEqual(12345);
      expect(r.summary.indexOf('这一年记录了 3 天') >= 0).assertTrue();
      expect(r.summary.indexOf('3 篇') >= 0).assertTrue();
      expect(r.summary.indexOf('1.2 万字') >= 0).assertTrue();
      expect(r.summary.indexOf('最常出现的心情是「开心」') >= 0).assertTrue();
      expect(r.summary.indexOf('最长连续 3 天') >= 0).assertTrue();
    });

    it('summary_is_sane_with_single_day', 0, () => {
      const r: AnnualReport = buildAnnualReport([rec('2026-10-08', '平淡', 12)], 2026);
      expect(r.recordedDays).assertEqual(1);
      expect(r.longestStreak).assertEqual(1);
      expect(r.summary.length > 0).assertTrue();
      expect(r.summary.indexOf('这一年记录了 1 天') >= 0).assertTrue();
      expect(r.summary.indexOf('1 篇') >= 0).assertTrue();
      expect(r.summary.indexOf('12 字') >= 0).assertTrue();
      // 只有一天，不该吹"最长连续 1 天"
      expect(r.summary.indexOf('最长连续') >= 0).assertFalse();
    });
  });

  describe('AnnualReportStreak', () => {
    it('cross_month_boundary_is_continuous', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-01-30', '开心', 1),
        rec('2026-01-31', '开心', 1),
        rec('2026-02-01', '开心', 1)
      ];
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(r.longestStreak).assertEqual(3);
      expect(monthOf(r, 1).recordedDays).assertEqual(2);
      expect(monthOf(r, 2).recordedDays).assertEqual(1);
    });

    it('leap_year_feb_29_connects_to_mar_01', 0, () => {
      const logs: StatsLog[] = [
        rec('2024-02-28', '开心', 1),
        rec('2024-02-29', '开心', 1),
        rec('2024-03-01', '开心', 1)
      ];
      const r: AnnualReport = buildAnnualReport(logs, 2024);
      expect(r.longestStreak).assertEqual(3);
      expect(monthOf(r, 2).recordedDays).assertEqual(2);
      expect(monthOf(r, 3).recordedDays).assertEqual(1);
    });

    it('leap_year_feb_29_record_counted_in_that_year', 0, () => {
      const logs: StatsLog[] = [
        rec('2024-02-29', '甜蜜', 40),
        rec('2025-02-28', '甜蜜', 40)
      ];
      const r2024: AnnualReport = buildAnnualReport(logs, 2024);
      expect(r2024.recordedDays).assertEqual(1);
      expect(r2024.entries).assertEqual(1);
      expect(r2024.chars).assertEqual(40);
      expect(monthOf(r2024, 2).recordedDays).assertEqual(1);
      expect(r2024.busiestMonth).assertEqual(2);
      expect(r2024.firstDate).assertEqual('2024-02-29');
      expect(r2024.lastDate).assertEqual('2024-02-29');
      expect(r2024.summary.indexOf('这一年记录了 1 天') >= 0).assertTrue();

      // 同一份数据在非闰年那边只能看到 2/28 那条
      const r2025: AnnualReport = buildAnnualReport(logs, 2025);
      expect(r2025.recordedDays).assertEqual(1);
      expect(r2025.firstDate).assertEqual('2025-02-28');
    });

    it('longest_streak_takes_best_run_across_gaps', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-01-01', '开心', 1),
        rec('2026-01-03', '开心', 1),
        rec('2026-01-04', '开心', 1),
        rec('2026-01-05', '开心', 1),
        rec('2026-01-09', '开心', 1)
      ];
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(r.longestStreak).assertEqual(3);
    });

    it('duplicate_dates_count_once', 0, () => {
      const logs: StatsLog[] = [
        rec('2026-01-01', '开心', 1),
        rec('2026-01-01', '开心', 1),
        rec('2026-01-02', '开心', 1),
        rec('2026-01-02', '开心', 1)
      ];
      expect(longestStreakOf(logs)).assertEqual(2);
      const r: AnnualReport = buildAnnualReport(logs, 2026);
      expect(r.longestStreak).assertEqual(2);
      expect(r.recordedDays).assertEqual(2);
      expect(r.entries).assertEqual(4);
    });

    it('longest_streak_helper_handles_empty_and_single', 0, () => {
      expect(longestStreakOf([])).assertEqual(0);
      expect(longestStreakOf([rec('2026-01-01', '开心', 1)])).assertEqual(1);
    });

    it('dec_31_to_jan_1_is_split_by_natural_year', 0, () => {
      const logs: StatsLog[] = [
        rec('2025-12-31', '开心', 1),
        rec('2026-01-01', '开心', 1)
      ];
      const r2025: AnnualReport = buildAnnualReport(logs, 2025);
      const r2026: AnnualReport = buildAnnualReport(logs, 2026);
      // 自然年口径：两天的跨年连续，在两边各只算 1 天
      expect(r2025.recordedDays).assertEqual(1);
      expect(r2026.recordedDays).assertEqual(1);
      expect(r2025.longestStreak).assertEqual(1);
      expect(r2026.longestStreak).assertEqual(1);
      expect(r2025.lastDate).assertEqual('2025-12-31');
      expect(r2026.firstDate).assertEqual('2026-01-01');
    });
  });

  describe('AnnualReportYears', () => {
    it('available_years_descending_and_contains_current', 0, () => {
      const logs: StatsLog[] = [
        rec('2024-05-05', '开心', 1),
        rec('2025-05-05', '开心', 1),
        rec('2026-05-05', '开心', 1)
      ];
      const years: number[] = availableYears(logs, 2026);
      expect(years.length).assertEqual(3);
      expect(years[0]).assertEqual(2026);
      expect(years[1]).assertEqual(2025);
      expect(years[2]).assertEqual(2024);
      expect(hasYear(years, 2026)).assertTrue();
    });

    it('available_years_with_no_records_is_only_current', 0, () => {
      const years: number[] = availableYears([], 2026);
      expect(years.length).assertEqual(1);
      expect(years[0]).assertEqual(2026);
    });

    it('available_years_ignores_stubs', 0, () => {
      const logs: StatsLog[] = [
        stub('2020-01-01', '平淡', 1),
        rec('2026-03-03', '开心', 1)
      ];
      const years: number[] = availableYears(logs, 2026);
      // 存根不算记录，所以最早记录年是 2026，不会冒出 2020
      expect(years.length).assertEqual(1);
      expect(years[0]).assertEqual(2026);
      expect(hasYear(years, 2020)).assertFalse();
    });

    it('available_years_gap_years_are_included', 0, () => {
      const logs: StatsLog[] = [
        rec('2023-01-01', '开心', 1),
        rec('2026-01-01', '开心', 1)
      ];
      const years: number[] = availableYears(logs, 2026);
      // 中间空着的年份也给出来，用户可以翻到空年份看引导文案
      expect(years.length).assertEqual(4);
      expect(years[0]).assertEqual(2026);
      expect(years[3]).assertEqual(2023);
    });

    it('available_years_earliest_record_wins', 0, () => {
      const logs: StatsLog[] = [
        rec('2019-08-08', '开心', 1),
        rec('2021-08-08', '开心', 1)
      ];
      const years: number[] = availableYears(logs, 2026);
      expect(years.length).assertEqual(8);
      expect(years[0]).assertEqual(2026);
      expect(years[7]).assertEqual(2019);
    });
  });
}
