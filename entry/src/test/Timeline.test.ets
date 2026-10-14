import { describe, it, expect } from '@ohos/hypium';
import { Anniversary, AnniversaryType } from '../main/ets/models/Anniversary';
import { DailyLog, Mood } from '../main/ets/models/DailyLog';
import {
  TIMELINE_ANNIVERSARY,
  TIMELINE_CHECKIN,
  TimelineItem,
  buildTimeline
} from '../main/ets/models/Timeline';

function makeLog(date: string, mood: Mood, journal: string): DailyLog {
  return {
    id: `l_${date}`,
    date: date,
    mood: mood,
    customMood: '',
    journal: journal,
    plan: '',
    photoUris: [],
    tags: [],
    hasEntry: true,
    createdAt: 0,
    updatedAt: 0
  };
}

function makeAnniversary(date: string, title: string): Anniversary {
  return {
    id: `a_${date}`,
    title: title,
    type: AnniversaryType.FESTIVAL,
    date: date,
    reminderEnabled: false,
    createdAt: 0
  };
}

export default function timelineTest() {
  describe('Timeline', () => {
    it('sorts_by_date_desc', 0, () => {
      const items: TimelineItem[] = buildTimeline([
        makeLog('2026-10-01', Mood.HAPPY, '第一条'),
        makeLog('2026-10-03', Mood.SAD, '第二条')
      ], []);
      expect(items.length).assertEqual(2);
      expect(items[0].date).assertEqual('2026-10-03');
      expect(items[1].date).assertEqual('2026-10-01');
    });

    it('merges_and_marks_types', 0, () => {
      const items: TimelineItem[] = buildTimeline([
        makeLog('2026-10-01', Mood.HAPPY, '记录')
      ], [makeAnniversary('2026-10-02', '国庆')]);
      expect(items.length).assertEqual(2);
      expect(items[0].type).assertEqual(TIMELINE_ANNIVERSARY);
      expect(items[0].title).assertEqual('国庆');
      expect(items[0].subtitle).assertEqual('节日');
      expect(items[1].type).assertEqual(TIMELINE_CHECKIN);
    });

    it('checkin_uses_mood_label_and_summary', 0, () => {
      const items: TimelineItem[] = buildTimeline([
        makeLog('2026-10-01', Mood.HAPPY, '今天去爬山了')
      ], []);
      expect(items[0].title).assertEqual('开心');
      expect(items[0].subtitle).assertEqual('今天去爬山了');
      expect(items[0].mood).assertEqual(Mood.HAPPY);
    });

    it('custom_mood_shows_its_text', 0, () => {
      const log: DailyLog = makeLog('2026-10-01', Mood.CUSTOM, '还行');
      log.customMood = '元气满满';
      const items: TimelineItem[] = buildTimeline([log], []);
      expect(items[0].title).assertEqual('元气满满');
    });

    it('keys_are_prefixed_by_kind', 0, () => {
      const items: TimelineItem[] = buildTimeline([
        makeLog('2026-10-01', Mood.HAPPY, 'a')
      ], [makeAnniversary('2026-10-01', '节日')]);
      expect(items[0].key.startsWith('c_')).assertTrue();
      expect(items[1].key.startsWith('a_')).assertTrue();
    });

    it('empty_input', 0, () => {
      const items: TimelineItem[] = buildTimeline([], []);
      expect(items.length).assertEqual(0);
    });
  });
}
