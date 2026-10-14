import { describe, it, expect } from '@ohos/hypium';
import { DailyLog, Mood, logSummary } from '../main/ets/models/DailyLog';

function makeLog(journal: string, plan: string): DailyLog {
  return {
    id: 'l1',
    date: '2026-10-08',
    mood: Mood.HAPPY,
    customMood: '',
    journal: journal,
    plan: plan,
    photoUris: [],
    tags: [],
    hasEntry: true,
    createdAt: 0,
    updatedAt: 0
  };
}

export default function logSummaryTest() {
  describe('LogSummary', () => {
    it('prefers_journal', 0, () => {
      expect(logSummary(makeLog('今天去了海边', '明天写报告'), 40)).assertEqual('今天去了海边');
    });

    it('falls_back_to_plan_when_journal_blank', 0, () => {
      expect(logSummary(makeLog('', '明天写报告'), 40)).assertEqual('明天写报告');
      expect(logSummary(makeLog('   ', '明天写报告'), 40)).assertEqual('明天写报告');
    });

    it('empty_placeholder_when_both_blank', 0, () => {
      expect(logSummary(makeLog('', ''), 40)).assertEqual('（无正文）');
      expect(logSummary(makeLog('  \n ', ' \n '), 40)).assertEqual('（无正文）');
    });

    it('takes_first_non_empty_line_only', 0, () => {
      expect(logSummary(makeLog('第一行\n第二行', ''), 40)).assertEqual('第一行');
      expect(logSummary(makeLog('\n\n第一段\n第二段', ''), 40)).assertEqual('第一段');
    });

    it('truncates_long_line_with_ellipsis', 0, () => {
      const long: string = '一二三四五六七八九十'.repeat(5);
      const summary: string = logSummary(makeLog(long, ''), 40);
      expect(summary.length).assertEqual(41);
      expect(summary.endsWith('…')).assertTrue();
    });

    it('keeps_short_line_intact', 0, () => {
      expect(logSummary(makeLog('短短一句', ''), 40)).assertEqual('短短一句');
    });
  });
}
