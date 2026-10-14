import { common } from '@kit.AbilityKit';
import { Constants } from '../common/constants/Constants';
import { DateUtils } from '../common/utils/DateUtils';
import { DateCalcUtils } from '../common/utils/DateCalcUtils';
import { ROUTE_LOG_DETAIL, ROUTE_RECORD, dateParams } from '../common/utils/RouteUtils';
import { Mood, DailyLog, getMoodOption, hasEntry, logSummary, moodColorsByLabel, moodLabel } from '../models/DailyLog';
import {
  CalendarMark,
  EMPTY_MONTH_SUMMARY,
  MonthSummary,
  UpcomingPlan,
  buildMonthMarks,
  buildUpcomingPlans,
  daysAheadLabel,
  summarizeMonth
} from '../models/Calendar';
import { Anniversary, getAnniversaryTypeLabel } from '../models/Anniversary';
import { DEFAULT_AVATAR_ID, AvatarOption, AVATAR_OPTIONS, findAvatar } from '../models/Avatar';
import { TaskPlan, TaskProgress, computeTaskProgress } from '../models/TaskPlan';
import { SessionManager } from '../services/storage/SessionManager';
import { ThemeManager } from '../services/storage/ThemeManager';
import { AppLockManager } from '../services/storage/AppLockManager';
import { RepositoryFactory } from '../services/data/RepositoryFactory';
import { PhotoService } from '../services/PhotoService';
import { CalendarHeatmap } from '../components/CalendarHeatmap';
import { EmptyState } from '../components/EmptyState';
import { MoodDot } from '../components/MoodDot';
import { Icon, IconKind } from '../components/Icons';
import { LedgerView } from '../components/LedgerView';
import { buildExportText, saveExport } from '../services/ExportService';
import {
  ExistingCounts,
  RestoreOutcome,
  countExisting,
  describeExisting,
  pickAndParseBackup,
  restoreFromBackup
} from '../services/ImportService';
import { ImportBundle, ImportResult, describeCounts, totalCount } from '../models/Import';
import { LedgerRecord } from '../models/Ledger';
import { Habit, HabitCheck } from '../models/Habit';

interface ActiveTask {
  id: string;
  title: string;
  remainLabel: string;
  percent: number;
  remainingDays: number;
  urgent: boolean;
}

interface RecentLog {
  date: string;
  mood: Mood;
  summary: string;
}

interface ThemeOption {
  mode: number;
  label: string;
}

const THEME_OPTIONS: ThemeOption[] = [
  { mode: ThemeManager.MODE_LIGHT, label: '日间' },
  { mode: ThemeManager.MODE_DARK, label: '夜间' }
];

/**
 * 主页面：底部四 tab（首页 / 日历 / 时间轴 / 我的）
 */
@Entry
@Component
struct HomePage {
  @State private startDate: string = '';
  @State private myNickname: string = '我';
  @State private today: string = DateUtils.today();

  @State private todayChecked: boolean = false;
  @State private todayMood: Mood = Mood.HAPPY;
  @State private todayCustomMood: string = '';
  @State private todayJournal: string = '';
  @State private yesterdayPlan: string = '';
  @State private avatarId: string = DEFAULT_AVATAR_ID;
  /** 从相册选的头像；非空时优先于内置头像 */
  @State private avatarUri: string = '';
  @State private showAvatarPicker: boolean = false;

  @State private logs: DailyLog[] = [];
  @State private activeTasks: ActiveTask[] = [];
  @State private recentLogs: RecentLog[] = [];
  @State private anniversaries: Anniversary[] = [];
  @State private checkedDates: string[] = [];
  @State private streak: number = 0;
  // 日历 tab：当月每天的标记 + 月度小结，都在 refreshMonth() 里一次性算好
  @State private monthMarks: CalendarMark[] = [];
  @State private monthSummary: MonthSummary = EMPTY_MONTH_SUMMARY;
  /** 接下来几天要做的事（来自日历上给未来日期安排的） */
  @State private upcomingPlans: UpcomingPlan[] = [];
  @State private displayYear: number = 2024;
  @State private displayMonth: number = 1;
  @State private nextAnniversary: Anniversary | null = null;
  @State private nextAnniversaryDays: number = -1;
  @State private currentTab: number = 0;
  @State private themeMode: number = ThemeManager.MODE_DEFAULT;

  /** 应用锁是否已开启（「我的」入口展示状态） */
  @State private lockOn: boolean = false;

  aboutToAppear(): void {
    this.loadData();
  }

  onPageShow(): void {
    this.loadData();
    this.lockOn = AppLockManager.getInstance().isOn();
    this.gateByAppLock();
  }

  /**
   * 冷启动门禁：开了应用锁就把锁屏页压在最上面。
   * 切后台回来的情况由 EntryAbility.onForeground 统一处理（一处覆盖所有页面）。
   */
  private gateByAppLock(): void {
    if (!AppLockManager.getInstance().needsUnlock()) {
      return;
    }
    this.getUIContext().getRouter().pushUrl({ url: 'pages/LockPage' });
  }

