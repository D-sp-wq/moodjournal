import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../common/constants/Constants';
import { Habit, HabitReminderSlot, buildReminderSlots } from '../models/Habit';
import { RepositoryFactory } from './data/RepositoryFactory';
import { ReminderService } from './ReminderService';

/**
 * 习惯提醒的编排：读全部习惯 → 算出需要排期的时段 → 先取消旧的再排新的。
 *
 * 与 PlanReminderService 同一套写法与容错原则：
 * 任何失败只记日志，绝不抛异常 —— 提醒是增强功能，坏了不能影响打卡本身。
 *
 * 注意：打卡（toggle）**不**触发 sync。提醒是按每天固定时刻响的，与今天打没打卡无关；
 * 每次打卡都重排一遍不但毫无意义，还会反复取消/发布系统提醒。
 */
export class HabitReminderService {
  /** 按当前习惯配置重排提醒（保存 / 编辑 / 删除习惯成功后调用） */
  static async sync(): Promise<void> {
    try {
      const habits: Habit[] = await RepositoryFactory.getRepository().getHabits();
      const slots: HabitReminderSlot[] = buildReminderSlots(habits);
      // 先清旧的再排新的：改过时间之后不能留着上一批
      await ReminderService.cancelHabitReminders();
      await ReminderService.publishHabitReminders(slots);
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '同步习惯提醒失败: %{public}s', JSON.stringify(err));
    }
  }
}
