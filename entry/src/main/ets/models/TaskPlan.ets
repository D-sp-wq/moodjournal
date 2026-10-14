import { DateUtils } from '../common/utils/DateUtils';

/**
 * 任务规划数据模型（以「天」为单位）
 *
 * 语义：为一件重要的事规划用多少天完成。startDate 为第 1 天，
 * 因此目标完成日 = startDate + (plannedDays - 1)。
 */
export interface TaskPlan {
  id: string;
  title: string;
  /** 'yyyy-MM-dd'，计划开始日 */
  startDate: string;
  /** 计划用多少天完成，1..365 */
  plannedDays: number;
  completed: boolean;
  completedAt: number;
  createdAt: number;
}

/** 同时规划的任务数量上限 */
export const MAX_TASK_PLANS: number = 6;
export const MIN_PLANNED_DAYS: number = 1;
export const MAX_PLANNED_DAYS: number = 365;

export interface TaskProgress {
  /** 目标完成日 'yyyy-MM-dd' */
  targetDate: string;
  /** 已过天数，0..plannedDays */
  elapsedDays: number;
  /** 剩余天数；0 表示今天到期，负数表示已超期 */
  remainingDays: number;
  /** 进度百分比 0..100 */
  percent: number;
  /** 是否已超期 */
  overdue: boolean;
  /** 开始日是否在未来 */
  notStarted: boolean;
}

/** 把任意输入的天数收敛到合法区间 */
export function clampPlannedDays(days: number): number {
  if (Number.isNaN(days) || days < MIN_PLANNED_DAYS) {
    return MIN_PLANNED_DAYS;
  }
  if (days > MAX_PLANNED_DAYS) {
    return MAX_PLANNED_DAYS;
  }
  return Math.floor(days);
}

/**
 * 纯函数：按「天」计算某个任务相对 today 的进度。
 * 不访问存储，可直接单元测试。
 */
export function computeTaskProgress(plan: TaskPlan, today: string): TaskProgress {
  const total: number = clampPlannedDays(plan.plannedDays);
  const targetDate: string = DateUtils.addDays(plan.startDate, total - 1);

  const offset: number = DateUtils.daysBetween(plan.startDate, today);
  const notStarted: boolean = offset < 0;

  let elapsedDays: number = offset + 1;
  if (elapsedDays < 0) {
    elapsedDays = 0;
  }
  if (elapsedDays > total) {
    elapsedDays = total;
  }

  const remainingDays: number = DateUtils.daysBetween(today, targetDate);

  return {
    targetDate: targetDate,
    elapsedDays: elapsedDays,
    remainingDays: remainingDays,
    percent: Math.round(elapsedDays * 100 / total),
    overdue: remainingDays < 0,
    notStarted: notStarted
  };
}