  private async loadData(): Promise<void> {
    try {
      // 这 4 次会话读取互相独立，并发发出：原来是 4 次串行 await，
      // 每次都要等上一轮落盘回来，返回首页时的等待被叠加了 4 倍。
      const session = SessionManager.getInstance();
      const basics: string[] = await Promise.all([
        session.getStartDate(),
        session.getNickname(),
        session.getAvatarId(),
        session.getAvatarUri()
      ]);
      this.startDate = basics[0];
      this.myNickname = basics[1];
      this.avatarId = basics[2];
      this.avatarUri = basics[3];
      this.today = DateUtils.today();

      const hostContext = this.getUIContext().getHostContext();
      if (hostContext !== undefined) {
        this.themeMode = ThemeManager.getInstance().getMode(hostContext);
      }

      const repo = RepositoryFactory.getRepository();
      const logs: DailyLog[] = await repo.getDailyLogs();
      this.logs = logs;

      const dates: string[] = [];
      for (const log of logs) {
        // 只写了计划的存根不算"记录过的日子"
        if (hasEntry(log)) {
          dates.push(log.date);
        }
      }
      this.checkedDates = dates;
      this.streak = DateUtils.computeStreak(dates, this.today);

      let todayLog: DailyLog | null = null;
      for (const log of logs) {
        if (log.date === this.today && hasEntry(log)) {
          todayLog = log;
          break;
        }
      }
      this.todayChecked = todayLog !== null;
      if (todayLog) {
        this.todayMood = todayLog.mood;
        this.todayCustomMood = todayLog.customMood;
        this.todayJournal = todayLog.journal;
      } else {
        this.todayMood = Mood.HAPPY;
        this.todayCustomMood = '';
        this.todayJournal = '';
      }

      // 昨天为今天留下的计划：今天打开应用时回显，形成"计划 → 执行"的闭环
      const yesterday: string = DateUtils.addDays(this.today, -1);
      let plan: string = '';
      for (const log of logs) {
        if (log.date === yesterday) {
          plan = log.plan;
          break;
        }
      }
      this.yesterdayPlan = plan;
      this.upcomingPlans = buildUpcomingPlans(logs, this.today, 7);

      this.anniversaries = await repo.getImportantDays();
      this.computeNextAnniversary();

      const plans: TaskPlan[] = await repo.getTaskPlans();
      this.buildActiveTasks(plans);
      this.recentLogs = this.buildRecentLogs(this.logs);

      const now: Date = new Date();
      this.displayYear = now.getFullYear();
      this.displayMonth = now.getMonth() + 1;
      this.refreshMonth();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '数据加载失败', duration: 2000 });
    }
  }

  private computeNextAnniversary(): void {
    let nearest: Anniversary | null = null;
    let nearestDays: number = -1;
    for (const a of this.anniversaries) {
      const days: number = DateUtils.nextAnniversaryDays(a.date, this.today);
      if (nearestDays < 0 || days < nearestDays) {
        nearestDays = days;
        nearest = a;
      }
    }
    this.nextAnniversary = nearest;
    this.nextAnniversaryDays = nearestDays;
  }

  private goRecord(date: string): void {
    this.getUIContext().getRouter().pushUrl({
      url: ROUTE_RECORD,
      params: dateParams(date)
    });
  }

  private goDetail(date: string): void {
    this.getUIContext().getRouter().pushUrl({
      url: ROUTE_LOG_DETAIL,
      params: dateParams(date)
    });
  }

  /** 日历点选：有记录进详情；过去的空白日不给补记；今天与未来可写 */
  private handlePickDate(date: string): void {
    if (this.checkedDates.indexOf(date) >= 0) {
      this.goDetail(date);
      return;
    }
    if (DateUtils.isSealed(date, this.today)) {
      this.getUIContext().getPromptAction().showToast({
        message: '过去的空白日子不能再补记',
        duration: 2000
      });
      return;
    }
    // 未来还没到的日子：不该出现「今天的心情」「今天发生了什么」，
    // 改成去安排"那天要做什么"
    if (date > this.today) {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/DayPlanPage',
        params: dateParams(date)
      });
      return;
    }
    this.goRecord(date);
  }

  /** 首页「最近的记录」：按日期倒序取前 3 条 */
  private buildRecentLogs(logs: DailyLog[]): RecentLog[] {
    const list: RecentLog[] = [];
    for (const c of logs) {
      if (list.length >= 3) {
        break;
      }
      // 计划存根不算"最近的记录"
      if (!hasEntry(c)) {
        continue;
      }
      list.push({ date: c.date, mood: c.mood, summary: logSummary(c, 40) });
    }
    return list;
  }

  private goDayPlan(date: string): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/DayPlanPage',
      params: dateParams(date)
    });
  }

  private goLockSettings(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/LockSettingsPage' });
  }

  private goTagBrowse(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/TagBrowsePage' });
  }

  private goAnnualReport(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/AnnualReportPage' });
  }

  /** 应用锁状态文案 */
  private lockLabel(): string {
    return this.lockOn ? '已开启' : '未开启';
  }

  /**
   * 导出全部数据。
   * 数据本来就在本机，这一步是"数据自主掌控"的最后一环：换机、留档、自己看。
   * 走系统文件选择器，零权限、不联网。
   */
  private async exportAll(): Promise<void> {
    try {
      const repo = RepositoryFactory.getRepository();
      const logs: DailyLog[] = await repo.getDailyLogs();
      const ledger: LedgerRecord[] = await repo.getLedgerRecords();
      const habits: Habit[] = await repo.getHabits();
      const checks: HabitCheck[] = await repo.getHabitChecks();
      const plans: TaskPlan[] = await repo.getTaskPlans();
      const days: Anniversary[] = await repo.getImportantDays();

      const text: string = buildExportText(logs, ledger, habits, checks, plans, days);
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        this.getUIContext().getPromptAction().showToast({ message: '导出失败，请重试', duration: 2000 });
        return;
      }
      const saved: boolean = await saveExport(context, `心情手记-${this.today}.txt`, text);
      if (saved) {
        this.getUIContext().getPromptAction().showToast({
          message: '已导出，可在「文件」里找到',
          duration: 2000
        });
      }
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '导出失败，请重试', duration: 2000 });
    }
  }

  /**
   * 从备份恢复 · 第一步：选文件、读取、解析校验，然后弹二次确认。
   *
   * 导入导出都走系统文件选择器，所以整个流程依然零权限、不联网。
   * 这里刻意不在解析成功后立刻写库：覆盖是不可撤销的操作，必须让用户看清楚
   * "会覆盖现有的多少条数据"之后再决定。
   */
  private async restoreFromBackupFile(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '恢复失败，请重试', duration: 2000 });
      return;
    }

    let parsed: ImportResult | null = null;
    try {
      parsed = await pickAndParseBackup(context);
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '恢复失败，请重试', duration: 2000 });
      return;
    }
    // 用户在选择器里点了返回，什么都不做
    if (parsed === null) {
      return;
    }
    if (!parsed.ok) {
      this.getUIContext().getPromptAction().showToast({ message: parsed.error, duration: 3000 });
      return;
    }

    const summary: string = describeCounts(parsed);
    if (totalCount(parsed) === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '这个备份里没有任何数据', duration: 2500 });
      return;
    }
    // 先取出 bundle：闭包里再读 parsed.bundle 会丢掉"已判空"的信息
    const bundle: ImportBundle = parsed.bundle;

    let existing: ExistingCounts | null = null;
    try {
      existing = await countExisting();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '恢复失败，请重试', duration: 2000 });
      return;
    }

    const shown: string = existing === null ? '当前数据' : describeExisting(existing);
    this.getUIContext().showAlertDialog({
      title: '从备份恢复',
      message: `备份里有：${summary}。\n\n恢复会覆盖当前的 ${shown}，且无法撤销。`
        + `建议先导出一次当前数据留档。`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '覆盖并恢复',
        fontColor: Constants.COLOR_PRIMARY,
        action: () => {
          this.doRestore(bundle);
        }
      }
    });
  }

  /** 第二步：用户确认后清空并写入，然后重新加载界面数据 */
  private async doRestore(bundle: ImportBundle): Promise<void> {
    const result: RestoreOutcome = await restoreFromBackup(bundle);
    this.getUIContext().getPromptAction().showToast({ message: result.message, duration: 3000 });
    if (result.ok) {
      // 数据全换了：回到首页并重新读一遍，避免界面上还留着旧记录
      this.currentTab = 0;
      await this.loadData();
    }
  }

  private goAnniversary(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/AnniversaryPage' });
  }

  private goAlbum(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/AlbumPage' });
  }

  private goTaskPlan(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/TaskPlanPage' });
  }

  /** 汇总进行中的任务（最多展示 2 条，按剩余天数升序） */
  private buildActiveTasks(plans: TaskPlan[]): void {
    const today: string = this.today;
    const list: ActiveTask[] = [];
    for (const p of plans) {
      if (p.completed) {
        continue;
      }
      const progress: TaskProgress = computeTaskProgress(p, today);
      let label: string = `还剩 ${progress.remainingDays} 天`;
      if (progress.remainingDays < 0) {
        label = `已超期 ${-progress.remainingDays} 天`;
      } else if (progress.remainingDays === 0) {
        label = '今天到期';
      }
      list.push({
        id: p.id,
        title: p.title,
        remainLabel: label,
        percent: progress.percent,
        remainingDays: progress.remainingDays,
        urgent: progress.overdue
      });
    }
    // 最紧急的在前：按剩余天数升序
    list.sort((a: ActiveTask, b: ActiveTask): number => a.remainingDays - b.remainingDays);
    this.activeTasks = list.slice(0, 2);
  }

  private goStats(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/StatsPage' });
  }

  private goSearch(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/SearchPage' });
  }

  private goTimeline(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/TimelinePage' });
  }

  private goReview(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/ReviewPage' });
  }

  private goHabit(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/HabitPage' });
  }

  private async switchTheme(mode: number): Promise<void> {
    // 先把高亮切过去，让点击立刻有反馈；再落盘与应用，失败时给提示
    this.themeMode = mode;
    const ok: boolean = await ThemeManager.getInstance().setMode(mode);
    if (!ok) {
      this.getUIContext().getPromptAction().showToast({
        message: '外观切换失败，请重试',
        duration: 2000
      });
    }
  }

  /** 打开内置头像选择层 */
  private openAvatarPicker(): void {
    this.showAvatarPicker = true;
  }

  /** 选定内置头像并持久化（会清掉相册头像，保证来源唯一） */
  private async chooseAvatar(option: AvatarOption): Promise<void> {
    try {
      const session = SessionManager.getInstance();
      await session.setAvatarId(option.id);
      await session.setAvatarUri('');
      this.avatarId = option.id;
      this.avatarUri = '';
      this.showAvatarPicker = false;
      this.getUIContext().getPromptAction().showToast({ message: '头像已更新', duration: 1500 });
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '设置头像失败，请重试', duration: 2000 });
    }
  }

  /** 从相册选一张作为头像；用户取消则什么都不做 */
  private async chooseAvatarFromAlbum(): Promise<void> {
    const context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    try {
      const uri: string = await PhotoService.pickAvatar(context);
      if (uri === '') {
        return;
      }
      await SessionManager.getInstance().setAvatarUri(uri);
      this.avatarUri = uri;
      this.showAvatarPicker = false;
      this.getUIContext().getPromptAction().showToast({ message: '头像已更新', duration: 1500 });
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '设置头像失败，请重试', duration: 2000 });
    }
  }

  private prevMonth(): void {
    if (this.displayMonth === 1) {
      this.displayMonth = 12;
      this.displayYear -= 1;
    } else {
      this.displayMonth -= 1;
    }
    this.refreshMonth();
  }

  private nextMonth(): void {
    if (this.displayMonth === 12) {
      this.displayMonth = 1;
      this.displayYear += 1;
    } else {
      this.displayMonth += 1;
    }
    this.refreshMonth();
  }

  /** 重新计算当月每天的标记与月度小结 */
  private refreshMonth(): void {
    this.monthMarks = buildMonthMarks(this.logs, this.displayYear, this.displayMonth, this.today);
    this.monthSummary = summarizeMonth(this.logs, this.displayYear, this.displayMonth, this.today);
  }

  /** 月份切远了以后一键回到今天 */
  private goToday(): void {
    const now: Date = new Date();
    this.displayYear = now.getFullYear();
    this.displayMonth = now.getMonth() + 1;
    this.refreshMonth();
  }

  /** 当前浏览的是不是今天所在的月份 */
  private isCurrentMonth(): boolean {
    const now: Date = new Date();
    return this.displayYear === now.getFullYear() && this.displayMonth === now.getMonth() + 1;
  }

  @Builder
  tabBuilder(kind: string, label: string, index: number) {
    Column() {
      Icon({
        kind: kind,
        iconSize: 26,
        color: this.currentTab === index ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_TERTIARY,
        strokeW: this.currentTab === index ? 2 : 1.7
      })
      Text(label)
        .fontSize(13)
        .fontColor(this.currentTab === index ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_TERTIARY)
        .margin({ top: 2 })
    }
    .width('100%')
    .height(54)
    .justifyContent(FlexAlign.Center)
    // 避让系统底部导航条：指示条落在这一段留白里，页签不被遮挡
    .padding({ bottom: this.bottomInset })
  }

  /** 底部导航条高度，由 EntryAbility 读出来写进 AppStorage */
  @StorageProp('bottomInset') private bottomInset: number = 0;

  @Builder
  buildHomeTab() {
    Scroll() {
      Column() {
        // 今日状态英雄区：一眼看到今天的状态，点击直接进详情/记录
        Stack() {
          // 左上角一层柔光，让纯色渐变多一点质感
          Row()
            .width(180)
            .height(180)
            .borderRadius(90)
            .backgroundColor(Constants.COLOR_ON_BRAND)
            .opacity(0.12)
            .blur(32)
            .position({ x: -48, y: -72 })

          Column() {
            Row() {
            if (this.todayChecked) {
              MoodDot({ mood: this.todayMood, dotSize: 40 })
            }
            Column() {
              Text(this.todayChecked ? moodLabel(this.todayMood, this.todayCustomMood) : '今天还没记录')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(Constants.COLOR_ON_BRAND)
              Text(this.todayChecked
                ? `${this.today} ${DateCalcUtils.weekdayLabel(this.today)}`
                : '写下此刻的心情')
                .fontSize(14)
                .fontColor(Constants.COLOR_ON_BRAND)
                .opacity(0.85)
                .margin({ top: 4 })
            }
            .margin({ left: this.todayChecked ? 12 : 0 })
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text(this.todayChecked ? '看全文 ›' : '去记录 ›')
              .fontSize(14)
              .fontColor(Constants.COLOR_ON_BRAND)
              .opacity(0.9)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(`连续记录 ${this.streak} 天 · 累计 ${this.logs.length} 篇`)
            .fontSize(14)
            .fontColor(Constants.COLOR_ON_BRAND)
            .opacity(0.9)
            .margin({ top: 14 })
        }
          .width('100%')
          .padding(18)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .borderRadius(18)
        .backgroundColor(Constants.COLOR_PRIMARY)
        .border({ width: 1, color: Constants.COLOR_PRIMARY_LIGHT })
        .margin({ top: 4 })
        .clip(true)
        .onClick(() => {
          if (this.todayChecked) {
            this.goDetail(this.today);
          } else {
            this.goRecord(this.today);
          }
        })

        // 新用户引导：一篇都没记录时给三步提示，避免首页一大片空白
        if (this.logs.length === 0) {
          Column() {
            Text('三步写下第一篇')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(Constants.COLOR_TEXT_PRIMARY)
              .width('100%')

            this.buildGuideStep(1, '选一个今天的心情')
            this.buildGuideStep(2, '写下今天发生了什么')
            this.buildGuideStep(3, '给明天留几件事')

            Row() {
              Icon({ kind: IconKind.NOTE, iconSize: 20, color: Constants.COLOR_ON_BRAND })
              Text('写下第一篇记录')
                .fontSize(16)
                .fontColor(Constants.COLOR_ON_BRAND)
                .margin({ left: 8 })
            }
            .width('100%')
            .height(48)
            .borderRadius(14)
            .backgroundColor(Constants.COLOR_PRIMARY)
            .justifyContent(FlexAlign.Center)
            .margin({ top: 16 })
            .onClick(() => {
              this.goRecord(this.today);
            })
          }
          .width('100%')
          .padding(18)
          .borderRadius(16)
          .backgroundColor(Constants.COLOR_CARD)
          .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
          .margin({ top: 14 })
          .alignItems(HorizontalAlign.Start)
        }

        // 计划：今天要做的事 + 接下来几天的安排（日历上给未来日期安排的事会出现在这里）
        if (this.yesterdayPlan !== '' || this.upcomingPlans.length > 0) {
          Column() {
            if (this.yesterdayPlan !== '') {
              Row() {
                Icon({ kind: IconKind.NOTE, iconSize: 24, color: Constants.COLOR_PRIMARY })
                Text('今天要做的事')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Constants.COLOR_TEXT_PRIMARY)
                  .margin({ left: 8 })
                Blank()
              }
              .width('100%')

              Text(this.yesterdayPlan)
                .fontSize(16)
                .fontColor(Constants.COLOR_TEXT_SECONDARY)
                .width('100%')
                .margin({ top: 10 })
            }

            if (this.upcomingPlans.length > 0) {
              if (this.yesterdayPlan !== '') {
                Divider()
                  .color(Constants.COLOR_DIVIDER)
                  .margin({ top: 14, bottom: 12 })
              }

              Row() {
                Icon({ kind: IconKind.CALENDAR, iconSize: 24, color: Constants.COLOR_PRIMARY })
                Text('接下来几天')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Constants.COLOR_TEXT_PRIMARY)
                  .margin({ left: 8 })
                Blank()
              }
              .width('100%')

              ForEach(this.upcomingPlans, (item: UpcomingPlan) => {
                Row() {
                  Column() {
                    Text(`${Number(item.date.slice(5, 7))}月${Number(item.date.slice(8, 10))}日 · ${daysAheadLabel(item.daysAhead)}`)
                      .fontSize(14)
                      .fontColor(Constants.COLOR_PRIMARY)
                    Text(item.plan)
                      .fontSize(15)
                      .fontColor(Constants.COLOR_TEXT_PRIMARY)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Icon({ kind: IconKind.CHEVRON, iconSize: 18, color: Constants.COLOR_TEXT_TERTIARY })
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  this.goDayPlan(item.date);
                })
              }, (item: UpcomingPlan) => item.date)
            }
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(Constants.COLOR_SURFACE_SECONDARY)
          .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
          .margin({ top: 16 })
          .alignItems(HorizontalAlign.Start)
        }

        // 今日记录卡片
        Column() {
          Row() {
            Text('今天的记录')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_TEXT_PRIMARY)
            Blank()
            Text(this.todayChecked ? '已记录' : '未记录')
              .fontSize(15)
              .fontColor(this.todayChecked ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_TERTIARY)
          }
          .width('100%')

          if (this.todayChecked) {
            Row() {
              MoodDot({ mood: this.todayMood, dotSize: 30 })
              Column() {
                Text(moodLabel(this.todayMood, this.todayCustomMood))
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Constants.COLOR_TEXT_PRIMARY)
                if (this.todayJournal !== '') {
                  Text(this.todayJournal)
                    .fontSize(15)
                    .fontColor(Constants.COLOR_TEXT_SECONDARY)
                    .margin({ top: 4 })
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .margin({ left: 12 })
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .margin({ top: 12 })
            .alignItems(VerticalAlign.Center)
            Button('修改记录')
              .fontSize(16)
              .fontColor(Constants.COLOR_PRIMARY)
              .backgroundColor(Constants.COLOR_BACKGROUND)
              .margin({ top: 14 })
              .onClick(() => {
                this.goRecord(this.today);
              })
          } else {
            Text('今天还没有记录，写下此刻的心情吧')
              .fontSize(15)
              .fontColor(Constants.COLOR_TEXT_SECONDARY)
              .margin({ top: 10 })
            Button('记录今天')
              .width('100%')
              .height(42)
              .fontSize(17)
              .backgroundColor(Constants.COLOR_PRIMARY)
              .fontColor(Constants.COLOR_ON_BRAND)
              .margin({ top: 14 })
              .onClick(() => {
                this.goRecord(this.today);
              })
          }
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
        .margin({ top: 16 })

        // 进行中的任务
        if (this.activeTasks.length > 0) {
          Column() {
            Row() {
              Icon({ kind: IconKind.TARGET, iconSize: 18, color: Constants.COLOR_PRIMARY })
              Text('进行中的任务')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor(Constants.COLOR_TEXT_PRIMARY)
                .margin({ left: 8 })
              Blank()
              Text('全部 ›')
                .fontSize(14)
                .fontColor(Constants.COLOR_TEXT_SECONDARY)
                .onClick(() => {
                  this.goTaskPlan();
                })
            }
            .width('100%')

            ForEach(this.activeTasks, (task: ActiveTask) => {
              Column() {
                Row() {
                  Text(task.title)
                    .fontSize(16)
                    .fontColor(Constants.COLOR_TEXT_PRIMARY)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(task.remainLabel)
                    .fontSize(14)
                    .fontColor(task.urgent ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_SECONDARY)
                    .margin({ left: 8 })
                }
                .width('100%')

                Row() {
                  Row()
                    .width(`${task.percent}%`)
                    .height(6)
                    .borderRadius(3)
                    .backgroundColor(Constants.COLOR_PRIMARY)
                }
                .width('100%')
                .height(6)
                .borderRadius(3)
                .backgroundColor(Constants.COLOR_TRACK)
                .margin({ top: 8 })
              }
              .width('100%')
              .margin({ top: 14 })
              .alignItems(HorizontalAlign.Start)
            }, (task: ActiveTask) => task.id)
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(Constants.COLOR_CARD)
          .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
          .margin({ top: 16 })
          .alignItems(HorizontalAlign.Start)
        }

        // 最近的记录：首页读历史的主入口
        if (this.recentLogs.length > 0) {
          Column() {
            Row() {
              Text('最近的记录')
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor(Constants.COLOR_TEXT_PRIMARY)
              Blank()
              Text('全部 ›')
                .fontSize(14)
                .fontColor(Constants.COLOR_TEXT_SECONDARY)
                .onClick(() => {
                  this.goTimeline();
                })
            }
            .width('100%')

            ForEach(this.recentLogs, (item: RecentLog) => {
              Row() {
                MoodDot({ mood: item.mood, dotSize: 22 })
                Column() {
                  Text(item.summary)
                    .fontSize(16)
                    .fontColor(Constants.COLOR_TEXT_PRIMARY)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(item.date)
                    .fontSize(13)
                    .fontColor(Constants.COLOR_TEXT_TERTIARY)
                    .margin({ top: 3 })
                }
                .margin({ left: 12 })
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Icon({ kind: IconKind.CHEVRON, iconSize: 20, color: Constants.COLOR_TEXT_TERTIARY })
              }
              .width('100%')
              .padding({ top: 12, bottom: 12 })
              .alignItems(VerticalAlign.Center)
              .border({ width: { top: 1 }, color: Constants.COLOR_DIVIDER })
              .onClick(() => {
                this.goDetail(item.date);
              })
            }, (item: RecentLog) => item.date)
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(Constants.COLOR_CARD)
          .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
          .margin({ top: 16 })
          .alignItems(HorizontalAlign.Start)
        }

        // 纪念日预览
        if (this.nextAnniversary) {
          Row() {
            Column() {
              Icon({ kind: IconKind.GIFT, iconSize: 30, color: Constants.COLOR_PRIMARY })
              Column() {
                Text(this.nextAnniversary.title)
                  .fontSize(17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Constants.COLOR_TEXT_PRIMARY)
                Text(getAnniversaryTypeLabel(this.nextAnniversary.type))
                  .fontSize(14)
                  .fontColor(Constants.COLOR_TEXT_TERTIARY)
                  .margin({ top: 2 })
              }
              .margin({ left: 12 })
              .alignItems(HorizontalAlign.Start)
            }
            Blank()
            Column() {
              Text(this.nextAnniversaryDays === 0 ? '就是今天' : '还剩')
                .fontSize(14)
                .fontColor(Constants.COLOR_TEXT_SECONDARY)
              if (this.nextAnniversaryDays === 0) {
                Icon({ kind: IconKind.STAR, iconSize: 24, color: Constants.COLOR_PRIMARY })
              } else {
                Text(`${this.nextAnniversaryDays} 天`)
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Constants.COLOR_PRIMARY)
              }
            }
            .alignItems(HorizontalAlign.End)
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(Constants.COLOR_CARD)
          .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
          .margin({ top: 12 })
          .onClick(() => {
            this.goAnniversary();
          })
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 20 })
      .alignItems(HorizontalAlign.Start)
    }
    .scrollBar(BarState.Off)
    .backgroundColor(Constants.COLOR_BACKGROUND)
    // 内容不足一屏时也顶到最上，避免被 TabContent 垂直居中而上下留白
    .height('100%')
    .align(Alignment.Top)
  }

  /** 新用户引导里的一步：圆形序号 + 说明 */
  @Builder
  buildGuideStep(index: number, text: string) {
    Row() {
      Row() {
        Text(`${index}`)
          .fontSize(13)
          .fontColor(Constants.COLOR_ON_BRAND)
      }
      .width(22)
      .height(22)
      .borderRadius(11)
      .backgroundColor(Constants.COLOR_PRIMARY)
      .justifyContent(FlexAlign.Center)
      Text(text)
        .fontSize(15)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .margin({ left: 10 })
      Blank()
    }
    .width('100%')
    .margin({ top: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildCalendarTab() {
    Scroll() {
      Column() {
        Row() {
          Stack() {
            Icon({ kind: IconKind.BACK, iconSize: 28, color: Constants.COLOR_TEXT_PRIMARY, strokeW: 1.8 })
          }
          .padding(8)
          .onClick(() => {
            this.prevMonth();
          })
          Text(`${this.displayYear}年${this.displayMonth}月`)
            .fontSize(23)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          // 翻远了以后一键回到今天
          if (!this.isCurrentMonth()) {
            Text('回到今天')
              .fontSize(15)
              .fontColor(Constants.COLOR_PRIMARY)
              .padding(6)
              .onClick(() => {
                this.goToday();
              })
          }
          Stack() {
            Icon({ kind: IconKind.CHEVRON, iconSize: 28, color: Constants.COLOR_TEXT_PRIMARY, strokeW: 1.8 })
          }
          .padding(8)
          .onClick(() => {
            this.nextMonth();
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        CalendarHeatmap({
          year: this.displayYear,
          month: this.displayMonth,
          marks: this.monthMarks,
          today: this.today,
          onPickDate: (date: string) => {
            this.handlePickDate(date);
          }
        })
        .margin({ top: 20 })

        // 本月小结：系统日历不会告诉你的那些事
        this.buildMonthSummaryCard()

        Row() {
          Column() {
            Text(`${this.streak}`)
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_PRIMARY)
            Text('连续记录(天)')
              .fontSize(15)
              .fontColor(Constants.COLOR_TEXT_SECONDARY)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          Column() {
            Text(`${this.checkedDates.length}`)
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_PRIMARY)
            Text('累计记录(篇)')
              .fontSize(15)
              .fontColor(Constants.COLOR_TEXT_SECONDARY)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
        .margin({ top: 12 })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 20, bottom: 32 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .backgroundColor(Constants.COLOR_BACKGROUND)
  }

  /** 本月小结卡：天数 / 篇数 / 字数 + 最常出现的心情 + 与上月对比 */
  @Builder
  buildMonthSummaryCard() {
    Column() {
      Text('本月小结')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%')

      if (this.monthSummary.recordedDays === 0) {
        Text('这个月还没有记录，写下第一篇吧')
          .fontSize(15)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 12 })
      } else {
        Row() {
          this.buildMonthCell(`${this.monthSummary.recordedDays}`, '记录天数')
          this.buildMonthCell(`${this.monthSummary.entries}`, '记录篇数')
          this.buildMonthCell(`${this.monthSummary.chars}`, '本文字数')
        }
        .width('100%')
        .margin({ top: 14 })

        if (this.monthSummary.topMood !== '') {
          Row() {
            Row()
              .width(12)
              .height(12)
              .borderRadius(6)
              .backgroundColor(moodColorsByLabel(this.monthSummary.topMood)[0])
            Text(`最常出现的心情：「${this.monthSummary.topMood}」`)
              .fontSize(15)
              .fontColor(Constants.COLOR_TEXT_PRIMARY)
              .margin({ left: 8 })
            Blank()
          }
          .width('100%')
          .margin({ top: 16 })
        }
      }

      // 有记录时才显示总结，否则会和上面的空态引导文案重复一遍
      if (this.monthSummary.recordedDays > 0 && this.monthSummary.summary !== '') {
        Text(this.monthSummary.summary)
          .fontSize(15)
          .lineHeight(26)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
          .width('100%')
          .margin({ top: 12 })
      }
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
    .margin({ top: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildMonthCell(value: string, label: string) {
    Column() {
      Text(value)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_PRIMARY)
      Text(label)
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
  }

  @Builder
  buildMineGroupTitle(title: string) {
    Text(title)
      .fontSize(14)
      .fontColor(Constants.COLOR_TEXT_TERTIARY)
      .width('100%')
      .margin({ top: 18, left: 4, bottom: 2 })
  }

  @Builder
  buildMineTab() {
    Scroll() {
      Column() {
        Row() {
          Stack({ alignContent: Alignment.BottomEnd }) {
            Image(this.avatarUri !== '' ? this.avatarUri : findAvatar(this.avatarId).res)
              .width(56)
              .height(56)
              .borderRadius(28)
              .objectFit(ImageFit.Cover)
            Text('换')
              .fontSize(12)
              .fontColor(Constants.COLOR_ON_BRAND)
              .padding(4)
              .borderRadius(10)
              .backgroundColor(Constants.COLOR_PRIMARY)
              .margin({ right: 2, bottom: 2 })
          }
          .onClick(() => {
            this.openAvatarPicker();
          })
          Column() {
            Text(this.myNickname)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_TEXT_PRIMARY)
            Text('记录每一天的心情')
              .fontSize(16)
              .fontColor(Constants.COLOR_PRIMARY)
              .margin({ top: 4 })
          }
          .margin({ left: 14 })
          .alignItems(HorizontalAlign.Start)
          Blank()
        }
        .width('100%')
        .padding(20)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })

        Row() {
          Column() {
            Text(`${this.logs.length}`)
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_PRIMARY)
            Text('记录(篇)')
              .fontSize(14)
              .fontColor(Constants.COLOR_TEXT_SECONDARY)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          Column() {
            Text(`${this.streak}`)
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_PRIMARY)
            Text('连续记录(天)')
              .fontSize(14)
              .fontColor(Constants.COLOR_TEXT_SECONDARY)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          Column() {
            Text(`${this.anniversaries.length}`)
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_PRIMARY)
            Text('重要日子(个)')
              .fontSize(14)
              .fontColor(Constants.COLOR_TEXT_SECONDARY)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
        }
        .width('100%')
        .padding(20)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
        .margin({ top: 12 })

        // ---- 分组：记录 ----
        this.buildMineGroupTitle('记录')

        Row() {
          Icon({ kind: IconKind.TIMELINE, iconSize: 24, color: Constants.COLOR_PRIMARY })
          Text('时间轴')
            .fontSize(17)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .margin({ left: 10 })
          Blank()
          Icon({ kind: IconKind.CHEVRON, iconSize: 20, color: Constants.COLOR_TEXT_TERTIARY })
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
        .margin({ top: 12 })
        .onClick(() => {
          this.goTimeline();
        })

        Row() {
          Icon({ kind: IconKind.CHART, iconSize: 24, color: Constants.COLOR_PRIMARY })
          Text('本周回顾')
            .fontSize(17)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .margin({ left: 10 })
          Blank()
          Icon({ kind: IconKind.CHEVRON, iconSize: 20, color: Constants.COLOR_TEXT_TERTIARY })
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
        .margin({ top: 12 })
        .onClick(() => {
          this.goReview();
        })

        Row() {
          Icon({ kind: IconKind.CHECK, iconSize: 24, color: Constants.COLOR_PRIMARY })
          Text('习惯打卡')
            .fontSize(17)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .margin({ left: 10 })
          Blank()
          Icon({ kind: IconKind.CHEVRON, iconSize: 20, color: Constants.COLOR_TEXT_TERTIARY })
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
        .margin({ top: 12 })
        .onClick(() => {
          this.goHabit();
        })

        Row() {
          Icon({ kind: IconKind.GIFT, iconSize: 24, color: Constants.COLOR_PRIMARY })
          Text('纪念日管理')
            .fontSize(17)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .margin({ left: 10 })
          Blank()
          Icon({ kind: IconKind.CHEVRON, iconSize: 20, color: Constants.COLOR_TEXT_TERTIARY })
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
        .margin({ top: 12 })
        .onClick(() => {
          this.goAnniversary();
        })

        Row() {
          Icon({ kind: IconKind.PHOTO, iconSize: 24, color: Constants.COLOR_PRIMARY })
          Text('记录里的照片')
            .fontSize(17)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .margin({ left: 10 })
          Blank()
          Icon({ kind: IconKind.CHEVRON, iconSize: 20, color: Constants.COLOR_TEXT_TERTIARY })
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
        .margin({ top: 12 })
        .onClick(() => {
          this.goAlbum();
        })

        Row() {
          Icon({ kind: IconKind.SEARCH, iconSize: 24, color: Constants.COLOR_PRIMARY })
          Text('搜索日记')
            .fontSize(17)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .margin({ left: 10 })
          Blank()
          Icon({ kind: IconKind.CHEVRON, iconSize: 20, color: Constants.COLOR_TEXT_TERTIARY })
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
        .margin({ top: 12 })
        .onClick(() => {
          this.goSearch();
        })

        Row() {
          Icon({ kind: IconKind.STAR, iconSize: 24, color: Constants.COLOR_PRIMARY })
          Text('标签浏览')
            .fontSize(17)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .margin({ left: 10 })
          Blank()
          Icon({ kind: IconKind.CHEVRON, iconSize: 20, color: Constants.COLOR_TEXT_TERTIARY })
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
        .margin({ top: 12 })
        .onClick(() => {
          this.goTagBrowse();
        })

        Row() {
          Icon({ kind: IconKind.CHART, iconSize: 24, color: Constants.COLOR_PRIMARY })
          Text('年度报告')
            .fontSize(17)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .margin({ left: 10 })
          Blank()
          Icon({ kind: IconKind.CHEVRON, iconSize: 20, color: Constants.COLOR_TEXT_TERTIARY })
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
        .margin({ top: 12 })
        .onClick(() => {
          this.goAnnualReport();
        })

        // ---- 分组：工具 ----
        this.buildMineGroupTitle('工具')

        Row() {
          Icon({ kind: IconKind.TARGET, iconSize: 24, color: Constants.COLOR_PRIMARY })
          Text('任务规划')
            .fontSize(17)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .margin({ left: 10 })
          Blank()
          Icon({ kind: IconKind.CHEVRON, iconSize: 20, color: Constants.COLOR_TEXT_TERTIARY })
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
        .margin({ top: 12 })
        .onClick(() => {
          this.goTaskPlan();
        })

        Row() {
          Icon({ kind: IconKind.CHART, iconSize: 24, color: Constants.COLOR_PRIMARY })
          Text('数据统计')
            .fontSize(17)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .margin({ left: 10 })
          Blank()
          Icon({ kind: IconKind.CHEVRON, iconSize: 20, color: Constants.COLOR_TEXT_TERTIARY })
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
        .margin({ top: 12 })
        .onClick(() => {
          this.goStats();
        })

        Row() {
          Icon({ kind: IconKind.NOTE, iconSize: 24, color: Constants.COLOR_PRIMARY })
          Text('导出我的数据')
            .fontSize(17)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .margin({ left: 10 })
          Blank()
          Text('TXT')
            .fontSize(14)
            .fontColor(Constants.COLOR_TEXT_TERTIARY)
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
        .margin({ top: 12 })
        .onClick(() => {
          this.exportAll();
        })

        Row() {
          Icon({ kind: IconKind.CHECK, iconSize: 24, color: Constants.COLOR_PRIMARY })
          Text('从备份恢复')
            .fontSize(17)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .margin({ left: 10 })
          Blank()
          Text('JSON')
            .fontSize(14)
            .fontColor(Constants.COLOR_TEXT_TERTIARY)
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
        .margin({ top: 12 })
        .onClick(() => {
          this.restoreFromBackupFile();
        })

        // ---- 分组：安全 ----
        this.buildMineGroupTitle('安全')

        Row() {
          Icon({ kind: IconKind.LOCK, iconSize: 24, color: Constants.COLOR_PRIMARY })
          Text('应用锁')
            .fontSize(17)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .margin({ left: 10 })
          Blank()
          Text(this.lockLabel())
            .fontSize(15)
            .fontColor(this.lockOn ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_TERTIARY)
            .margin({ right: 6 })
          Icon({ kind: IconKind.CHEVRON, iconSize: 20, color: Constants.COLOR_TEXT_TERTIARY })
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
        .margin({ top: 12 })
        .stateStyles({
          pressed: {
            .opacity(0.75)
          }
        })
        .onClick(() => {
          this.goLockSettings();
        })

        // ---- 分组：外观 ----
        this.buildMineGroupTitle('外观')

        // 日夜模式切换
        Column() {
          Row() {
            Icon({ kind: IconKind.THEME, iconSize: 24, color: Constants.COLOR_PRIMARY })
            Text('日夜模式')
              .fontSize(17)
              .fontColor(Constants.COLOR_TEXT_PRIMARY)
              .margin({ left: 10 })
            Blank()
          }
          .width('100%')

          Row() {
            ForEach(THEME_OPTIONS, (option: ThemeOption) => {
              Text(option.label)
                .fontSize(15)
                .fontColor(this.themeMode === option.mode ? Constants.COLOR_ON_BRAND : Constants.COLOR_TEXT_SECONDARY)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .padding({ top: 8, bottom: 8 })
                .borderRadius(9)
                .backgroundColor(this.themeMode === option.mode ? Constants.COLOR_PRIMARY : Constants.COLOR_TRANSPARENT)
                .onClick(() => {
                  this.switchTheme(option.mode);
                })
            }, (option: ThemeOption) => `${option.mode}`)
          }
          .width('100%')
          .padding(4)
          .borderRadius(12)
          .backgroundColor(Constants.COLOR_TRACK)
          .margin({ top: 12 })
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
        .margin({ top: 12 })

      }
      .width('100%')
      .padding(20)
      .alignItems(HorizontalAlign.Start)
    }
    .scrollBar(BarState.Off)
    .backgroundColor(Constants.COLOR_BACKGROUND)
  }

  @Builder
  buildAvatarPicker() {
    Column() {
      Column()
        .width('100%')
        .layoutWeight(1)
        .onClick(() => {
          this.showAvatarPicker = false;
        })

      Column() {
        Text('选择头像')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
          .width('100%')
        Text('从下面挑一个，也可以从相册选自己的照片')
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 4 })

        Grid() {
          ForEach(AVATAR_OPTIONS, (option: AvatarOption) => {
            GridItem() {
              Column() {
                Image(option.res)
                  .width(52)
                  .height(52)
                  .borderRadius(26)
                  .objectFit(ImageFit.Cover)
                  .border({
                    width: this.avatarId === option.id ? 2 : 1,
                    color: this.avatarId === option.id ? Constants.COLOR_PRIMARY : Constants.COLOR_DIVIDER
                  })
              }
              .width('100%')
              .height(64)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                this.chooseAvatar(option);
              })
            }
          }, (option: AvatarOption) => option.id)

        }
        .columnsTemplate('1fr 1fr 1fr')
        .rowsGap(8)
        .columnsGap(8)
        .width('100%')
        .height(136)
        .margin({ top: 14 })

        // 从相册选一张自己的照片：做成满宽按钮，比挤在网格最后一格更清楚
        Row() {
          Icon({ kind: IconKind.PHOTO, iconSize: 24, color: Constants.COLOR_PRIMARY })
          Text('从相册选一张自己的照片')
            .fontSize(15)
            .fontColor(Constants.COLOR_PRIMARY)
            .margin({ left: 8 })
        }
        .width('100%')
        .height(48)
        .borderRadius(14)
        .backgroundColor(Constants.COLOR_BACKGROUND)
        .border({
          width: this.avatarUri !== '' ? 2 : 1,
          color: this.avatarUri !== '' ? Constants.COLOR_PRIMARY : Constants.COLOR_DIVIDER
        })
        .justifyContent(FlexAlign.Center)
        .margin({ top: 14 })
        .onClick(() => {
          this.chooseAvatarFromAlbum();
        })

        Button('取消')
          .width('100%')
          .height(42)
          .fontSize(17)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
          .backgroundColor(Constants.COLOR_BACKGROUND)
          .margin({ top: 10 })
          .onClick(() => {
            this.showAvatarPicker = false;
          })
      }
      .width('100%')
      .padding(20)
      .borderRadius({ topLeft: 20, topRight: 20 })
      .backgroundColor(Constants.COLOR_CARD)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Tabs({ barPosition: BarPosition.End }) {
        TabContent() {
          this.buildHomeTab()
        }
        .tabBar(this.tabBuilder(IconKind.HOME, '首页', 0))

        TabContent() {
          this.buildCalendarTab()
        }
        .tabBar(this.tabBuilder(IconKind.CALENDAR, '记录日历', 1))

        TabContent() {
          LedgerView({ active: this.currentTab === 2 })
        }
        .tabBar(this.tabBuilder(IconKind.WALLET, '账本', 2))

        TabContent() {
          this.buildMineTab()
        }
        .tabBar(this.tabBuilder(IconKind.MINE, '我的', 3))
      }
      .scrollable(false)
      .barHeight(60 + this.bottomInset)
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        this.currentTab = index;
      })

      if (this.showAvatarPicker) {
        this.buildAvatarPicker()
      }

      // 悬浮按钮：随时记下今天（避开底部导航栏）
      if (this.currentTab === 0 && !this.showAvatarPicker) {
        Stack() {
          Icon({ kind: IconKind.PLUS, iconSize: 28, color: Constants.COLOR_ON_BRAND, strokeW: 2.2 })
        }
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor(Constants.COLOR_HERO_START)
        .shadow({ radius: 16, color: Constants.COLOR_SHADOW, offsetY: 6 })
        .margin({ right: 20, bottom: 84 })
        .onClick(() => {
          this.goRecord(DateUtils.today());
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
