import { Anniversary, getAnniversaryTypeLabel } from './Anniversary';
import { DailyLog, Mood, logSummary, moodLabel } from './DailyLog';

/** 时间轴条目：每日记录与重要日子合并后的一行 */
export interface TimelineItem {
  key: string;
  /** TIMELINE_CHECKIN 或 TIMELINE_ANNIVERSARY */
  type: string;
  date: string;
  mood: Mood;
  title: string;
  subtitle: string;
}

export const TIMELINE_CHECKIN: string = 'checkin';
export const TIMELINE_ANNIVERSARY: string = 'anniversary';

/**
 * 把每日记录与重要日子合并成一条按日期倒序的时间轴。
 * 纯函数：不访问存储，便于单元测试。
 */
export function buildTimeline(logs: DailyLog[], anniversaries: Anniversary[]): TimelineItem[] {
  const items: TimelineItem[] = [];
  for (const c of logs) {
    items.push({
      key: `c_${c.id}`,
      type: TIMELINE_CHECKIN,
      date: c.date,
      mood: c.mood,
      title: moodLabel(c.mood, c.customMood),
      subtitle: logSummary(c, 40)
    });
  }
  for (const a of anniversaries) {
    items.push({
      key: `a_${a.id}`,
      type: TIMELINE_ANNIVERSARY,
      date: a.date,
      mood: Mood.HAPPY,
      title: a.title,
      subtitle: getAnniversaryTypeLabel(a.type)
    });
  }
  items.sort((x: TimelineItem, y: TimelineItem): number => {
    if (x.date < y.date) {
      return 1;
    }
    if (x.date > y.date) {
      return -1;
    }
    return 0;
  });
  return items;
}
