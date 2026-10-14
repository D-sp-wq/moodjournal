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
  buildHabitDays,
  computeHabitProgress,
  groupChecksByHabit,
  normalizeHabitName,
  remainingHabitSlots
} from '../models/Habit';
import { RepositoryFactory } from '../services/data/RepositoryFactory';
import { Icon, IconKind } from '../components/Icons';

/**
 * 习惯打卡页：每天勾一下自己的习惯，看连续天数与近 30 天完成情况。
 *
 * 手机系统只有"运动健康"那种特定打卡，管不了读书、喝水、早睡这类自定义习惯，
 * 所以这一块是系统做不到的（应用商店审核指南 3.5 正好排除「系统自带的简易功能」）。
 * 全部本地存储，不联网、不需要任何权限。
 */
@Entry
@Component
struct HabitPage {
  @State private habits: Habit[] = [];
  @State private checks: HabitCheck[] = [];
  @State private loaded: boolean = false;
  @State private showAdd: boolean = false;
  @State private draft: string = '';
  @State private saving: boolean = false;
  // 下面几组按 habits 的下标对齐，在 load() 里一次性算好。
  // 之前是在每个习惯的每次渲染里现算（还要把全部打卡记录重新分组），非常浪费。
  @State private streaks: number[] = [];
  @State private rates: number[] = [];
  @State private doneFlags: boolean[] = [];
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
   * 一次性把每个习惯的连续天数 / 完成率 / 今日是否已打卡 / 30 天条带都算好。
   * 之前这三项是在每个习惯的每次渲染里现算的，而分组又会把全部打卡记录重新遍历一遍。
   */
  private recompute(): void {
    const today: string = this.today();
    const grouped: Map<string, string[]> = groupChecksByHabit(this.checks);
    const streaks: number[] = [];
    const rates: number[] = [];
    const doneFlags: boolean[] = [];
    const strips: HabitDay[][] = [];
    for (const habit of this.habits) {
      const list: string[] | undefined = grouped.get(habit.id);
      const own: string[] = list === undefined ? [] : list;
      const progress: HabitProgress = computeHabitProgress(habit.id, own, today, HABIT_WINDOW_DAYS);
      streaks.push(progress.streak);
      rates.push(progress.rate);
      doneFlags.push(progress.doneToday);
      strips.push(buildHabitDays(own, today, HABIT_WINDOW_DAYS));
    }
    this.streaks = streaks;
    this.rates = rates;
    this.doneFlags = doneFlags;
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

  private stripAt(index: number): HabitDay[] {
    return index < this.strips.length ? this.strips[index] : [];
  }

  /** 今天已完成几个 */
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

  /** 勾选 / 取消勾选（只针对今天） */
  private async toggleToday(habit: Habit, index: number): Promise<void> {
    const date: string = this.today();
    try {
      const repo = RepositoryFactory.getRepository();
      if (this.doneTodayAt(index)) {
        await repo.deleteHabitCheck(habit.id, date);
      } else {
        await repo.upsertHabitCheck({
          id: IdUtils.generate('check'),
          habitId: habit.id,
          date: date,
          createdAt: Date.now()
        });
      }
      await this.load();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '打卡失败，请重试', duration: 2000 });
    }
  }

  private async addHabit(): Promise<void> {
    const name: string = normalizeHabitName(this.draft);
    if (name === '') {
      this.getUIContext().getPromptAction().showToast({ message: '给这个习惯起个名字', duration: 2000 });
      return;
    }
    if (this.slots() <= 0) {
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
      await RepositoryFactory.getRepository().upsertHabit({
        id: IdUtils.generate('habit'),
        name: name,
        sortOrder: this.habits.length,
        createdAt: Date.now()
      });
      this.draft = '';
      this.showAdd = false;
      await this.load();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '添加失败，请重试', duration: 2000 });
    } finally {
      this.saving = false;
    }
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
      await this.load();
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

  /** 今天已完成几个 */
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
            ? `连续 ${this.streakAt(index)} 天 · 近 30 天 ${this.rateAt(index)}%`
            : `近 30 天 ${this.rateAt(index)}%`)
            .fontSize(14)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Stack() {
          if (this.doneTodayAt(index)) {
            Icon({ kind: IconKind.CHECK, iconSize: 24, color: Constants.COLOR_ON_BRAND, strokeW: 2.4 })
          }
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(this.doneTodayAt(index) ? Constants.COLOR_PRIMARY : Constants.COLOR_BACKGROUND)
        .border({
          width: this.doneTodayAt(index) ? 0 : 1,
          color: Constants.COLOR_DIVIDER
        })
        // 打卡时轻微放大，给一点即时反馈
        .scale({
          x: this.doneTodayAt(index) ? 1 : 0.94,
          y: this.doneTodayAt(index) ? 1 : 0.94
        })
        .animation({ duration: 180, curve: Curve.EaseOut })
        .onClick(() => {
          this.toggleToday(habit, index);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 近 30 天条带：一天一格
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
  private buildAddCard() {
    Column() {
      if (!this.showAdd) {
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
          this.showAdd = true;
        })
      } else {
        Row() {
          TextInput({ placeholder: '比如：读书、喝水、早睡', text: this.draft })
            .layoutWeight(1)
            .height(44)
            .fontSize(16)
            .maxLength(MAX_HABIT_NAME_LENGTH)
            .backgroundColor(Constants.COLOR_BACKGROUND)
            .onChange((value: string) => {
              this.draft = value;
            })
          Button('添加')
            .height(44)
            .fontSize(15)
            .backgroundColor(Constants.COLOR_PRIMARY)
            .fontColor(Constants.COLOR_ON_BRAND)
            .margin({ left: 10 })
            .enabled(!this.saving)
            .onClick(() => {
              this.addHabit();
            })
        }
        .width('100%')

        Text(`最多 ${MAX_HABITS} 个，最多 ${MAX_HABIT_NAME_LENGTH} 个字`)
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 8 })
      }
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
      Text('长按某个习惯可以删除')
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .margin({ top: 10 })
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
            if (this.habits.length > 0) {
              this.buildTodayCard()
            }
            ForEach(this.habits, (habit: Habit, index: number) => {
              this.buildHabitRow(habit, index)
            }, (habit: Habit) => habit.id)
            this.buildAddCard()
            if (this.habits.length === 0) {
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
