import { DateUtils, DurationBreakdown } from './DateUtils';

export interface MilestoneInfo {
  /** 里程碑天数，如 100 */
  days: number;
  /** 达成日期 'yyyy-MM-dd' */
  date: string;
  /** 距今天还有多少天 */
  daysLeft: number;
}

/** 星期中文名，索引对应 Date.getDay() */
const WEEKDAY_LABELS: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

/**
 * 日期计算工具：供「日期工具」页使用的纯函数集合。
 * 全部复用 DateUtils 的解析与差值实现，统一 'yyyy-MM-dd' 格式。
 */
export class DateCalcUtils {
  /** 距离目标日还有多少天：今天为 0，未来为正，已过为负 */
  static daysUntil(target: string, todayStr: string): number {
    return DateUtils.daysBetween(todayStr, target);
  }

  /** 倒计时文案 */
  static untilLabel(days: number): string {
    if (days === 0) {
      return '就是今天';
    }
    if (days > 0) {
      return `还有 ${days} 天`;
    }
    return `已过去 ${-days} 天`;
  }

  /** 中文星期 */
  static weekdayLabel(dateStr: string): string {
    const week: number = DateUtils.parseDate(dateStr).getDay();
    return WEEKDAY_LABELS[week];
  }

  /** 'yyyy-MM-dd' -> '2026年10月8日' */
  static toChineseDate(dateStr: string): string {
    const y: number = Number(dateStr.slice(0, 4));
    const m: number = Number(dateStr.slice(5, 7));
    const d: number = Number(dateStr.slice(8, 10));
    return `${y}年${m}月${d}日`;
  }

  /** 两个日期相距的中文描述 */
  static diffLabel(from: string, to: string): string {
    const n: number = DateUtils.daysBetween(from, to);
    if (n === 0) {
      return '同一天';
    }
    return n > 0 ? `晚 ${n} 天` : `早 ${-n} 天`;
  }

  /** 两个日期之间时长的中文描述，如 '1 年 9 个月 5 天' */
  static durationLabel(from: string, to: string): string {
    const earlier: string = from <= to ? from : to;
    const later: string = from <= to ? to : from;
    const duration: DurationBreakdown = DateUtils.computeDuration(earlier, later);
    const parts: string[] = [];
    if (duration.years > 0) {
      parts.push(`${duration.years} 年`);
    }
    if (duration.months > 0) {
      parts.push(`${duration.months} 个月`);
    }
    if (duration.days > 0) {
      parts.push(`${duration.days} 天`);
    }
    return parts.length > 0 ? parts.join(' ') : '0 天';
  }

  /** 日期推算：在 base 上加减 days */
  static shift(base: string, days: number): string {
    return DateUtils.addDays(base, days);
  }

  /**
   * 下一个整步长里程碑，例如每 100 天一个节点。
   * 起始日晚于今天时，从第一个步长开始算。
   */
  static nextMilestone(startDate: string, todayStr: string, step: number): MilestoneInfo {
    const safeStep: number = step > 0 ? step : 1;
    const passed: number = DateUtils.daysBetween(startDate, todayStr);
    let index: number = Math.floor(passed / safeStep) + 1;
    if (passed < 0) {
      index = 1;
    }
    const days: number = index * safeStep;
    const date: string = DateUtils.addDays(startDate, days);
    return { days: days, date: date, daysLeft: DateUtils.daysBetween(todayStr, date) };
  }

  /** 校验日期区间：合法且起点不晚于终点时返回空串，否则返回提示 */
  static validateRange(from: string, to: string): string {
    if (!DateUtils.isValidDateStr(from) || !DateUtils.isValidDateStr(to)) {
      return '请选择合法的日期';
    }
    if (DateUtils.daysBetween(from, to) < 0) {
      return '结束日期不能早于开始日期';
    }
    return '';
  }
}
