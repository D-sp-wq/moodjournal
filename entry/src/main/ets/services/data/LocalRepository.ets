import relationalStore from '@ohos.data.relationalStore';
import { DatabaseHelper } from '../storage/DatabaseHelper';
import { DailyLog, Mood, parsePhotoUris, parseTags, serializePhotoUris, serializeTags } from '../../models/DailyLog';
import { Anniversary } from '../../models/Anniversary';
import { Photo } from '../../models/Photo';
import { TaskPlan } from '../../models/TaskPlan';
import { LedgerRecord, LedgerType, LedgerFeeling } from '../../models/Ledger';
import { Habit, HabitCheck, normalizeTimesPerDay, parseSlotTimes, serializeSlotTimes } from '../../models/Habit';
import { Repository } from './Repository';

/**
 * 本地数据访问实现：基于关系型数据库，完全离线。
 * 单用户模型，不涉及账号、绑定与任何网络请求。
 */
export class LocalRepository implements Repository {

  private get store(): relationalStore.RdbStore {
    return DatabaseHelper.getInstance().getStore();
  }

  // ---------------- 每日记录 ----------------

  async getDailyLog(date: string): Promise<DailyLog | null> {
    const rs: relationalStore.ResultSet = await this.store.querySql(
      'SELECT * FROM daily_logs WHERE date = ?', [date]);
    let log: DailyLog | null = null;
    if (rs.goToFirstRow()) {
      log = this.mapDailyLog(rs);
    }
    rs.close();
    return log;
  }

  async upsertDailyLog(log: DailyLog): Promise<void> {
    const existing: DailyLog | null = await this.getDailyLog(log.date);
    if (existing) {
      const values: relationalStore.ValuesBucket = {
        'mood': Number(log.mood),
        'custom_mood': log.customMood,
        'journal': log.journal,
        'plan': log.plan,
        'photo_uris': serializePhotoUris(log.photoUris),
        'tags': serializeTags(log.tags),
        'updated_at': log.updatedAt
      };
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('daily_logs');
      predicates.equalTo('date', log.date);
      await this.store.update(values, predicates);
    } else {
      await this.store.insert('daily_logs', this.dailyLogToValues(log));
    }
  }

  async getDailyLogs(): Promise<DailyLog[]> {
    const rs: relationalStore.ResultSet = await this.store.querySql(
      'SELECT * FROM daily_logs ORDER BY date DESC', []);
    const list: DailyLog[] = [];
    if (rs.goToFirstRow()) {
      do {
        list.push(this.mapDailyLog(rs));
      } while (rs.goToNextRow());
    }
    rs.close();
    return list;
  }

  async deleteDailyLog(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('daily_logs');
    predicates.equalTo('id', id);
    await this.store.delete(predicates);
  }

  // ---------------- 重要日子 ----------------

  async getImportantDays(): Promise<Anniversary[]> {
    const rs: relationalStore.ResultSet = await this.store.querySql(
      'SELECT * FROM important_days ORDER BY date ASC', []);
    const list: Anniversary[] = [];
    if (rs.goToFirstRow()) {
      do {
        list.push(this.mapAnniversary(rs));
      } while (rs.goToNextRow());
    }
    rs.close();
    return list;
  }

  async upsertImportantDay(item: Anniversary): Promise<void> {
    const existing: Anniversary | null = await this.findImportantDayById(item.id);
    if (existing) {
      const values: relationalStore.ValuesBucket = {
        'title': item.title,
        'type': item.type,
        'date': item.date,
        'reminder_enabled': item.reminderEnabled ? 1 : 0
      };
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('important_days');
      predicates.equalTo('id', item.id);
      await this.store.update(values, predicates);
    } else {
      await this.store.insert('important_days', this.anniversaryToValues(item));
    }
  }

  async deleteImportantDay(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('important_days');
    predicates.equalTo('id', id);
    await this.store.delete(predicates);
  }

  // ---------------- 图片 ----------------

  async getPhotos(): Promise<Photo[]> {
    const rs: relationalStore.ResultSet = await this.store.querySql(
      'SELECT * FROM photos ORDER BY date DESC', []);
    const list: Photo[] = [];
    if (rs.goToFirstRow()) {
      do {
        list.push(this.mapPhoto(rs));
      } while (rs.goToNextRow());
    }
    rs.close();
    return list;
  }

