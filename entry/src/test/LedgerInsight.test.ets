import { describe, it, expect } from '@ohos/hypium';
import {
  LedgerFeeling,
  LedgerRecord,
  LedgerType,
  MIN_GROUP_DAYS,
  buildDailySpendStrip,
  buildSpendingInsights,
  computeDailyLeft,
  computeWorthScore,
  summarizeLedger
} from '../main/ets/models/Ledger';

function rec(date: string, type: LedgerType, amount: number, category: string, feeling: LedgerFeeling): LedgerRecord {
  return {
    id: `${date}_${category}_${amount}`,
    date: date,
    type: type,
    amount: amount,
    category: category,
    note: '',
    feeling: feeling,
    createdAt: 0
  };
}

export default function ledgerInsightTest() {
  describe('LedgerInsight', () => {
    it('worth_score_needs_marks', 0, () => {
      expect(computeWorthScore(0, 0, 0, 100, 0)).assertEqual(-1);
    });

    it('worth_score_all_worth_within_budget', 0, () => {
      // 值得占比 1 -> 70 分；未超预算 -> 预算 30 分
      expect(computeWorthScore(3, 0, 0, 100, 500)).assertEqual(100);
    });

    it('worth_score_half_worth_half_regret', 0, () => {
      // (2*1 + 0)/4 = 0.5 -> 35 分；预算满 30 分 -> 65
      expect(computeWorthScore(2, 0, 2, 100, 500)).assertEqual(65);
    });

    it('worth_score_neutral_counts_half', 0, () => {
      // (0 + 4*0.5)/4 = 0.5 -> 35 + 30 = 65
      expect(computeWorthScore(0, 4, 0, 100, 500)).assertEqual(65);
    });

    it('worth_score_drops_when_over_budget', 0, () => {
      // 值得占比 1 -> 70；超支 50% -> 预算 15 分；合计 85
      expect(computeWorthScore(2, 0, 0, 150, 100)).assertEqual(85);
    });

    it('daily_left_with_budget', 0, () => {
      // 预算 300，本月已花 100，10 月 10 号 -> 剩 22 天 -> (300-100)/22 = 9
      expect(computeDailyLeft(100, 300, 10, 31)).assertEqual(9);
    });

    it('daily_left_without_budget', 0, () => {
      expect(computeDailyLeft(100, 0, 10, 31)).assertEqual(-1);
    });

    it('daily_left_last_day', 0, () => {
      // 最后一天：剩余天数 = 1，不会除零
      expect(computeDailyLeft(100, 300, 31, 31)).assertEqual(200);
    });

    it('daily_left_over_budget_is_negative', 0, () => {
      expect(computeDailyLeft(400, 300, 10, 31)).assertEqual(-5);
    });

    it('summary_counts_feelings_and_scores', 0, () => {
      const startOfMonth: string = `${'2026-10'}-`;
      const list: LedgerRecord[] = [
        rec(`${startOfMonth}01`, LedgerType.EXPENSE, 30, '餐饮', LedgerFeeling.WORTH),
        rec(`${startOfMonth}02`, LedgerType.EXPENSE, 70, '购物', LedgerFeeling.REGRET),
        rec(`${startOfMonth}03`, LedgerType.EXPENSE, 20, '交通', LedgerFeeling.NEUTRAL),
        rec(`${startOfMonth}04`, LedgerType.EXPENSE, 50, '娱乐', LedgerFeeling.NONE),
        rec(`${startOfMonth}05`, LedgerType.INCOME, 500, '工资', LedgerFeeling.NONE)
      ];
      const s = summarizeLedger(list, '2026-10', 500);
      expect(s.worthCount).assertEqual(1);
      expect(s.neutralCount).assertEqual(1);
      expect(s.regretCount).assertEqual(1);
      expect(s.markedCount).assertEqual(3);
      expect(s.worthScore > 0).assertTrue();
      expect(s.regretTop.length).assertEqual(1);
      expect(s.regretTop[0].amount).assertEqual(70);
    });

    it('regret_top_sorted_and_capped', 0, () => {
      const list: LedgerRecord[] = [
        rec('2026-10-01', LedgerType.EXPENSE, 10, '餐饮', LedgerFeeling.REGRET),
        rec('2026-10-02', LedgerType.EXPENSE, 300, '购物', LedgerFeeling.REGRET),
        rec('2026-10-03', LedgerType.EXPENSE, 90, '娱乐', LedgerFeeling.REGRET),
        rec('2026-10-04', LedgerType.EXPENSE, 200, '医疗', LedgerFeeling.REGRET),
        rec('2026-10-05', LedgerType.EXPENSE, 0, '其他', LedgerFeeling.REGRET),
        rec('2026-10-06', LedgerType.EXPENSE, 999, '居住', LedgerFeeling.WORTH)
      ];
      const s = summarizeLedger(list, '2026-10', 0);
      expect(s.regretTop.length).assertEqual(3);
      expect(s.regretTop[0].amount).assertEqual(300);
      expect(s.regretTop[1].amount).assertEqual(200);
      expect(s.regretTop[2].amount).assertEqual(90);
    });

    it('daily_strip_length_and_values', 0, () => {
      const list: LedgerRecord[] = [
        rec('2026-10-01', LedgerType.EXPENSE, 10, '餐饮', LedgerFeeling.NONE),
        rec('2026-10-01', LedgerType.EXPENSE, 5, '交通', LedgerFeeling.NONE),
        rec('2026-10-03', LedgerType.EXPENSE, 20, '购物', LedgerFeeling.NONE),
        rec('2026-10-03', LedgerType.INCOME, 100, '红包', LedgerFeeling.NONE)
      ];
      const strip: number[] = buildDailySpendStrip(list, '2026-10', 31);
      expect(strip.length).assertEqual(31);
      expect(strip[0]).assertEqual(15);
      expect(strip[1]).assertEqual(0);
      expect(strip[2]).assertEqual(20);
    });

    it('insights_need_enough_samples', 0, () => {
      const list: LedgerRecord[] = [
        rec('2026-10-01', LedgerType.EXPENSE, 100, '购物', LedgerFeeling.NONE)
      ];
      const mood: Map<string, string> = new Map();
      mood.set('2026-10-01', '低落');
      expect(buildSpendingInsights(list, mood, '2026-10').length).assertEqual(0);
    });

    it('insight_low_mood_spends_more', 0, () => {
      const list: LedgerRecord[] = [];
      const mood: Map<string, string> = new Map();
      // 3 个低落日，每天 100；3 个开心日，每天 10
      for (let i: number = 1; i <= 3; i++) {
        const d: string = `2026-10-0${i}`;
        list.push(rec(d, LedgerType.EXPENSE, 100, '购物', LedgerFeeling.NONE));
        mood.set(d, '低落');
      }
      for (let i: number = 4; i <= 6; i++) {
        const d: string = `2026-10-0${i}`;
        list.push(rec(d, LedgerType.EXPENSE, 10, '餐饮', LedgerFeeling.NONE));
        mood.set(d, '开心');
      }
      const out = buildSpendingInsights(list, mood, '2026-10');
      expect(out.length > 0).assertTrue();
      expect(out[0].text.indexOf('心情不好') >= 0).assertTrue();
    });

    it('insight_regret_category', 0, () => {
      const list: LedgerRecord[] = [
        rec('2026-10-01', LedgerType.EXPENSE, 100, '购物', LedgerFeeling.REGRET),
        rec('2026-10-02', LedgerType.EXPENSE, 200, '购物', LedgerFeeling.REGRET),
        rec('2026-10-03', LedgerType.EXPENSE, 50, '餐饮', LedgerFeeling.REGRET)
      ];
      const out = buildSpendingInsights(list, new Map(), '2026-10');
      let found: boolean = false;
      for (const item of out) {
        if (item.text.indexOf('购物') >= 0) {
          found = true;
        }
      }
      expect(found).assertTrue();
      expect(MIN_GROUP_DAYS).assertEqual(3);
    });
  });
}
