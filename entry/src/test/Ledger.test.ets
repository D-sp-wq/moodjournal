import { describe, it, expect } from '@ohos/hypium';
import {
  LedgerFeeling,
  LedgerRecord,
  LedgerType,
  formatAmount,
  monthOf,
  normalizeAmount,
  summarizeLedger
} from '../main/ets/models/Ledger';

function rec(date: string, type: LedgerType, amount: number, category: string): LedgerRecord {
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

export default function ledgerTest() {
  describe('Ledger', () => {
    it('normalize_amount', 0, () => {
      expect(normalizeAmount(-12.345)).assertEqual(12.35);
      expect(normalizeAmount(0)).assertEqual(0);
      expect(normalizeAmount(Number.NaN)).assertEqual(0);
    });

    it('format_amount', 0, () => {
      expect(formatAmount(12)).assertEqual('12');
      expect(formatAmount(12.5)).assertEqual('12.50');
      expect(formatAmount(12.345)).assertEqual('12.35');
    });

    it('month_of', 0, () => {
      expect(monthOf('2026-10-09')).assertEqual('2026-10');
      expect(monthOf('2026-01-01')).assertEqual('2026-01');
    });

    it('summarize_basic', 0, () => {
      const list: LedgerRecord[] = [
        rec('2026-10-01', LedgerType.EXPENSE, 30, '餐饮'),
        rec('2026-10-02', LedgerType.EXPENSE, 70, '购物'),
        rec('2026-10-03', LedgerType.INCOME, 500, '工资'),
        rec('2026-09-30', LedgerType.EXPENSE, 999, '其他')
      ];
      const s = summarizeLedger(list, '2026-10', 0);
      expect(s.expense).assertEqual(100);
      expect(s.income).assertEqual(500);
      expect(s.balance).assertEqual(400);
      expect(s.count).assertEqual(3);
      expect(s.byCategory.length).assertEqual(2);
      // 分类按金额降序
      expect(s.byCategory[0].name).assertEqual('购物');
      expect(s.byCategory[0].percent).assertEqual(70);
      expect(s.byCategory[1].name).assertEqual('餐饮');
      expect(s.byCategory[1].percent).assertEqual(30);
    });

    it('budget_progress', 0, () => {
      const list: LedgerRecord[] = [rec('2026-10-01', LedgerType.EXPENSE, 250, '餐饮')];
      const s = summarizeLedger(list, '2026-10', 1000);
      expect(s.budgetPercent).assertEqual(25);
      expect(s.budgetLeft).assertEqual(750);
      expect(s.overBudget).assertFalse();
    });

    it('over_budget', 0, () => {
      const list: LedgerRecord[] = [rec('2026-10-01', LedgerType.EXPENSE, 1200, '餐饮')];
      const s = summarizeLedger(list, '2026-10', 1000);
      expect(s.budgetPercent).assertEqual(100);
      expect(s.budgetLeft).assertEqual(-200);
      expect(s.overBudget).assertTrue();
    });

    it('no_budget_set', 0, () => {
      const list: LedgerRecord[] = [rec('2026-10-01', LedgerType.EXPENSE, 50, '餐饮')];
      const s = summarizeLedger(list, '2026-10', 0);
      expect(s.budgetPercent).assertEqual(0);
      expect(s.budgetLeft).assertEqual(0);
      expect(s.overBudget).assertFalse();
    });

    it('empty_month', 0, () => {
      const s = summarizeLedger([], '2026-10', 1000);
      expect(s.expense).assertEqual(0);
      expect(s.income).assertEqual(0);
      expect(s.count).assertEqual(0);
      expect(s.byCategory.length).assertEqual(0);
    });
  });
}
