/**
 * 日期工具类：天数计算、连续打卡、倒计时等纯函数逻辑
 * 统一使用 'yyyy-MM-dd' 字符串作为日期格式，时区固定为本地时区
 */
export interface DurationBreakdown {
  years: number;
  months: number;
  days: number;
}

export interface ElapsedTime {
  days: number;
  hours: number;
  minutes: number;
  seconds: number;
}

export class DateUtils {
  private static readonly MS_PER_DAY: number = 86400000;

  /** 将 Date 格式化为 'yyyy-MM-dd'（本地时区） */
  static formatDate(date: Date): string {
    const y: number = date.getFullYear();
    const m: number = date.getMonth() + 1;
    const d: number = date.getDate();
    return `${y}-${DateUtils.pad2(m)}-${DateUtils.pad2(d)}`;
  }

  /** 返回今天的 'yyyy-MM-dd' */
  static today(): string {
    return DateUtils.formatDate(new Date());
  }

  /** 由年月日构造 'yyyy-MM-dd'，month 从 1 开始 */
  static buildDateStr(year: number, month: number, day: number): string {
    return `${year}-${DateUtils.pad2(month)}-${DateUtils.pad2(day)}`;
  }

  /** 解析 'yyyy-MM-dd' 为 Date（本地零点） */
  static parseDate(dateStr: string): Date {
    const y: number = Number(dateStr.slice(0, 4));
    const m: number = Number(dateStr.slice(5, 7));
    const d: number = Number(dateStr.slice(8, 10));
    return new Date(y, m - 1, d);
  }

  /** 两个日期字符串之间的天数差（end - start），可正可负 */
  static daysBetween(startStr: string, endStr: string): number {
    const start: number = DateUtils.toUtcMillis(startStr);
    const end: number = DateUtils.toUtcMillis(endStr);
    return Math.floor((end - start) / DateUtils.MS_PER_DAY);
  }

  /**
   * 该日期是否已封存：早于今天即为封存。
   *
   * 封存规则（全应用唯一判定处）：
   *   - 过去的日子不能再新建（不能补记）、不能再修改
   *   - 但仍然允许删除
   *   - 今天与未来都不封存
   */
  static isSealed(dateStr: string, todayStr: string): boolean {
    return DateUtils.daysBetween(dateStr, todayStr) > 0;
  }

  /** 在指定日期上增加天数，返回 'yyyy-MM-dd' */
  static addDays(dateStr: string, days: number): string {
    const y: number = Number(dateStr.slice(0, 4));
    const m: number = Number(dateStr.slice(5, 7));
    const d: number = Number(dateStr.slice(8, 10));
    const dt: Date = new Date(Date.UTC(y, m - 1, d + days));
    const yy: number = dt.getUTCFullYear();
    const mm: number = dt.getUTCMonth() + 1;
    const dd: number = dt.getUTCDate();
    return `${yy}-${DateUtils.pad2(mm)}-${DateUtils.pad2(dd)}`;
  }

  /** 判断闰年 */
  static isLeapYear(year: number): boolean {
    return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
  }

  /** 指定年月的天数，month 从 1 开始 */
  static daysInMonth(year: number, month: number): number {
    if (month === 2) {
      return DateUtils.isLeapYear(year) ? 29 : 28;
    }
    const monthDays: number[] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return monthDays[month - 1];
  }

  /** 校验是否为合法的 'yyyy-MM-dd' 字符串 */
  static isValidDateStr(dateStr: string): boolean {
    if (dateStr.length !== 10 || dateStr.charAt(4) !== '-' || dateStr.charAt(7) !== '-') {
      return false;
    }
    const y: number = Number(dateStr.slice(0, 4));
    const m: number = Number(dateStr.slice(5, 7));
    const d: number = Number(dateStr.slice(8, 10));
    if (Number.isNaN(y) || Number.isNaN(m) || Number.isNaN(d)) {
      return false;
    }
    if (m < 1 || m > 12 || d < 1) {
      return false;
    }
    return d <= DateUtils.daysInMonth(y, m);
  }

