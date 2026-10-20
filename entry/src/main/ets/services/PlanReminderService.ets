import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../common/constants/Constants';
import { DateUtils } from '../common/utils/DateUtils';
import { DailyLog } from '../models/DailyLog';
import { DayPlan, PlanReminderSettings, buildReminderPlan, shouldPublish } from '../models/PlanReminder';
import { RepositoryFactory } from './data/RepositoryFactory';
import { ReminderService } from './ReminderService';
import { SessionManager } from './storage/SessionManager';

/**
 * 「今日提醒」的编排：读设置 + 读未来 7 天的计划，交给 ReminderService 重排。
 *
 * 读计划沿用全应用唯一的存储语义：日期 D 要做的事，写在 **D-1** 那条 DailyLog 的 plan 里
 * （DayPlanPage 按这个规则写入，HomePage 按这个规则回显）。
 * 日期减法一律用 DateUtils.addDays，不手写月份天数表。
 *
 * 任何失败只记日志，绝不抛异常 —— 提醒是增强功能，坏了不能影响记录本身。
 */
export class PlanReminderService {
  /**
   * 重排今日提醒：
   * - 关闭（或时间脏了）→ 只取消已排期的，不排新的
   * - 开启 → 读今天起 7 天里每天的计划，先取消旧的再按新设置排新的
   */
  static async sync(): Promise<void> {
    try {
      const settings: PlanReminderSettings = await PlanReminderService.readSettings();
      if (!shouldPublish(settings)) {
        await ReminderService.cancelPlanReminders();
        return;
      }
      const dayPlans: DayPlan[] = await PlanReminderService.readNextDays(Constants.PLAN_REMINDER_DAYS);
      const items: DayPlan[] = buildReminderPlan(dayPlans);
      // 先清旧的再排新的：改过时间之后不能留着上一批
      await ReminderService.cancelPlanReminders();
      await ReminderService.publishPlanReminders(items, settings);
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '同步今日提醒失败: %{public}s', JSON.stringify(err));
    }
  }

  /** 读设置；读不到就用默认值（关闭 + 09:00），页面与同步逻辑共用 */
  static async readSettings(): Promise<PlanReminderSettings> {
    try {
      const session = SessionManager.getInstance();
      return {
        enabled: await session.isPlanReminderEnabled(),
        hour: await session.getPlanReminderHour(),
        minute: await session.getPlanReminderMinute()
      };
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '读取今日提醒设置失败: %{public}s', JSON.stringify(err));
      return {
        enabled: false,
        hour: Constants.PLAN_REMINDER_HOUR,
        minute: Constants.PLAN_REMINDER_MINUTE
      };
    }
  }

  /**
   * 今天起 days 天里，每一天要做的事（没有安排的日子 plan 为 ''）。
   *
   * 一天要做的事存在它**前一天**的记录里，所以查 date 的前一天。
   * 只读一次全表再在内存里找：七天七次查库没必要。
   */
  private static async readNextDays(days: number): Promise<DayPlan[]> {
    const logs: DailyLog[] = await PlanReminderService.readLogs();
    const today: string = DateUtils.today();
    const result: DayPlan[] = [];
    for (let i: number = 0; i < days; i++) {
      const date: string = DateUtils.addDays(today, i);
      const source: string = DateUtils.addDays(date, -1);
      let plan: string = '';
      for (const log of logs) {
        if (log.date === source) {
          plan = log.plan;
          break;
        }
      }
      result.push({ date: date, plan: plan === undefined || plan === null ? '' : plan });
    }
    return result;
  }

  /** 读全部记录；读库失败按「没有任何安排」处理（宁可不打扰，也不拿旧数据瞎排） */
  private static async readLogs(): Promise<DailyLog[]> {
    try {
      return await RepositoryFactory.getRepository().getDailyLogs();
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '读取计划失败: %{public}s', JSON.stringify(err));
      return [];
    }
  }
}
