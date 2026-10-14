import { DailyLog } from '../../models/DailyLog';
import { Anniversary } from '../../models/Anniversary';
import { Photo } from '../../models/Photo';
import { TaskPlan } from '../../models/TaskPlan';
import { LedgerRecord } from '../../models/Ledger';
import { Habit, HabitCheck } from '../../models/Habit';

/**
 * 数据访问层接口。
 *
 * 单用户模型：没有账号、没有绑定关系，全部数据都属于本机这一位使用者。
 * 本地实现为 LocalRepository；后续若接入云端，再提供 CloudRepository 实现。
 */
export interface Repository {
  /** 读取某一天的记录，无则返回 null */
  getDailyLog(date: string): Promise<DailyLog | null>;

  /** 写入／更新某一天的记录（按 date 唯一，一天一条） */
  upsertDailyLog(log: DailyLog): Promise<void>;

  /** 按日期倒序读取全部记录 */
  getDailyLogs(): Promise<DailyLog[]>;

  deleteDailyLog(id: string): Promise<void>;

  getImportantDays(): Promise<Anniversary[]>;

  upsertImportantDay(item: Anniversary): Promise<void>;

  deleteImportantDay(id: string): Promise<void>;

  getPhotos(): Promise<Photo[]>;

  addPhoto(photo: Photo): Promise<void>;

  deletePhoto(id: string): Promise<void>;

  /** 任务规划：未完成在前，按创建时间倒序 */
  getTaskPlans(): Promise<TaskPlan[]>;

  upsertTaskPlan(plan: TaskPlan): Promise<void>;

  deleteTaskPlan(id: string): Promise<void>;

  /** 账本：按日期倒序（同一天按创建时间倒序） */
  getLedgerRecords(): Promise<LedgerRecord[]>;

  upsertLedgerRecord(record: LedgerRecord): Promise<void>;

  deleteLedgerRecord(id: string): Promise<void>;

  /** 习惯打卡：习惯按 sortOrder 升序 */
  getHabits(): Promise<Habit[]>;

  upsertHabit(habit: Habit): Promise<void>;

  deleteHabit(id: string): Promise<void>;

  /** 全部打卡记录（按日期倒序），调用方自己按习惯分组 */
  getHabitChecks(): Promise<HabitCheck[]>;

  upsertHabitCheck(check: HabitCheck): Promise<void>;

  deleteHabitCheck(habitId: string, date: string): Promise<void>;

  /** 删除某习惯时连带删掉它的打卡记录 */
  deleteHabitChecksOf(habitId: string): Promise<void>;
}