  /**
   * 计算从 startStr 到 endStr 的持续时间，拆分为年月日
   * 例如：start=2023-06-15, end=2025-03-20 => 1年9个月5天
   */
  static computeDuration(startStr: string, endStr: string): DurationBreakdown {
    let sy: number = Number(startStr.slice(0, 4));
    let sm: number = Number(startStr.slice(5, 7));
    let sd: number = Number(startStr.slice(8, 10));
    const ey: number = Number(endStr.slice(0, 4));
    const em: number = Number(endStr.slice(5, 7));
    const ed: number = Number(endStr.slice(8, 10));

    let years: number = ey - sy;
    let months: number = em - sm;
    let days: number = ed - sd;

    if (days < 0) {
      months -= 1;
      const prevMonth: number = em === 1 ? 12 : em - 1;
      const prevYear: number = em === 1 ? ey - 1 : ey;
      days += DateUtils.daysInMonth(prevYear, prevMonth);
    }
    if (months < 0) {
      years -= 1;
      months += 12;
    }
    return { years, months, days };
  }

  /**
   * 计算连续打卡天数：从今天（或昨天，若今天尚未打卡）向前连续计数
   * @param dates 已打卡的日期字符串数组（去重）
   * @param todayStr 今天日期
   */
  static computeStreak(dates: string[], todayStr: string): number {
    const dateSet: Set<string> = new Set(dates);
    let cursor: string = todayStr;
    if (!dateSet.has(cursor)) {
      cursor = DateUtils.addDays(todayStr, -1);
    }
    let streak: number = 0;
    while (dateSet.has(cursor)) {
      streak += 1;
      cursor = DateUtils.addDays(cursor, -1);
    }
    return streak;
  }

  /**
   * 计算历史最长连续打卡天数：去重后按日期升序扫描最长连续段
   */
  static computeBestStreak(dates: string[]): number {
    const seen: Set<string> = new Set();
    const unique: string[] = [];
    for (const d of dates) {
      if (!seen.has(d)) {
        seen.add(d);
        unique.push(d);
      }
    }
    if (unique.length === 0) {
      return 0;
    }
    unique.sort((a: string, b: string): number => {
      if (a < b) {
        return -1;
      }
      if (a > b) {
        return 1;
      }
      return 0;
    });
    let best: number = 1;
    let run: number = 1;
    for (let i: number = 1; i < unique.length; i++) {
      if (DateUtils.daysBetween(unique[i - 1], unique[i]) === 1) {
        run += 1;
      } else {
        run = 1;
      }
      if (run > best) {
        best = run;
      }
    }
    return best;
  }

  /** 判断今天是否已打卡 */
  static hasCheckedToday(dates: string[], todayStr: string): boolean {
    return dates.indexOf(todayStr) >= 0;
  }

  /**
   * 计算纪念日倒计时（按每年重复的月-日计算）
   * @param dateStr 完整日期 'yyyy-MM-dd'，仅取其月-日
   * @param todayStr 今天日期
   * @returns 距离下一次纪念日的天数，0 表示就是今天
   */
  static nextAnniversaryDays(dateStr: string, todayStr: string): number {
    const monthDay: string = dateStr.slice(5);
    const thisYear: number = Number(todayStr.slice(0, 4));
    let targetYear: number = thisYear;
    // 处理 2-29 在非闰年的边界，落到 2-28
    let targetMonthDay: string = monthDay;
    if (monthDay === '02-29' && !DateUtils.isLeapYear(targetYear)) {
      targetMonthDay = '02-28';
    }
    let target: string = `${targetYear}-${targetMonthDay}`;
    if (DateUtils.daysBetween(todayStr, target) < 0) {
      targetYear += 1;
      targetMonthDay = monthDay;
      if (monthDay === '02-29' && !DateUtils.isLeapYear(targetYear)) {
        targetMonthDay = '02-28';
      }
      target = `${targetYear}-${targetMonthDay}`;
    }
    return DateUtils.daysBetween(todayStr, target);
  }

  /** 计算从 startStr 到现在的精确时长（天、时、分、秒），用于心跳式展示 */
  static computeElapsed(startStr: string, now: Date): ElapsedTime {
    const start: Date = DateUtils.parseDate(startStr);
    let diffSec: number = Math.floor((now.getTime() - start.getTime()) / 1000);
    if (diffSec < 0) {
      diffSec = 0;
    }
    const days: number = Math.floor(diffSec / 86400);
    const hours: number = Math.floor((diffSec % 86400) / 3600);
    const minutes: number = Math.floor((diffSec % 3600) / 60);
    const seconds: number = diffSec % 60;
    return { days, hours, minutes, seconds };
  }

  private static pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  private static toUtcMillis(dateStr: string): number {
    const y: number = Number(dateStr.slice(0, 4));
    const m: number = Number(dateStr.slice(5, 7));
    const d: number = Number(dateStr.slice(8, 10));
    return Date.UTC(y, m - 1, d);
  }
}
