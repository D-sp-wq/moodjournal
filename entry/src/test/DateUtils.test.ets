import { describe, it, expect } from '@ohos/hypium';
import { DateUtils } from '../main/ets/common/utils/DateUtils';

export default function dateUtilsTest() {
  describe('DateUtils', () => {
    it('daysBetween_basic', 0, () => {
      expect(DateUtils.daysBetween('2024-01-01', '2024-01-02')).assertEqual(1);
      expect(DateUtils.daysBetween('2024-01-02', '2024-01-01')).assertEqual(-1);
      expect(DateUtils.daysBetween('2024-01-01', '2024-01-01')).assertEqual(0);
    });

    it('daysBetween_leapYear', 0, () => {
      expect(DateUtils.daysBetween('2023-06-15', '2024-06-15')).assertEqual(366);
      expect(DateUtils.daysBetween('2024-06-15', '2025-06-15')).assertEqual(365);
    });

    it('isLeapYear', 0, () => {
      expect(DateUtils.isLeapYear(2024)).assertTrue();
      expect(DateUtils.isLeapYear(2023)).assertFalse();
      expect(DateUtils.isLeapYear(2000)).assertTrue();
      expect(DateUtils.isLeapYear(1900)).assertFalse();
    });

    it('daysInMonth', 0, () => {
      expect(DateUtils.daysInMonth(2024, 2)).assertEqual(29);
      expect(DateUtils.daysInMonth(2023, 2)).assertEqual(28);
      expect(DateUtils.daysInMonth(2024, 1)).assertEqual(31);
      expect(DateUtils.daysInMonth(2024, 4)).assertEqual(30);
    });

    it('addDays', 0, () => {
      expect(DateUtils.addDays('2024-12-31', 1)).assertEqual('2025-01-01');
      expect(DateUtils.addDays('2024-03-01', -1)).assertEqual('2024-02-29');
      expect(DateUtils.addDays('2023-03-01', -1)).assertEqual('2023-02-28');
    });

    it('computeDuration', 0, () => {
      const duration = DateUtils.computeDuration('2023-06-15', '2025-03-20');
      expect(duration.years).assertEqual(1);
      expect(duration.months).assertEqual(9);
      expect(duration.days).assertEqual(5);
    });

    it('computeStreak', 0, () => {
      expect(DateUtils.computeStreak(['2024-05-01', '2024-05-02', '2024-05-03'], '2024-05-03')).assertEqual(3);
      expect(DateUtils.computeStreak(['2024-05-01', '2024-05-03'], '2024-05-03')).assertEqual(1);
      // 今天未打卡，从昨天开始连续计数
      expect(DateUtils.computeStreak(['2024-05-01', '2024-05-02'], '2024-05-03')).assertEqual(2);
      expect(DateUtils.computeStreak([], '2024-05-03')).assertEqual(0);
    });

    it('computeBestStreak', 0, () => {
      expect(DateUtils.computeBestStreak([])).assertEqual(0);
      expect(DateUtils.computeBestStreak(['2024-05-01'])).assertEqual(1);
      // 重复日期去重
      expect(DateUtils.computeBestStreak(['2024-05-01', '2024-05-01'])).assertEqual(1);
      // 含断点的最长连续段
      expect(DateUtils.computeBestStreak(['2024-05-01', '2024-05-03', '2024-05-04', '2024-05-05'])).assertEqual(3);
      // 跨月连续
      expect(DateUtils.computeBestStreak(['2024-04-29', '2024-04-30', '2024-05-01'])).assertEqual(3);
      // 跨年连续
      expect(DateUtils.computeBestStreak(['2024-12-30', '2024-12-31', '2025-01-01'])).assertEqual(3);
      // 闰年 2 月连续
      expect(DateUtils.computeBestStreak(['2024-02-28', '2024-02-29', '2024-03-01'])).assertEqual(3);
    });

    it('nextAnniversaryDays', 0, () => {
      expect(DateUtils.nextAnniversaryDays('2024-05-20', '2024-05-20')).assertEqual(0);
      expect(DateUtils.nextAnniversaryDays('2024-05-20', '2024-05-19')).assertEqual(1);
      // 今年已过，跳到明年
      expect(DateUtils.nextAnniversaryDays('2024-05-20', '2024-05-21')).assertEqual(364);
    });

    it('isValidDateStr', 0, () => {
      expect(DateUtils.isValidDateStr('2024-02-29')).assertTrue();
      expect(DateUtils.isValidDateStr('2023-02-29')).assertFalse();
      expect(DateUtils.isValidDateStr('2024-13-01')).assertFalse();
      expect(DateUtils.isValidDateStr('2024-00-10')).assertFalse();
    });

    it('isSealed_yesterday_is_locked', 0, () => {
      expect(DateUtils.isSealed('2024-05-19', '2024-05-20')).assertTrue();
      expect(DateUtils.isSealed('2024-05-01', '2024-05-20')).assertTrue();
    });

    it('isSealed_today_and_future_are_writable', 0, () => {
      expect(DateUtils.isSealed('2024-05-20', '2024-05-20')).assertFalse();
      expect(DateUtils.isSealed('2024-05-21', '2024-05-20')).assertFalse();
      expect(DateUtils.isSealed('2030-01-01', '2024-05-20')).assertFalse();
    });

    it('isSealed_month_and_year_boundaries', 0, () => {
      expect(DateUtils.isSealed('2024-04-30', '2024-05-01')).assertTrue();
      expect(DateUtils.isSealed('2024-12-31', '2025-01-01')).assertTrue();
      expect(DateUtils.isSealed('2025-01-01', '2024-12-31')).assertFalse();
    });

    it('isSealed_leap_year_boundary', 0, () => {
      expect(DateUtils.isSealed('2024-02-28', '2024-02-29')).assertTrue();
      expect(DateUtils.isSealed('2024-02-29', '2024-03-01')).assertTrue();
      expect(DateUtils.isSealed('2023-02-28', '2023-03-01')).assertTrue();
    });
  });
}