  async addPhoto(photo: Photo): Promise<void> {
    await this.store.insert('photos', this.photoToValues(photo));
  }

  async deletePhoto(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('photos');
    predicates.equalTo('id', id);
    await this.store.delete(predicates);
  }

  // ---------------- 任务规划 ----------------

  async getTaskPlans(): Promise<TaskPlan[]> {
    const rs: relationalStore.ResultSet = await this.store.querySql(
      'SELECT * FROM task_plans ORDER BY completed ASC, created_at DESC', []);
    const list: TaskPlan[] = [];
    if (rs.goToFirstRow()) {
      do {
        list.push(this.mapTaskPlan(rs));
      } while (rs.goToNextRow());
    }
    rs.close();
    return list;
  }

  async upsertTaskPlan(plan: TaskPlan): Promise<void> {
    const existing: TaskPlan | null = await this.findTaskPlanById(plan.id);
    if (existing) {
      const values: relationalStore.ValuesBucket = {
        'title': plan.title,
        'start_date': plan.startDate,
        'planned_days': plan.plannedDays,
        'completed': plan.completed ? 1 : 0,
        'completed_at': plan.completedAt
      };
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('task_plans');
      predicates.equalTo('id', plan.id);
      await this.store.update(values, predicates);
    } else {
      await this.store.insert('task_plans', this.taskPlanToValues(plan));
    }
  }

  async deleteTaskPlan(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('task_plans');
    predicates.equalTo('id', id);
    await this.store.delete(predicates);
  }

  // ---------------- 账本 ----------------

  async getLedgerRecords(): Promise<LedgerRecord[]> {
    const rs: relationalStore.ResultSet = await this.store.querySql(
      'SELECT * FROM ledger_records ORDER BY date DESC, created_at DESC', []);
    const list: LedgerRecord[] = [];
    if (rs.goToFirstRow()) {
      do {
        list.push(this.mapLedger(rs));
      } while (rs.goToNextRow());
    }
    rs.close();
    return list;
  }

  async upsertLedgerRecord(record: LedgerRecord): Promise<void> {
    const existing: LedgerRecord | null = await this.findLedgerById(record.id);
    if (existing) {
      const values: relationalStore.ValuesBucket = {
        'date': record.date,
        'type': Number(record.type),
        'amount': record.amount,
        'category': record.category,
        'note': record.note
      };
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('ledger_records');
      predicates.equalTo('id', record.id);
      await this.store.update(values, predicates);
    } else {
      await this.store.insert('ledger_records', this.ledgerToValues(record));
    }
  }

  async deleteLedgerRecord(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('ledger_records');
    predicates.equalTo('id', id);
    await this.store.delete(predicates);
  }

  // ---------------- 习惯打卡 ----------------

  async getHabits(): Promise<Habit[]> {
    const rs: relationalStore.ResultSet = await this.store.querySql(
      'SELECT * FROM habits ORDER BY sort_order ASC, created_at ASC', []);
    const list: Habit[] = [];
    if (rs.goToFirstRow()) {
      do {
        list.push(this.mapHabit(rs));
      } while (rs.goToNextRow());
    }
    rs.close();
    return list;
  }

  async upsertHabit(habit: Habit): Promise<void> {
    const existing: Habit | null = await this.findHabitById(habit.id);
    if (existing !== null) {
      const values: relationalStore.ValuesBucket = {
        'name': habit.name,
        'sort_order': habit.sortOrder,
        'times_per_day': normalizeTimesPerDay(habit.timesPerDay),
        'slot_times': serializeSlotTimes(habit.slotTimes),
        'reminder_enabled': habit.reminderEnabled ? 1 : 0
      };
      const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('habits');
      predicates.equalTo('id', habit.id);
      await this.store.update(values, predicates);
    } else {
      await this.store.insert('habits', this.habitToValues(habit));
    }
  }

  async deleteHabit(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('habits');
    predicates.equalTo('id', id);
    await this.store.delete(predicates);
  }

