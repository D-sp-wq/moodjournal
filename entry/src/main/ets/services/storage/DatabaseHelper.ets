import relationalStore from '@ohos.data.relationalStore';
import { BusinessError } from '@ohos.base';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { Constants } from '../../common/constants/Constants';

/**
 * 关系型数据库单例：负责 RDB 初始化与建表
 *
 * 单用户模型：不再有 users / couples 表；昵称、头像、开始记录日期由 SessionManager
 * 的偏好存储承担。每天一条记录由 daily_logs.date 的唯一约束保证。
 */
export class DatabaseHelper {
  /** 数据库结构版本。每次改表结构都要 +1，并在 migrate() 里补上对应语句。 */
  private static readonly DB_VERSION: number = 6;

  private static instance: DatabaseHelper | undefined = undefined;
  private store: relationalStore.RdbStore | undefined = undefined;

  private constructor() {
  }

  static getInstance(): DatabaseHelper {
    if (!DatabaseHelper.instance) {
      DatabaseHelper.instance = new DatabaseHelper();
    }
    return DatabaseHelper.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.store) {
      return;
    }
    try {
      const config: relationalStore.StoreConfig = {
        name: Constants.DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      };
      this.store = await relationalStore.getRdbStore(context, config);
      await this.createTables();
      await this.migrate();
      hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '数据库初始化成功');
    } catch (err) {
      const businessError = err as BusinessError;
      hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, '数据库初始化失败: %{public}s', businessError.message);
      throw new Error(businessError.message);
    }
  }

  getStore(): relationalStore.RdbStore {
    if (!this.store) {
      throw new Error('数据库尚未初始化，请先调用 init()');
    }
    return this.store;
  }

  private async createTables(): Promise<void> {
    const store = this.getStore();
    const sqls: string[] = [
      `CREATE TABLE IF NOT EXISTS daily_logs (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL UNIQUE,
        mood INTEGER NOT NULL,
        custom_mood TEXT,
        journal TEXT,
        plan TEXT,
        photo_uris TEXT,
        tags TEXT,
        has_entry INTEGER,
        created_at INTEGER,
        updated_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS important_days (
        id TEXT PRIMARY KEY,
        title TEXT,
        type TEXT,
        date TEXT,
        reminder_enabled INTEGER,
        created_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS photos (
        id TEXT PRIMARY KEY,
        uri TEXT,
        caption TEXT,
        date TEXT,
        created_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS task_plans (
        id TEXT PRIMARY KEY,
        title TEXT,
        start_date TEXT,
        planned_days INTEGER,
        completed INTEGER,
        completed_at INTEGER,
        created_at INTEGER
      )`,
      // 账本：与每日记录完全独立。新增"表"不需要迁移语句，
      // 因为建表用的是 IF NOT EXISTS，每次启动都会补齐。
      `CREATE TABLE IF NOT EXISTS ledger_records (
        id TEXT PRIMARY KEY,
        date TEXT,
        type INTEGER,
        amount REAL,
        category TEXT,
        note TEXT,
        feeling INTEGER,
        created_at INTEGER
      )`,
      // 习惯打卡：习惯定义 + 每天一条打卡记录（同一习惯同一天只有一条）
      `CREATE TABLE IF NOT EXISTS habits (
        id TEXT PRIMARY KEY,
        name TEXT,
        sort_order INTEGER,
        created_at INTEGER
      )`,
      `CREATE TABLE IF NOT EXISTS habit_checks (
        id TEXT PRIMARY KEY,
        habit_id TEXT,
        date TEXT,
        created_at INTEGER
      )`
    ];
    for (let i: number = 0; i < sqls.length; i++) {
      await store.executeSql(sqls[i]);
    }
  }

  /**
   * 结构迁移。
   *
   * 历史版本只用 CREATE TABLE IF NOT EXISTS 建表，对已存在的表加列**不会生效**，
   * 所以这里按版本号补列，补完把版本写回，后续启动就不再执行。
   * 列已经存在时 ALTER 会抛错（全新安装的建表语句已带上该列），属正常情况，忽略即可。
   */
  private async migrate(): Promise<void> {
    const store = this.getStore();
    if (store.version >= DatabaseHelper.DB_VERSION) {
      return;
    }
    try {
      await store.executeSql('ALTER TABLE daily_logs ADD COLUMN custom_mood TEXT');
    } catch (err) {
      // 列已存在，无需处理
    }
    try {
      await store.executeSql('ALTER TABLE daily_logs ADD COLUMN photo_uris TEXT');
    } catch (err) {
      // 列已存在，无需处理
    }
    try {
      // 老数据全都是正常记录，所以默认 1；只有"只写了计划的存根"才是 0
      await store.executeSql('ALTER TABLE daily_logs ADD COLUMN has_entry INTEGER DEFAULT 1');
    } catch (err) {
      // 列已存在，无需处理
    }
    try {
      // 账本"感受"：老账目一律未标记
      await store.executeSql('ALTER TABLE ledger_records ADD COLUMN feeling INTEGER DEFAULT 0');
    } catch (err) {
      // 表或列不存在（例如还未记账过），无需处理
    }
    try {
      // 标签（JSON 字符串）：老数据为 NULL，读取时兜底为空数组
      await store.executeSql('ALTER TABLE daily_logs ADD COLUMN tags TEXT');
    } catch (err) {
      // 列已存在，无需处理
    }
    store.version = DatabaseHelper.DB_VERSION;
  }
}
