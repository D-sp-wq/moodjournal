import { describe, it, expect } from '@ohos/hypium';
import { DateCalcUtils, MilestoneInfo } from '../main/ets/common/utils/DateCalcUtils';

export default function dateCalcUtilsTest() {
  describe('DateCalcUtils', () => {
    it('daysUntil_and_label', 0, () => {
      expect(DateCalcUtils.daysUntil('2026-10-11', '2026-10-08')).assertEqual(3);
      expect(DateCalcUtils.daysUntil('2026-10-08', '2026-10-08')).assertEqual(0);
      expect(DateCalcUtils.daysUntil('2026-10-01', '2026-10-08')).assertEqual(-7);
      expect(DateCalcUtils.untilLabel(0)).assertEqual('就是今天');
      expect(DateCalcUtils.untilLabel(3)).assertEqual('还有 3 天');
      expect(DateCalcUtils.untilLabel(-7)).assertEqual('已过去 7 天');
    });

    it('weekday_and_chinese_date', 0, () => {
      // 2026-10-08 是星期四
      expect(DateCalcUtils.weekdayLabel('2026-10-08')).assertEqual('周四');
      expect(DateCalcUtils.weekdayLabel('2026-10-01')).assertEqual('周四');
      expect(DateCalcUtils.toChineseDate('2026-10-08')).assertEqual('2026年10月8日');
      expect(DateCalcUtils.toChineseDate('2026-01-01')).assertEqual('2026年1月1日');
    });

    it('shift_and_diff', 0, () => {
      expect(DateCalcUtils.shift('2026-10-08', 7)).assertEqual('2026-10-15');
      expect(DateCalcUtils.shift('2026-10-08', -8)).assertEqual('2026-09-30');
      expect(DateCalcUtils.shift('2026-12-31', 1)).assertEqual('2027-01-01');
      expect(DateCalcUtils.diffLabel('2026-10-08', '2026-10-15')).assertEqual('晚 7 天');
      expect(DateCalcUtils.diffLabel('2026-10-08', '2026-10-01')).assertEqual('早 7 天');
      expect(DateCalcUtils.diffLabel('2026-10-08', '2026-10-08')).assertEqual('同一天');
    });

    it('duration_label', 0, () => {
      expect(DateCalcUtils.durationLabel('2023-06-15', '2025-03-20')).assertEqual('1 年 9 个月 5 天');
      // 顺序颠倒也应得到同一结果
      expect(DateCalcUtils.durationLabel('2025-03-20', '2023-06-15')).assertEqual('1 年 9 个月 5 天');
      expect(DateCalcUtils.durationLabel('2026-10-08', '2026-10-08')).assertEqual('0 天');
    });

    it('next_milestone', 0, () => {
      // 2026-01-01 起第 94 天是 2026-04-05，下一个整百天是第 100 天 → 2026-04-11
      const m: MilestoneInfo = DateCalcUtils.nextMilestone('2026-01-01', '2026-04-05', 100);
      expect(m.days).assertEqual(100);
      expect(m.date).assertEqual('2026-04-11');
      expect(m.daysLeft).assertEqual(6);
      // 起始日在未来：从第一个步长算起
      const future: MilestoneInfo = DateCalcUtils.nextMilestone('2027-01-01', '2026-10-08', 100);
      expect(future.days).assertEqual(100);
      expect(future.date).assertEqual('2027-04-11');
    });

    it('validate_range', 0, () => {
      expect(DateCalcUtils.validateRange('2026-10-01', '2026-10-08')).assertEqual('');
      expect(DateCalcUtils.validateRange('2026-10-08', '2026-10-01')).assertEqual('结束日期不能早于开始日期');
      expect(DateCalcUtils.validateRange('2026-13-01', '2026-10-08')).assertEqual('请选择合法的日期');
      expect(DateCalcUtils.validateRange('2026-02-30', '2026-10-08')).assertEqual('请选择合法的日期');
    });
  });
}
