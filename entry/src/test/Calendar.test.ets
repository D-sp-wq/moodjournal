import { describe, it, expect } from '@ohos/hypium';
import { DailyLog, Mood } from '../main/ets/models/DailyLog';
import { CalendarMark, MonthSummary, buildMonthMarks, summarizeMonth } from '../main/ets/models/Calendar';

/** 造一条记录；只需要关心日历用得到的字段 */
function log(date: string, mood: Mood, customMood: string, journal: string, photos: string[]): DailyLog {
  return {
    id: date,
    date: date,
    mood: mood,
    customMood: customMood,
    journal: journal,
    plan: '',
    photoUris: photos,
    tags: [],
    hasEntry: true,
    createdAt: 0,
    updatedAt: 0
  };
}

export default function calendarTest() {
  describe('Calendar', () => {
    it('marks_length_equals_days_in_month', 0, () => {
      expect(buildMonthMarks([], 2026, 10, '2026-10-10').length).assertEqual(31);
      expect(buildMonthMarks([], 2026, 4, '2026-10-10').length).assertEqual(30);
      expect(buildMonthMarks([], 2026, 2, '2026-10-10').length).assertEqual(28);
      // 闰年 2 月
      expect(buildMonthMarks([], 2028, 2, '2026-10-10').length).assertEqual(29);
    });

    it('empty_month_marks_are_sealed_for_past_days', 0, () => {
      const marks: CalendarMark[] = buildMonthMarks([], 2026, 10, '2026-10-10');
      expect(marks[0].date).assertEqual('2026-10-01');
      expect(marks[0].mood).assertEqual('');
      expect(marks[0].sealed).assertTrue();
      expect(marks[0].hasPhoto).assertFalse();
      // 9 号是过去 -> 封存；10 号是今天 -> 不封存；11 号是未来 -> 不封存
      expect(marks[8].date).assertEqual('2026-10-09');
      expect(marks[8].sealed).assertTrue();
      expect(marks[9].sealed).assertFalse();
      expect(marks[10].sealed).assertFalse();
    });

    it('recorded_day_carries_mood_label', 0, () => {
      const logs: DailyLog[] = [log('2026-10-05', Mood.HAPPY, '', '今天不错', [])];
      const marks: CalendarMark[] = buildMonthMarks(logs, 2026, 10, '2026-10-10');
      expect(marks[4].mood !== '').assertTrue();
      expect(marks[4].sealed).assertFalse();
      expect(marks[4].hasPhoto).assertFalse();
    });

    it('custom_mood_uses_custom_text', 0, () => {
      const logs: DailyLog[] = [log('2026-10-05', Mood.CUSTOM, '元气满满', 'hi', [])];
      const marks: CalendarMark[] = buildMonthMarks(logs, 2026, 10, '2026-10-10');
      expect(marks[4].mood).assertEqual('元气满满');
    });

    it('photo_flag_follows_photo_uris', 0, () => {
      const withPhoto: DailyLog[] = [log('2026-10-05', Mood.HAPPY, '', 'x', ['file://a.jpg'])];
      expect(buildMonthMarks(withPhoto, 2026, 10, '2026-10-10')[4].hasPhoto).assertTrue();
      const without: DailyLog[] = [log('2026-10-05', Mood.HAPPY, '', 'x', [])];
      expect(buildMonthMarks(without, 2026, 10, '2026-10-10')[4].hasPhoto).assertFalse();
    });

    it('ignores_logs_from_other_months', 0, () => {
      const logs: DailyLog[] = [
        log('2026-09-20', Mood.HAPPY, '', 'x', []),
        log('2026-11-02', Mood.HAPPY, '', 'x', [])
      ];
      const marks: CalendarMark[] = buildMonthMarks(logs, 2026, 10, '2026-10-10');
      let recorded: number = 0;
      for (const mark of marks) {
        if (mark.mood !== '') {
          recorded += 1;
        }
      }
      expect(recorded).assertEqual(0);
    });

    it('summary_counts_days_entries_and_chars', 0, () => {
      const logs: DailyLog[] = [
        log('2026-10-01', Mood.HAPPY, '', '一二三', []),
        log('2026-10-02', Mood.HAPPY, '', '一二', []),
        log('2026-10-05', Mood.SAD, '', '一', [])
      ];
      const s: MonthSummary = summarizeMonth(logs, 2026, 10, '2026-10-10');
      expect(s.recordedDays).assertEqual(3);
      expect(s.entries).assertEqual(3);
      expect(s.chars).assertEqual(6);
      expect(s.topMood !== '').assertTrue();
    });

    it('empty_month_summary_has_guide_text', 0, () => {
      const s: MonthSummary = summarizeMonth([], 2026, 10, '2026-10-10');
      expect(s.recordedDays).assertEqual(0);
      expect(s.topMood).assertEqual('');
      expect(s.summary.indexOf('还没有记录') >= 0).assertTrue();
    });

    it('delta_against_previous_natural_month', 0, () => {
      const logs: DailyLog[] = [
        log('2026-10-01', Mood.HAPPY, '', 'x', []),
        log('2026-10-02', Mood.HAPPY, '', 'x', []),
        log('2026-09-10', Mood.HAPPY, '', 'x', [])
      ];
      const s: MonthSummary = summarizeMonth(logs, 2026, 10, '2026-10-10');
      expect(s.recordedDays).assertEqual(2);
      expect(s.daysDelta).assertEqual(1);
      expect(s.summary.indexOf('多记了 1 天') >= 0).assertTrue();
    });

    it('january_compares_with_previous_december', 0, () => {
      const logs: DailyLog[] = [
        log('2026-01-03', Mood.HAPPY, '', 'x', []),
        log('2025-12-01', Mood.HAPPY, '', 'x', []),
        log('2025-12-02', Mood.HAPPY, '', 'x', [])
      ];
      const s: MonthSummary = summarizeMonth(logs, 2026, 1, '2026-01-10');
      expect(s.recordedDays).assertEqual(1);
      expect(s.daysDelta).assertEqual(-1);
      expect(s.summary.indexOf('少记了 1 天') >= 0).assertTrue();
    });
  });
}
