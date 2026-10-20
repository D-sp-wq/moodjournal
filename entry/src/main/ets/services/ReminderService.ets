import reminderAgentManager from '@ohos.reminderAgentManager';
import notificationManager from '@ohos.notificationManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../common/constants/Constants';
import { DateUtils } from '../common/utils/DateUtils';
import { DayPlan, PlanReminderSettings, reminderContent, shouldPublish } from '../models/PlanReminder';
import { SessionManager } from './storage/SessionManager';

/** 「今日提醒」通知标题（固定文案） */
const PLAN_REMINDER_TITLE: string = '今天要做的事';

/**
 * 后台代理提醒服务：每日记录提醒 + 重要日子提醒 + 今日提醒（尽力而为，失败仅记录日志）
 */
export class ReminderService {
  /** 发布每日记录提醒（每天 21:00） */
  static async publishDailyRecordReminder(): Promise<void> {
    try {
      const reminder: reminderAgentManager.ReminderRequestAlarm = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
        hour: Constants.REMINDER_HOUR,
        minute: Constants.REMINDER_MINUTE,
        daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
        title: '记录今天的心情',
        content: '花一分钟写写今天发生了什么，再给明天定几件事 ✍️',
        notificationId: 1001,
        slotType: notificationManager.SlotType.CONTENT_INFORMATION
      };
      await reminderAgentManager.publishReminder(reminder);
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '发布记录提醒失败: %{public}s', JSON.stringify(err));
    }
  }

  /** 发布某一天的重要日子提醒（当天 09:00） */
  static async publishAnniversaryReminder(title: string, dateStr: string): Promise<void> {
    try {
      if (!DateUtils.isValidDateStr(dateStr)) {
        return;
      }
      const y: number = Number(dateStr.slice(0, 4));
      const m: number = Number(dateStr.slice(5, 7));
      const d: number = Number(dateStr.slice(8, 10));
      const dateTime: reminderAgentManager.LocalDateTime = {
        year: y,
        month: m,
        day: d,
        hour: 9,
        minute: 0,
        second: 0
      };
      const reminder: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: dateTime,
        title: '重要日子提醒',
        content: `今天是「${title}」`,
        notificationId: 2001,
        slotType: notificationManager.SlotType.CONTENT_INFORMATION
      };
      await reminderAgentManager.publishReminder(reminder);
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '发布重要日子提醒失败: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 发布「今日提醒」：为每个 { date, plan } 排一条当天的一次性提醒。
   *
   * - 标题固定「今天要做的事」，正文是该天计划的摘要（超长截断加省略号）
   * - notificationId = 3000 + 序号，避开记录提醒的 1001 与重要日子的 2001
   * - 发布成功的 reminderId 会写进 preferences（key planReminderIds），供 cancelPlanReminders 取消
   * - 单条失败只记日志并跳过，整体不抛异常
   *
   * @returns 发布成功的 reminderId 列表（顺序与 items 中被排上的顺序一致）
   */
  static async publishPlanReminders(items: DayPlan[], settings: PlanReminderSettings): Promise<number[]> {
    const ids: number[] = [];
    try {
      // 关闭（或时间非法）时绝不排期：这就是「设置关闭时不应发布」的落点
      if (!shouldPublish(settings)) {
        hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '今日提醒未开启，跳过排期');
        return ids;
      }
      for (let i: number = 0; i < items.length; i++) {
        const dateStr: string = items[i].date;
        const content: string = reminderContent(items[i].plan, Constants.PLAN_REMINDER_CONTENT_MAX);
        if (!DateUtils.isValidDateStr(dateStr) || content === '') {
          continue;
        }
        // 今天这个点已经过了（例如 10:00 才打开应用）就不补了：
        // 否则每次冷启动 sync() 都会立刻弹一次通知。
        const target: Date = DateUtils.parseDate(dateStr);
        target.setHours(settings.hour, settings.minute, 0, 0);
        if (target.getTime() <= Date.now()) {
          continue;
        }
        try {
          const dateTime: reminderAgentManager.LocalDateTime = {
            year: Number(dateStr.slice(0, 4)),
            month: Number(dateStr.slice(5, 7)),
            day: Number(dateStr.slice(8, 10)),
            hour: settings.hour,
            minute: settings.minute,
            second: 0
          };
          const reminder: reminderAgentManager.ReminderRequestCalendar = {
            reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
            dateTime: dateTime,
            title: PLAN_REMINDER_TITLE,
            content: content,
            notificationId: Constants.PLAN_REMINDER_ID_BASE + i,
            slotType: notificationManager.SlotType.CONTENT_INFORMATION
          };
          const reminderId: number = await reminderAgentManager.publishReminder(reminder);
          ids.push(reminderId);
        } catch (err) {
          hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '发布今日提醒失败(%{public}s): %{public}s',
            dateStr, JSON.stringify(err));
        }
      }
      await ReminderService.savePlanReminderIds(ids);
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '发布今日提醒失败: %{public}s', JSON.stringify(err));
    }
    return ids;
  }

  /**
   * 取消所有已排的「今日提醒」：把上次存下的 reminderId 逐个取消，然后清空记录。
   * 单个取消失败只记日志；整体不抛异常。
   */
  static async cancelPlanReminders(): Promise<void> {
    try {
      const session = SessionManager.getInstance();
      const ids: number[] = await session.getPlanReminderIds();
      for (const id of ids) {
        try {
          await reminderAgentManager.cancelReminder(id);
        } catch (err) {
          // 已经被系统清掉（或 id 早就失效）属正常情况，继续取消剩下的
          hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '取消今日提醒失败(%{public}d): %{public}s',
            id, JSON.stringify(err));
        }
      }
      if (ids.length > 0) {
        await session.setPlanReminderIds([]);
      }
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '取消今日提醒失败: %{public}s', JSON.stringify(err));
    }
  }

  /** 记住这次排上的 reminderId（存失败只记日志，不影响提醒本身已经生效） */
  private static async savePlanReminderIds(ids: number[]): Promise<void> {
    try {
      await SessionManager.getInstance().setPlanReminderIds(ids);
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '保存今日提醒 id 失败: %{public}s', JSON.stringify(err));
    }
  }
}
