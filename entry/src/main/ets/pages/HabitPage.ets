import { Constants } from '../common/constants/Constants';
import { DateUtils } from '../common/utils/DateUtils';
import { IdUtils } from '../common/utils/IdUtils';
import {
  HABIT_WINDOW_DAYS,
  Habit,
  HabitCheck,
  HabitDay,
  HabitProgress,
  MAX_HABITS,
  MAX_HABIT_NAME_LENGTH,
  MAX_HABIT_TIMES,
  buildHabitDays,
  computeHabitProgress,
  countDoneSlots,
  formatSlotTime,
  fullyDoneDates,
  isHabitFullyDone,
  isValidSlotTime,
  normalizeHabitName,
  normalizeSlotTimes,
  normalizeTimesPerDay,
  remainingHabitSlots
} from '../models/Habit';
import { Repository } from '../services/data/Repository';
import { RepositoryFactory } from '../services/data/RepositoryFactory';
import { HabitReminderService } from '../services/HabitReminderService';
import { Icon, IconKind } from '../components/Icons';

/** 每天几次的选项（与 MAX_HABIT_TIMES 一致） */
const HABIT_TIMES_OPTIONS: number[] = [1, 2, 3, 4];

/**
 * 习惯打卡页：每天勾一下自己的习惯，看连续天数与近 30 天完成情况。
 *
 * 手机系统只有"运动健康"那种特定打卡，管不了读书、喝水、早睡这类自定义习惯，
 * 所以这一块是系统做不到的（应用商店审核指南 3.5 正好排除「系统自带的简易功能」）。
 * 全部本地存储，不联网、不需要任何权限。
 *
 * 一个习惯一天可以打多次（timesPerDay，最多 MAX_HABIT_TIMES），每个时段可选定时提醒。
 * 统计口径统一为「当天全部次数都完成才算这一天完成」：
 * 先由 fullyDoneDates() 折算成日期数组，再交给 computeHabitStreak / computeHabitProgress /
 * buildHabitDays 这些未改动的纯函数，所以老数据（一天一次）的统计结果与以前完全一致。
 */