  async getHabitChecks(): Promise<HabitCheck[]> {
    const rs: relationalStore.ResultSet = await this.store.querySql(
      'SELECT * FROM habit_checks ORDER BY date DESC', []);
    const list: HabitCheck[] = [];
    if (rs.goToFirstRow()) {
      do {
        list.push(this.mapHabitCheck(rs));
      } while (rs.goToNextRow());
    }
    rs.close();
    return list;
  }

  async upsertHabitCheck(check: HabitCheck): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('habit_checks');
    predicates.equalTo('habit_id', check.habitId);
    predicates.equalTo('date', check.date);
    // 一天多次：同一习惯 + 同一天 + 同一时段 才算同一条
    predicates.equalTo('slot_index', check.slotIndex);
    const values: relationalStore.ValuesBucket = {
      'id': check.id,
      'created_at': check.createdAt
    };
    const changed: number = await this.store.update(values, predicates);
    if (changed === 0) {
      await this.store.insert('habit_checks', this.habitCheckToValues(check));
    }
  }

  /** 删除某习惯某天的**全部时段**（清空数据、导入前清理都依赖这个语义） */
  async deleteHabitCheck(habitId: string, date: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('habit_checks');
    predicates.equalTo('habit_id', habitId);
    predicates.equalTo('date', date);
    await this.store.delete(predicates);
  }

  /** 只删某习惯某天的某一个时段 */
  async deleteHabitCheckSlot(habitId: string, date: string, slotIndex: number): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('habit_checks');
    predicates.equalTo('habit_id', habitId);
    predicates.equalTo('date', date);
    predicates.equalTo('slot_index', slotIndex);
    await this.store.delete(predicates);
  }

  async deleteHabitChecksOf(habitId: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('habit_checks');
    predicates.equalTo('habit_id', habitId);
    await this.store.delete(predicates);
  }

  // ---------------- 内部：查询与映射 ----------------

  private async findImportantDayById(id: string): Promise<Anniversary | null> {
    const rs: relationalStore.ResultSet = await this.store.querySql(
      'SELECT * FROM important_days WHERE id = ?', [id]);
    let item: Anniversary | null = null;
    if (rs.goToFirstRow()) {
      item = this.mapAnniversary(rs);
    }
    rs.close();
    return item;
  }

  private mapDailyLog(rs: relationalStore.ResultSet): DailyLog {
    // custom_mood / photo_uris / has_entry / tags 都是后加的列：
    // 老数据里为 NULL，列不存在时索引为 -1，都要兜底
    const customIndex: number = rs.getColumnIndex('custom_mood');
    const photoIndex: number = rs.getColumnIndex('photo_uris');
    const entryIndex: number = rs.getColumnIndex('has_entry');
    const tagIndex: number = rs.getColumnIndex('tags');
    return {
      id: rs.getString(rs.getColumnIndex('id')),
      date: rs.getString(rs.getColumnIndex('date')),
      mood: rs.getLong(rs.getColumnIndex('mood')) as Mood,
      customMood: (customIndex < 0 || rs.isColumnNull(customIndex)) ? '' : rs.getString(customIndex),
      journal: rs.getString(rs.getColumnIndex('journal')),
      plan: rs.getString(rs.getColumnIndex('plan')),
      photoUris: (photoIndex < 0 || rs.isColumnNull(photoIndex))
        ? []
        : parsePhotoUris(rs.getString(photoIndex)),
      // 迁移前的老记录没有标签列（或为 NULL）→ 空数组
      tags: (tagIndex < 0 || rs.isColumnNull(tagIndex))
        ? []
        : parseTags(rs.getString(tagIndex)),
      // 迁移前的老记录都是正常记录
      hasEntry: (entryIndex < 0 || rs.isColumnNull(entryIndex)) ? true : rs.getLong(entryIndex) === 1,
      createdAt: rs.getLong(rs.getColumnIndex('created_at')),
      updatedAt: rs.getLong(rs.getColumnIndex('updated_at'))
    };
  }

  private dailyLogToValues(log: DailyLog): relationalStore.ValuesBucket {
    const values: relationalStore.ValuesBucket = {
      'id': log.id,
      'date': log.date,
      'mood': Number(log.mood),
      'custom_mood': log.customMood,
      'journal': log.journal,
      'plan': log.plan,
      'photo_uris': serializePhotoUris(log.photoUris),
      'tags': serializeTags(log.tags),
      'has_entry': log.hasEntry ? 1 : 0,
      'created_at': log.createdAt,
      'updated_at': log.updatedAt
    };
    return values;
  }

  private mapAnniversary(rs: relationalStore.ResultSet): Anniversary {
    return {
      id: rs.getString(rs.getColumnIndex('id')),
      title: rs.getString(rs.getColumnIndex('title')),
      type: rs.getString(rs.getColumnIndex('type')),
      date: rs.getString(rs.getColumnIndex('date')),
      reminderEnabled: rs.getLong(rs.getColumnIndex('reminder_enabled')) === 1,
      createdAt: rs.getLong(rs.getColumnIndex('created_at'))
    };
  }

  private anniversaryToValues(item: Anniversary): relationalStore.ValuesBucket {
    const values: relationalStore.ValuesBucket = {
      'id': item.id,
      'title': item.title,
      'type': item.type,
      'date': item.date,
      'reminder_enabled': item.reminderEnabled ? 1 : 0,
      'created_at': item.createdAt
    };
    return values;
  }

  private mapPhoto(rs: relationalStore.ResultSet): Photo {
    return {
      id: rs.getString(rs.getColumnIndex('id')),
      uri: rs.getString(rs.getColumnIndex('uri')),
      caption: rs.getString(rs.getColumnIndex('caption')),
      date: rs.getString(rs.getColumnIndex('date')),
      createdAt: rs.getLong(rs.getColumnIndex('created_at'))
    };
  }

  private photoToValues(photo: Photo): relationalStore.ValuesBucket {
    const values: relationalStore.ValuesBucket = {
      'id': photo.id,
      'uri': photo.uri,
      'caption': photo.caption,
      'date': photo.date,
      'created_at': photo.createdAt
    };
    return values;
  }

  private async findTaskPlanById(id: string): Promise<TaskPlan | null> {
    const rs: relationalStore.ResultSet = await this.store.querySql(
      'SELECT * FROM task_plans WHERE id = ?', [id]);
    let plan: TaskPlan | null = null;
    if (rs.goToFirstRow()) {
      plan = this.mapTaskPlan(rs);
    }
    rs.close();
    return plan;
  }

  private mapTaskPlan(rs: relationalStore.ResultSet): TaskPlan {
    return {
      id: rs.getString(rs.getColumnIndex('id')),
      title: rs.getString(rs.getColumnIndex('title')),
      startDate: rs.getString(rs.getColumnIndex('start_date')),
      plannedDays: rs.getLong(rs.getColumnIndex('planned_days')),
      completed: rs.getLong(rs.getColumnIndex('completed')) === 1,
      completedAt: rs.getLong(rs.getColumnIndex('completed_at')),
      createdAt: rs.getLong(rs.getColumnIndex('created_at'))
    };
  }

  private taskPlanToValues(plan: TaskPlan): relationalStore.ValuesBucket {
    const values: relationalStore.ValuesBucket = {
      'id': plan.id,
      'title': plan.title,
      'start_date': plan.startDate,
      'planned_days': plan.plannedDays,
      'completed': plan.completed ? 1 : 0,
      'completed_at': plan.completedAt,
      'created_at': plan.createdAt
    };
    return values;
  }

  private async findLedgerById(id: string): Promise<LedgerRecord | null> {
    const rs: relationalStore.ResultSet = await this.store.querySql(
      'SELECT * FROM ledger_records WHERE id = ?', [id]);
    let record: LedgerRecord | null = null;
    if (rs.goToFirstRow()) {
      record = this.mapLedger(rs);
    }
    rs.close();
    return record;
  }

  private mapLedger(rs: relationalStore.ResultSet): LedgerRecord {
    // feeling 是后加的列：老账目一律"未标记"
    const feelingIndex: number = rs.getColumnIndex('feeling');
    return {
      id: rs.getString(rs.getColumnIndex('id')),
      date: rs.getString(rs.getColumnIndex('date')),
      type: rs.getLong(rs.getColumnIndex('type')) as LedgerType,
      amount: rs.getDouble(rs.getColumnIndex('amount')),
      category: rs.getString(rs.getColumnIndex('category')),
      note: rs.getString(rs.getColumnIndex('note')),
      feeling: (feelingIndex < 0 || rs.isColumnNull(feelingIndex))
        ? LedgerFeeling.NONE
        : rs.getLong(feelingIndex) as LedgerFeeling,
      createdAt: rs.getLong(rs.getColumnIndex('created_at'))
    };
  }

  private ledgerToValues(record: LedgerRecord): relationalStore.ValuesBucket {
    const values: relationalStore.ValuesBucket = {
      'id': record.id,
      'date': record.date,
      'type': Number(record.type),
      'amount': record.amount,
      'category': record.category,
      'note': record.note,
      'feeling': Number(record.feeling),
      'created_at': record.createdAt
    };
    return values;
  }

  private async findHabitById(id: string): Promise<Habit | null> {
    const rs: relationalStore.ResultSet = await this.store.querySql(
      'SELECT * FROM habits WHERE id = ?', [id]);
    let habit: Habit | null = null;
    if (rs.goToFirstRow()) {
      habit = this.mapHabit(rs);
    }
    rs.close();
    return habit;
  }

  private mapHabit(rs: relationalStore.ResultSet): Habit {
    // times_per_day / slot_times / reminder_enabled 都是 v7 后加的列：
    // 老数据的 times_per_day 为 NULL、slot_times 为 NULL、reminder_enabled 为 0；
    // 列不存在时索引为 -1。两种都要兜底成「每天 1 次、没有时段、不提醒」。
    const timesIndex: number = rs.getColumnIndex('times_per_day');
    const slotTimesIndex: number = rs.getColumnIndex('slot_times');
    const reminderIndex: number = rs.getColumnIndex('reminder_enabled');
    return {
      id: rs.getString(rs.getColumnIndex('id')),
      name: rs.getString(rs.getColumnIndex('name')),
      sortOrder: rs.getLong(rs.getColumnIndex('sort_order')),
      createdAt: rs.getLong(rs.getColumnIndex('created_at')),
      timesPerDay: (timesIndex < 0 || rs.isColumnNull(timesIndex))
        ? 1
        : normalizeTimesPerDay(rs.getLong(timesIndex)),
      slotTimes: (slotTimesIndex < 0 || rs.isColumnNull(slotTimesIndex))
        ? []
        : parseSlotTimes(rs.getString(slotTimesIndex)),
      reminderEnabled: (reminderIndex < 0 || rs.isColumnNull(reminderIndex))
        ? false
        : rs.getLong(reminderIndex) === 1
    };
  }

  private habitToValues(habit: Habit): relationalStore.ValuesBucket {
    const values: relationalStore.ValuesBucket = {
      'id': habit.id,
      'name': habit.name,
      'sort_order': habit.sortOrder,
      'created_at': habit.createdAt,
      'times_per_day': normalizeTimesPerDay(habit.timesPerDay),
      'slot_times': serializeSlotTimes(habit.slotTimes),
      'reminder_enabled': habit.reminderEnabled ? 1 : 0
    };
    return values;
  }

  private mapHabitCheck(rs: relationalStore.ResultSet): HabitCheck {
    // slot_index 是 v7 后加的列：老记录为 NULL（第 1 次），列不存在时索引为 -1
    const slotIndex: number = rs.getColumnIndex('slot_index');
    return {
      id: rs.getString(rs.getColumnIndex('id')),
      habitId: rs.getString(rs.getColumnIndex('habit_id')),
      date: rs.getString(rs.getColumnIndex('date')),
      createdAt: rs.getLong(rs.getColumnIndex('created_at')),
      slotIndex: (slotIndex < 0 || rs.isColumnNull(slotIndex)) ? 0 : rs.getLong(slotIndex)
    };
  }

  private habitCheckToValues(check: HabitCheck): relationalStore.ValuesBucket {
    const values: relationalStore.ValuesBucket = {
      'id': check.id,
      'habit_id': check.habitId,
      'date': check.date,
      'created_at': check.createdAt,
      'slot_index': check.slotIndex
    };
    return values;
  }
}
