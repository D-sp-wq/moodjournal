import reminderAgentManager from '@ohos.reminderAgentManager';
import notificationManager from '@ohos.notificationManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../common/constants/Constants';
import { DateUtils } from '../common/utils/DateUtils';

/**
 * 后台代理提醒服务：每日记录提醒 + 重要日子提醒（尽力而为，失败仅记录日志）
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
}
