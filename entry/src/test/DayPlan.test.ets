import { describe, it, expect } from '@ohos/hypium';
import { DateUtils } from '../main/ets/common/utils/DateUtils';
import { CalendarMark, buildMonthMarks, buildUpcomingPlans, daysAheadLabel } from '../main/ets/models/Calendar';
import { DailyLog, Mood, hasEntry } from '../main/ets/models/DailyLog';

/** 造一条正常记录 */
function entry(date: string, mood: Mood, journal: string, plan: string): DailyLog {
  return {
    id: date,
    date: date,
    mood: mood,
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

/** 造一个"只写了计划"的存根 */
function stub(date: string, plan: string): DailyLog {
  return {
    id: date,
    date: date,
    mood: Mood.HAPPY,
    customMood: '',
    journal: '',
    plan: plan,
    photoUris: [],
    tags: [],
    hasEntry: false,
    createdAt: 0,
    updatedAt: 0
  };
}

export default function dayPlanTest() {
  describe('DayPlan', () => {
    // 未来日期 D 的计划落在 D-1 的 plan 上，所以减一天必须跨月跨年都正确
    it('target_date_is_previous_day', 0, () => {
      expect(DateUtils.addDays('2026-10-11', -1)).assertEqual('2026-10-10');
      expect(DateUtils.addDays('2026-11-01', -1)).assertEqual('2026-10-31');
      expect(DateUtils.addDays('2027-01-01', -1)).assertEqual('2026-12-31');
      expect(DateUtils.addDays('2028-03-01', -1)).assertEqual('2028-02-29');
    });

    it('entry_flag_predicate', 0, () => {
      expect(hasEntry(entry('2026-10-10', Mood.HAPPY, '写了点什么', ''))).assertTrue();
      expect(hasEntry(stub('2026-10-11', '去看医生'))).assertFalse();
    });

    it('plan_stub_does_not_paint_mood_color', 0, () => {
      const logs: DailyLog[] = [stub('2026-10-12', '开会')];
      const marks: CalendarMark[] = buildMonthMarks(logs, 2026, 10, '2026-10-10');
      // 10-12 是第 12 个
      expect(marks[11].mood).assertEqual('');
      expect(marks[11].hasPlan).assertTrue();
    });

    it('real_entry_paints_mood_and_keeps_plan_mark', 0, () => {
      const logs: DailyLog[] = [entry('2026-10-05', Mood.HAPPY, '今天不错', '明天去跑步')];
      const marks: CalendarMark[] = buildMonthMarks(logs, 2026, 10, '2026-10-10');
      expect(marks[4].mood !== '').assertTrue();
      expect(marks[4].hasPlan).assertTrue();
    });

    it('entry_without_plan_has_no_plan_mark', 0, () => {
      const logs: DailyLog[] = [entry('2026-10-05', Mood.HAPPY, '今天不错', '')];
      const marks: CalendarMark[] = buildMonthMarks(logs, 2026, 10, '2026-10-10');
      expect(marks[4].hasPlan).assertFalse();
    });

    it('blank_plan_is_not_a_plan_mark', 0, () => {
      const logs: DailyLog[] = [entry('2026-10-05', Mood.HAPPY, '今天不错', '   ')];
      const marks: CalendarMark[] = buildMonthMarks(logs, 2026, 10, '2026-10-10');
      expect(marks[4].hasPlan).assertFalse();
    });

    it('future_days_are_not_sealed', 0, () => {
      const marks: CalendarMark[] = buildMonthMarks([], 2026, 10, '2026-10-10');
      expect(marks[10].sealed).assertFalse();  // 10-11 未来
      expect(marks[8].sealed).assertTrue();    // 10-09 过去
    });

    // 首页「接下来几天」：D 那天要做的事存在 D-1 的 plan 里，展示时要顺延回来
    it('upcoming_plans_shift_by_one_day', 0, () => {
      const logs: DailyLog[] = [
        entry('2026-10-10', Mood.HAPPY, '今天', '明天体检'),
        entry('2026-10-12', Mood.HAPPY, 'x', '后天交材料')
      ];
      const list = buildUpcomingPlans(logs, '2026-10-10', 7);
      expect(list.length).assertEqual(2);
      expect(list[0].date).assertEqual('2026-10-11');
      expect(list[0].plan).assertEqual('明天体检');
      expect(list[0].daysAhead).assertEqual(1);
      expect(list[1].date).assertEqual('2026-10-13');
      expect(list[1].daysAhead).assertEqual(3);
    });

    it('upcoming_plans_skip_blank_and_out_of_range', 0, () => {
      const logs: DailyLog[] = [
        entry('2026-10-10', Mood.HAPPY, 'x', '   '),          // 空白不算
        entry('2026-10-20', Mood.HAPPY, 'x', '太远了')         // 超出 7 天窗口
      ];
      expect(buildUpcomingPlans(logs, '2026-10-10', 7).length).assertEqual(0);
    });

    it('upcoming_plan_stub_counts', 0, () => {
      const logs: DailyLog[] = [stub('2026-10-11', '去看医生')];
      const list = buildUpcomingPlans(logs, '2026-10-10', 7);
      expect(list.length).assertEqual(1);
      expect(list[0].date).assertEqual('2026-10-12');
    });

    it('days_ahead_labels', 0, () => {
      expect(daysAheadLabel(1)).assertEqual('明天');
      expect(daysAheadLabel(2)).assertEqual('后天');
      expect(daysAheadLabel(5)).assertEqual('5 天后');
    });
  });
}
