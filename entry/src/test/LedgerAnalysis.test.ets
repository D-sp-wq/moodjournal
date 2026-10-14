import { describe, it, expect } from '@ohos/hypium';
import { LedgerFeeling, LedgerRecord, LedgerType } from '../main/ets/models/Ledger';
import {
  ANOMALY_FACTOR,
  ANOMALY_MIN_SAMPLES,
  ConsumptionAnalysis,
  SMALL_TICKET_AMOUNT,
  SMALL_TICKET_MIN_COUNT,
  analyzeConsumption,
  buildAnalysisPayload,
  elapsedDaysOf,
  previousMonthOf
} from '../main/ets/models/LedgerAnalysis';

function rec(date: string, amount: number, category: string, type: LedgerType): LedgerRecord {
  return {
    id: `${date}_${category}_${amount}`,
    date: date,
    type: type,
    amount: amount,
    category: category,
    note: '',
    feeling: LedgerFeeling.NONE,
    createdAt: 0
  };
}

function expense(date: string, amount: number, category: string): LedgerRecord {
  return rec(date, amount, category, LedgerType.EXPENSE);
}

export default function ledgerAnalysisTest() {
  describe('LedgerAnalysis', () => {
    it('previous_month_handles_year_boundary', 0, () => {
      expect(previousMonthOf('2026-10')).assertEqual('2026-09');
      expect(previousMonthOf('2026-01')).assertEqual('2025-12');
    });

    it('elapsed_days_uses_today_for_current_month', 0, () => {
      expect(elapsedDaysOf('2026-10', '2026-10-10', 31)).assertEqual(10);
      // 分析历史月份时整月都算已过，避免预测值失真
      expect(elapsedDaysOf('2026-09', '2026-10-10', 30)).assertEqual(30);
    });

    it('forecast_projects_to_month_end', 0, () => {
      const list: LedgerRecord[] = [expense('2026-10-01', 100, '餐饮')];
      const a: ConsumptionAnalysis = analyzeConsumption(list, '2026-10', 0, '2026-10-10');
      expect(a.forecast.elapsedDays).assertEqual(10);
      expect(a.forecast.dailyAverage).assertEqual(10);
      expect(a.forecast.projectedTotal).assertEqual(310);
      expect(a.forecast.budget).assertEqual(0);
      expect(a.forecast.overBy).assertEqual(0);
    });

    it('forecast_reports_over_budget', 0, () => {
      const list: LedgerRecord[] = [expense('2026-10-01', 100, '餐饮')];
      const a: ConsumptionAnalysis = analyzeConsumption(list, '2026-10', 200, '2026-10-10');
      // 预计 310，预算 200 -> 超出 110
      expect(a.forecast.overBy).assertEqual(110);
    });

    it('delta_percent_is_minus_one_without_previous_month', 0, () => {
      const list: LedgerRecord[] = [expense('2026-10-01', 50, '餐饮')];
      const a: ConsumptionAnalysis = analyzeConsumption(list, '2026-10', 0, '2026-10-10');
      expect(a.previousTotal).assertEqual(0);
      expect(a.deltaPercent).assertEqual(-1);
      expect(a.deltaAmount).assertEqual(50);
    });

    it('delta_percent_computed_normally', 0, () => {
      const list: LedgerRecord[] = [
        expense('2026-10-01', 150, '餐饮'),
        expense('2026-09-10', 100, '餐饮')
      ];
      const a: ConsumptionAnalysis = analyzeConsumption(list, '2026-10', 0, '2026-10-10');
      expect(a.currentTotal).assertEqual(150);
      expect(a.previousTotal).assertEqual(100);
      expect(a.deltaAmount).assertEqual(50);
      expect(a.deltaPercent).assertEqual(50);
    });

    it('category_changes_sorted_by_abs_delta_top3', 0, () => {
      const list: LedgerRecord[] = [
        expense('2026-10-01', 200, '餐饮'),
        expense('2026-09-10', 50, '餐饮'),
        expense('2026-10-02', 10, '交通'),
        expense('2026-09-11', 80, '交通'),
        expense('2026-10-03', 100, '购物'),
        expense('2026-10-04', 90, '娱乐'),
        expense('2026-10-05', 70, '医疗')
      ];
      const a: ConsumptionAnalysis = analyzeConsumption(list, '2026-10', 0, '2026-10-10');
      expect(a.categoryChanges.length).assertEqual(3);
      // 餐饮 +150 最大
      expect(a.categoryChanges[0].name).assertEqual('餐饮');
      expect(a.categoryChanges[0].delta).assertEqual(150);
    });

    it('max_single_ignores_zero_and_income', 0, () => {
      const list: LedgerRecord[] = [
        expense('2026-10-01', 0, '餐饮'),
        rec('2026-10-02', 9999, '工资', LedgerType.INCOME),
        expense('2026-10-03', 88, '购物')
      ];
      const a: ConsumptionAnalysis = analyzeConsumption(list, '2026-10', 0, '2026-10-10');
      expect(a.maxSingle === null).assertFalse();
      expect(a.maxSingle!.amount).assertEqual(88);
    });

    it('small_ticket_needs_min_count', 0, () => {
      const few: LedgerRecord[] = [
        expense('2026-10-01', 10, '餐饮'),
        expense('2026-10-02', 12, '餐饮')
      ];
      expect(analyzeConsumption(few, '2026-10', 0, '2026-10-10').smallTicketCount)
        .assertEqual(2);
      // 笔数不足阈值时页面不展示，但计数本身要准
      expect(SMALL_TICKET_MIN_COUNT).assertEqual(5);
      expect(SMALL_TICKET_AMOUNT).assertEqual(30);
    });

    it('small_ticket_amount_and_percent', 0, () => {
      const list: LedgerRecord[] = [];
      for (let i: number = 1; i <= 5; i++) {
        list.push(expense(`2026-10-0${i}`, 20, '餐饮'));
      }
      list.push(expense('2026-10-06', 400, '购物'));
      const a: ConsumptionAnalysis = analyzeConsumption(list, '2026-10', 0, '2026-10-10');
      expect(a.smallTicketCount).assertEqual(5);
      expect(a.smallTicketAmount).assertEqual(100);
      expect(a.smallTicketPercent).assertEqual(20);
    });

    it('no_spend_days_counts_only_elapsed', 0, () => {
      const list: LedgerRecord[] = [expense('2026-10-01', 10, '餐饮')];
      const a: ConsumptionAnalysis = analyzeConsumption(list, '2026-10', 0, '2026-10-05');
      expect(a.noSpendDays).assertEqual(4);
    });

    it('anomaly_needs_min_samples', 0, () => {
      const list: LedgerRecord[] = [
        expense('2026-10-01', 10, '购物'),
        expense('2026-10-02', 500, '购物')
      ];
      const a: ConsumptionAnalysis = analyzeConsumption(list, '2026-10', 0, '2026-10-10');
      expect(a.anomalies.length).assertEqual(0);
      expect(ANOMALY_MIN_SAMPLES).assertEqual(3);
    });

    it('anomaly_flags_outlier', 0, () => {
      const list: LedgerRecord[] = [
        expense('2026-10-01', 100, '购物'),
        expense('2026-10-02', 100, '购物'),
        expense('2026-10-03', 100, '购物'),
        expense('2026-10-04', 900, '购物')
      ];
      const a: ConsumptionAnalysis = analyzeConsumption(list, '2026-10', 0, '2026-10-10');
      expect(a.anomalies.length).assertEqual(1);
      expect(a.anomalies[0].amount).assertEqual(900);
      expect(a.anomalies[0].usual).assertEqual(100);
      expect(a.anomalies[0].times).assertEqual(9);
    });

    it('anomaly_boundary_exactly_two_times_is_not_flagged', 0, () => {
      // 其余三笔 100 -> 均值 100；这笔恰好 200 = 均值 × 2，不算异常
      const list: LedgerRecord[] = [
        expense('2026-10-01', 100, '购物'),
        expense('2026-10-02', 100, '购物'),
        expense('2026-10-03', 100, '购物'),
        expense('2026-10-04', 200, '购物')
      ];
      const a: ConsumptionAnalysis = analyzeConsumption(list, '2026-10', 0, '2026-10-10');
      expect(a.anomalies.length).assertEqual(0);
      expect(ANOMALY_FACTOR).assertEqual(2);
    });

    it('payload_contains_only_aggregates', 0, () => {
      const list: LedgerRecord[] = [
        expense('2026-10-01', 100, '餐饮'),
        expense('2026-10-02', 900, '购物'),
        expense('2026-10-03', 100, '购物'),
        expense('2026-10-04', 100, '购物')
      ];
      const a: ConsumptionAnalysis = analyzeConsumption(list, '2026-10', 300, '2026-10-10');
      const payload: string = buildAnalysisPayload(a);
      // 含聚合字段
      expect(payload.indexOf('支出合计') >= 0).assertTrue();
      expect(payload.indexOf('预计月底支出') >= 0).assertTrue();
      expect(payload.indexOf('分类涨跌') >= 0).assertTrue();
      // 不含任何明细敏感字段
      expect(payload.indexOf('备注') >= 0).assertFalse();
      expect(payload.indexOf('日记') >= 0).assertFalse();
      expect(payload.indexOf('心情') >= 0).assertFalse();
      expect(payload.indexOf('照片') >= 0).assertFalse();
    });

    it('payload_is_valid_json_shape', 0, () => {
      const list: LedgerRecord[] = [expense('2026-10-01', 100, '餐饮')];
      const a: ConsumptionAnalysis = analyzeConsumption(list, '2026-10', 0, '2026-10-10');
      const payload: string = buildAnalysisPayload(a);
      expect(payload.startsWith('{')).assertTrue();
      expect(payload.endsWith('}')).assertTrue();
      // 空数组也要是合法形状
      expect(payload.indexOf('"异常支出":[') >= 0).assertTrue();
    });

    it('empty_month_is_safe', 0, () => {
      const a: ConsumptionAnalysis = analyzeConsumption([], '2026-10', 0, '2026-10-10');
      expect(a.currentTotal).assertEqual(0);
      expect(a.forecast.dailyAverage).assertEqual(0);
      expect(a.forecast.projectedTotal).assertEqual(0);
      expect(a.maxSingle === null).assertTrue();
      expect(a.anomalies.length).assertEqual(0);
      expect(a.smallTicketPercent).assertEqual(0);
    });
  });
}