@Entry
@Component
struct HabitPage {
  @State private habits: Habit[] = [];
  @State private checks: HabitCheck[] = [];
  @State private loaded: boolean = false;
  // 新增 / 编辑习惯共用一个卡片：editorHabitId 为空表示新增
  @State private editorOpen: boolean = false;
  @State private editorHabitId: string = '';
  @State private draftName: string = '';
  @State private draftTimes: number = 1;
  @State private draftSlots: string[] = [];
  @State private draftReminder: boolean = false;
  @State private saving: boolean = false;
  // 下面几组按 habits 的下标对齐，在 load() 里一次性算好。
  // 之前是在每个习惯的每次渲染里现算（还要把全部打卡记录重新分组），非常浪费。
  @State private streaks: number[] = [];
  @State private rates: number[] = [];
  @State private doneFlags: boolean[] = [];
  /** 今天每个习惯完成了几个时段 */
  @State private doneCounts: number[] = [];
  /** 今天每个习惯每个时段是否已打卡（与 habits 下标对齐，内层长度 = timesPerDay） */
  @State private doneSlots: boolean[][] = [];
  @State private strips: HabitDay[][] = [];

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      const repo = RepositoryFactory.getRepository();
      this.habits = await repo.getHabits();
      this.checks = await repo.getHabitChecks();
      this.recompute();
    } catch (err) {
      this.habits = [];
      this.checks = [];
      this.recompute();
    } finally {
      this.loaded = true;
    }
  }

  private today(): string {
    return DateUtils.today();
  }

  /**
   * 一次性把每个习惯的连续天数 / 完成率 / 今天完成情况 / 30 天条带都算好。
   *
   * 多时段折算只在这里做一次：fullyDoneDates() 给出「全天打满」的日期，
   * 后面三个纯函数完全不用知道「一天几次」这回事。
   */
  private recompute(): void {
    const today: string = this.today();
    const fully: Map<string, string[]> = fullyDoneDates(this.habits, this.checks);
    // 今天每个时段是否已打卡：一次遍历建成集合，避免每个圆点都去扫一遍全部记录
    const doneKeys: Set<string> = new Set();
    for (const check of this.checks) {
      doneKeys.add(`${check.habitId}|${check.date}|${check.slotIndex}`);
    }
    const streaks: number[] = [];
    const rates: number[] = [];
    const doneFlags: boolean[] = [];
    const doneCounts: number[] = [];
    const doneSlots: boolean[][] = [];
    const strips: HabitDay[][] = [];
    for (const habit of this.habits) {
      const dates: string[] | undefined = fully.get(habit.id);
      const own: string[] = dates === undefined ? [] : dates;
      const progress: HabitProgress = computeHabitProgress(habit.id, own, today, HABIT_WINDOW_DAYS);
      streaks.push(progress.streak);
      rates.push(progress.rate);
      doneFlags.push(isHabitFullyDone(this.checks, habit.id, today, habit.timesPerDay));
      doneCounts.push(countDoneSlots(this.checks, habit.id, today, habit.timesPerDay));
      const total: number = normalizeTimesPerDay(habit.timesPerDay);
      const flags: boolean[] = [];
      for (let i: number = 0; i < total; i++) {
        flags.push(doneKeys.has(`${habit.id}|${today}|${i}`));
      }
      doneSlots.push(flags);
      strips.push(buildHabitDays(own, today, HABIT_WINDOW_DAYS));
    }
    this.streaks = streaks;
    this.rates = rates;
    this.doneFlags = doneFlags;
    this.doneCounts = doneCounts;
    this.doneSlots = doneSlots;
    this.strips = strips;
  }

  private doneTodayAt(index: number): boolean {
    return index < this.doneFlags.length ? this.doneFlags[index] : false;
  }

  private streakAt(index: number): number {
    return index < this.streaks.length ? this.streaks[index] : 0;
  }

  private rateAt(index: number): number {
    return index < this.rates.length ? this.rates[index] : 0;
  }

  private doneCountAt(index: number): number {
    return index < this.doneCounts.length ? this.doneCounts[index] : 0;
  }

  private stripAt(index: number): HabitDay[] {
    return index < this.strips.length ? this.strips[index] : [];
  }

  /** 某个习惯今天第 slotIndex 个时段是否已打卡 */
  private slotDoneAt(habitIndex: number, slotIndex: number): boolean {
    const flags: boolean[] = habitIndex < this.doneSlots.length ? this.doneSlots[habitIndex] : [];
    return slotIndex < flags.length ? flags[slotIndex] : false;
  }

  private habitTimes(habit: Habit): number {
    return normalizeTimesPerDay(habit.timesPerDay);
  }

  /** 圆点是第几个时段（0..N-1），ForEach 需要数组 */
  private slotIndexes(habit: Habit): number[] {
    const total: number = this.habitTimes(habit);
    const out: number[] = [];
    for (let i: number = 0; i < total; i++) {
      out.push(i);
    }
    return out;
  }

  /** 今天已完成几个（全天打满的习惯数） */
  private doneCount(): number {
    let count: number = 0;
    for (const flag of this.doneFlags) {
      if (flag) {
        count += 1;
      }
    }
    return count;
  }

  private slots(): number {
    return remainingHabitSlots(this.habits.length);
  }

  /** 勾选 / 取消勾选今天第 slotIndex 个时段 */
  private async toggleSlot(habitIndex: number, habit: Habit, slotIndex: number): Promise<void> {
    const date: string = this.today();
    try {
      const repo = RepositoryFactory.getRepository();
      if (this.slotDoneAt(habitIndex, slotIndex)) {
        await repo.deleteHabitCheckSlot(habit.id, date, slotIndex);
      } else {
        await repo.upsertHabitCheck({
          id: IdUtils.generate('check'),
          habitId: habit.id,
          date: date,
          createdAt: Date.now(),
          slotIndex: slotIndex
        });
      }
      // 打卡只影响今日进度，不影响提醒排期（提醒是每天固定时刻），所以这里不调 sync
      await this.load();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '打卡失败，请重试', duration: 2000 });
    }
  }

  // ---------------- 新增 / 编辑习惯 ----------------

  private findHabitById(id: string): Habit | null {
    if (id === '') {
      return null;
    }
    for (const habit of this.habits) {
      if (habit.id === id) {
        return habit;
      }
    }
    return null;
  }

  /** 新时段的默认时间：08:00 / 09:00 / 10:00 / 11:00，保证开启提醒时马上可用 */
  private defaultSlotTime(index: number): string {
    return formatSlotTime(8 + index, 0);
  }

  private openAdd(): void {
    this.editorHabitId = '';
    this.draftName = '';
    this.draftTimes = 1;
    this.draftSlots = [this.defaultSlotTime(0)];
    this.draftReminder = false;
    this.editorOpen = true;
  }

  private openEdit(habit: Habit): void {
    const total: number = this.habitTimes(habit);
    const times: string[] = normalizeSlotTimes(total, habit.slotTimes);
    const slots: string[] = [];
    for (let i: number = 0; i < total; i++) {
      // 老数据没有时段：给个默认时间，用户不动也能直接开提醒
      slots.push(isValidSlotTime(times[i]) ? times[i] : this.defaultSlotTime(i));
    }
    this.editorHabitId = habit.id;
    this.draftName = habit.name;
    this.draftTimes = total;
    this.draftSlots = slots;
    this.draftReminder = habit.reminderEnabled;
    this.editorOpen = true;
  }

  private closeEditor(): void {
    this.editorOpen = false;
    this.editorHabitId = '';
    this.draftName = '';
    this.draftTimes = 1;
    this.draftSlots = [];
    this.draftReminder = false;
  }

  private setDraftTimes(times: number): void {
    const total: number = normalizeTimesPerDay(times);
    if (total === this.draftTimes) {
      return;
    }
    const next: string[] = [];
    for (let i: number = 0; i < total; i++) {
      const old: string = i < this.draftSlots.length ? this.draftSlots[i] : '';
      next.push(isValidSlotTime(old) ? old : this.defaultSlotTime(i));
    }
    this.draftTimes = total;
    this.draftSlots = next;
  }

  /**
   * 选某个时段的时分。
   * TimePickerDialog.show() 在新版 API 里已标记 deprecated，但项目现有的
   * ReminderSettingsPage 用的就是同一套 API，这里沿用（避免为了选个时间引入新依赖/权限）。
   */
  private pickSlotTime(index: number): void {
    const current: string = index < this.draftSlots.length ? this.draftSlots[index] : '';
    const valid: boolean = isValidSlotTime(current);
    const hour: number = valid ? Number(current.slice(0, 2)) : 8;
    const minute: number = valid ? Number(current.slice(3, 5)) : 0;
    const selected: Date = new Date();
    selected.setHours(hour, minute, 0, 0);
    TimePickerDialog.show({
      selected: selected,
      format: TimePickerFormat.HOUR_MINUTE,
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        this.applySlotTime(index, value.hour, value.minute);
      }
    });
  }

  private applySlotTime(index: number, hour: number, minute: number): void {
    const next: string[] = [];
    for (let i: number = 0; i < this.draftTimes; i++) {
      if (i === index) {
        next.push(formatSlotTime(hour, minute));
      } else {
        const old: string = i < this.draftSlots.length ? this.draftSlots[i] : '';
        next.push(old);
      }
    }
    this.draftSlots = next;
  }

  /** 编辑器里第 index 个时段显示的文字 */
  private draftSlotText(index: number): string {
    const text: string = index < this.draftSlots.length ? this.draftSlots[index] : '';
    return isValidSlotTime(text) ? text : '未设置';
  }

  private draftSlotIndexes(): number[] {
    const out: number[] = [];
    for (let i: number = 0; i < this.draftTimes; i++) {
      out.push(i);
    }
    return out;
  }

  /** 保存编辑器（新增 / 编辑共用校验） */
  private async submitEditor(): Promise<void> {
    const name: string = normalizeHabitName(this.draftName);
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '给这个习惯起个名字', duration: 2000 });
      return;
    }
    const total: number = normalizeTimesPerDay(this.draftTimes);
    const slots: string[] = normalizeSlotTimes(total, this.draftSlots);
    if (this.draftReminder) {
      for (let i: number = 0; i < total; i++) {
        if (!isValidSlotTime(slots[i])) {
          this.getUIContext().getPromptAction().showToast({
            message: `请先给第 ${i + 1} 个时段设置时间`,
            duration: 2000
          });
          return;
        }
      }
    }
    const existing: Habit | null = this.findHabitById(this.editorHabitId);
    if (existing === null && this.slots() <= 0) {
      this.getUIContext().getPromptAction().showToast({
        message: `最多同时坚持 ${MAX_HABITS} 个习惯`,
        duration: 2000
      });
      return;
    }
    if (this.saving) {
      return;
    }
    this.saving = true;
    try {
      const repo: Repository = RepositoryFactory.getRepository();
      if (existing === null) {
        await this.addHabit(repo, name, total, slots);
      } else {
        await this.updateHabit(repo, existing, name, total, slots);
      }
      this.closeEditor();
      await this.load();
      // 习惯配置变了，重排提醒（异步不 await，不卡界面）
      HabitReminderService.sync();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试', duration: 2000 });
    } finally {
      this.saving = false;
    }
  }

  /** 新增习惯：名称 + 每天次数 + 每个时段的时间 + 提醒开关 */
  private async addHabit(repo: Repository, name: string, total: number,
    slots: string[]): Promise<void> {
    await repo.upsertHabit({
      id: IdUtils.generate('habit'),
      name: name,
      sortOrder: this.habits.length,
      createdAt: Date.now(),
      timesPerDay: total,
      slotTimes: slots,
      reminderEnabled: this.draftReminder
    });
  }

  /** 编辑习惯：id / sortOrder / createdAt 保持不变 */
  private async updateHabit(repo: Repository, habit: Habit, name: string, total: number,
    slots: string[]): Promise<void> {
    await repo.upsertHabit({
      id: habit.id,
      name: name,
      sortOrder: habit.sortOrder,
      createdAt: habit.createdAt,
      timesPerDay: total,
      slotTimes: slots,
      reminderEnabled: this.draftReminder
    });
  }

  private confirmDelete(habit: Habit): void {
    this.getUIContext().showAlertDialog({
      title: '删除这个习惯',
      message: `「${habit.name}」以及它的全部打卡记录都会被删除，无法恢复。`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Constants.COLOR_PRIMARY,
        action: () => {
          this.doDelete(habit.id);
        }
      }
    });
  }

  private async doDelete(id: string): Promise<void> {
    try {
      const repo = RepositoryFactory.getRepository();
      await repo.deleteHabit(id);
      await repo.deleteHabitChecksOf(id);
      if (this.editorHabitId === id) {
        this.closeEditor();
      }
      await this.load();
      // 习惯删了，它名下的提醒也要撤掉
      HabitReminderService.sync();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败，请重试', duration: 2000 });
    }
  }

  @Builder
  private buildHeader() {
    Stack() {
      Text('习惯打卡')
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_ON_BRAND)
      Row() {
        Stack() {
          Icon({ kind: IconKind.BACK, iconSize: 30, color: Constants.COLOR_ON_BRAND, strokeW: 2.4 })
        }
        .padding(12)
        .margin({ left: -6 })
        .onClick(() => {
          this.getUIContext().getRouter().back();
        })
        Blank()
      }
      .width('100%')
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
  }

  /** 今天已完成几个（全天打满才算完成） */
  @Builder
  private buildTodayCard() {
    Column() {
      Row() {
        Text('今天')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
        Blank()
        Text(`${this.doneCount()} / ${this.habits.length}`)
          .fontSize(15)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
      }
      .width('100%')
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildHabitRow(habit: Habit, index: number) {
    Column() {
      Row() {
        Column() {
          Text(habit.name)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
          Text(this.streakAt(index) > 0
            ? `完成 ${this.doneCountAt(index)}/${this.habitTimes(habit)} 次 · 连续 ${this.streakAt(index)} 天 · 近 30 天 ${this.rateAt(index)}%`
            : `完成 ${this.doneCountAt(index)}/${this.habitTimes(habit)} 次 · 近 30 天 ${this.rateAt(index)}%`)
            .fontSize(14)
            .fontColor(this.doneTodayAt(index) ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_SECONDARY)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        // 点文字区域进入编辑（点圆点只切换对应时段，不会进编辑）
        .onClick(() => {
          this.openEdit(habit);
        })

        // 一天 N 次：一行 N 个圆点，点第 i 个切换第 i 个时段
        Row() {
          ForEach(this.slotIndexes(habit), (slotIndex: number) => {
            this.buildSlotDot(index, habit, slotIndex)
          }, (slotIndex: number) => `${habit.id}-${slotIndex}`)
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 近 30 天条带：一天一格（当天打满才算完成）
      Row() {
        ForEach(this.stripAt(index), (day: HabitDay) => {
          Column()
            .layoutWeight(1)
            .height(10)
            .borderRadius(3)
            .backgroundColor(day.done ? Constants.COLOR_PRIMARY : Constants.COLOR_TRACK)
            .margin({ right: 2 })
        }, (day: HabitDay) => day.date)
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .margin({ top: 12 })
    .alignItems(HorizontalAlign.Start)
    .gesture(
      LongPressGesture()
        .onAction(() => {
          this.confirmDelete(habit);
        })
    )
  }

  @Builder
  private buildSlotDot(habitIndex: number, habit: Habit, slotIndex: number) {
    Stack() {
      if (this.slotDoneAt(habitIndex, slotIndex)) {
        Icon({ kind: IconKind.CHECK, iconSize: 15, color: Constants.COLOR_ON_BRAND, strokeW: 2.6 })
      } else if (this.habitTimes(habit) > 1) {
        // 多次习惯在未打卡的圆点里标序号，用户能分清点的是第几次
        Text(`${slotIndex + 1}`)
          .fontSize(11)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
      }
    }
    .width(34)
    .height(34)
    .borderRadius(17)
    .backgroundColor(this.slotDoneAt(habitIndex, slotIndex)
      ? Constants.COLOR_PRIMARY
      : Constants.COLOR_BACKGROUND)
    .border({
      width: this.slotDoneAt(habitIndex, slotIndex) ? 0 : 1,
      color: Constants.COLOR_DIVIDER
    })
    // 打卡时轻微放大，给一点即时反馈
    .scale({
      x: this.slotDoneAt(habitIndex, slotIndex) ? 1 : 0.94,
      y: this.slotDoneAt(habitIndex, slotIndex) ? 1 : 0.94
    })
    .animation({ duration: 180, curve: Curve.EaseOut })
    .margin({ left: 6 })
    .onClick(() => {
      this.toggleSlot(habitIndex, habit, slotIndex);
    })
  }

  /** 新增 / 编辑习惯的卡片（同一套 UI，editorHabitId 为空即新增） */
  @Builder
  private buildEditorCard() {
    Column() {
      Row() {
        Text(this.editorHabitId === '' ? '添加习惯' : '编辑习惯')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
        Blank()
        Text('取消')
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .onClick(() => {
            this.closeEditor();
          })
      }
      .width('100%')

      TextInput({ placeholder: '比如：读书、喝水、早睡', text: this.draftName })
        .width('100%')
        .height(44)
        .fontSize(16)
        .maxLength(MAX_HABIT_NAME_LENGTH)
        .backgroundColor(Constants.COLOR_BACKGROUND)
        .margin({ top: 12 })
        .onChange((value: string) => {
          this.draftName = value;
        })

      Text('每天几次')
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 14 })

      Row() {
        ForEach(HABIT_TIMES_OPTIONS, (times: number) => {
          Text(`${times} 次`)
            .fontSize(14)
            .fontColor(this.draftTimes === times
              ? Constants.COLOR_ON_BRAND
              : Constants.COLOR_TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(36)
            .borderRadius(18)
            .backgroundColor(this.draftTimes === times
              ? Constants.COLOR_PRIMARY
              : Constants.COLOR_BACKGROUND)
            .margin({ left: 8 })
            .onClick(() => {
              this.setDraftTimes(times);
            })
        }, (times: number) => `times-${times}`)
      }
      .width('100%')
      .margin({ top: 8 })

      Text('每个时段的时间')
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 14 })

      ForEach(this.draftSlotIndexes(), (index: number) => {
        Row() {
          Text(`第 ${index + 1} 次`)
            .fontSize(15)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
          Blank()
          Text(this.draftSlotText(index))
            .fontSize(15)
            .fontColor(Constants.COLOR_PRIMARY)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(10)
            .backgroundColor(Constants.COLOR_BACKGROUND)
            .onClick(() => {
              this.pickSlotTime(index);
            })
        }
        .width('100%')
        .height(44)
      }, (index: number) => `slot-${index}`)

      Row() {
        Column() {
          Text('按时提醒')
            .fontSize(15)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
          Text('到点提醒你打卡（每天重复）')
            .fontSize(12)
            .fontColor(Constants.COLOR_TEXT_TERTIARY)
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.draftReminder })
          .onChange((isOn: boolean) => {
            this.draftReminder = isOn;
          })
      }
      .width('100%')
      .margin({ top: 12 })
      .alignItems(VerticalAlign.Center)

      Row() {
        Button('取消')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .backgroundColor(Constants.COLOR_BACKGROUND)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
          .onClick(() => {
            this.closeEditor();
          })
        Button(this.saving ? '保存中…' : '保存')
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .fontColor(Constants.COLOR_ON_BRAND)
          .margin({ left: 10 })
          .enabled(!this.saving)
          .onClick(() => {
            this.submitEditor();
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .margin({ top: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildAddCard() {
    Column() {
      Row() {
        Icon({ kind: IconKind.PLUS, iconSize: 24, color: Constants.COLOR_PRIMARY })
        Text('添加一个习惯')
          .fontSize(16)
          .fontColor(Constants.COLOR_PRIMARY)
          .margin({ left: 8 })
        Blank()
        Text(`还能加 ${this.slots()} 个`)
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
      }
      .width('100%')
      .height(48)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.openAdd();
      })
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .margin({ top: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildGuide() {
    Column() {
      Text('还没有习惯')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
      Text('给自己定几个每天想坚持的小事，\n每天点一下圆点就算打卡')
        .fontSize(15)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .margin({ top: 10 })
        .textAlign(TextAlign.Center)
      Text(`可以一天点多次（最多 ${MAX_HABIT_TIMES} 次），还能按时段提醒`)
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .margin({ top: 10 })
      Text('点习惯可以修改，长按可以删除')
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .margin({ top: 6 })
    }
    .width('100%')
    .padding({ top: 40, bottom: 40 })
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      Column() {
        this.buildHeader()
      }
      .width('100%')
      .linearGradient({
        angle: 135,
        colors: [[Constants.COLOR_HERO_START, 0.0], [Constants.COLOR_HERO_END, 1.0]]
      })

      Scroll() {
        Column() {
          if (!this.loaded) {
            Text('加载中…')
              .fontSize(15)
              .fontColor(Constants.COLOR_TEXT_TERTIARY)
              .margin({ top: 40 })
          } else {
            if (this.editorOpen) {
              this.buildEditorCard()
            }
            if (this.habits.length > 0) {
              this.buildTodayCard()
            }
            ForEach(this.habits, (habit: Habit, index: number) => {
              this.buildHabitRow(habit, index)
            }, (habit: Habit) => habit.id)
            if (!this.editorOpen) {
              this.buildAddCard()
            }
            if (this.habits.length === 0 && !this.editorOpen) {
              this.buildGuide()
            }
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 32 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Constants.COLOR_BACKGROUND)
  }
}
