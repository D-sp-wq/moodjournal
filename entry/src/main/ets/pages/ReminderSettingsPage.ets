import { Constants } from '../common/constants/Constants';
import { formatTime } from '../models/PlanReminder';
import { SessionManager } from '../services/storage/SessionManager';
import { PlanReminderService } from '../services/PlanReminderService';
import { Icon, IconKind } from '../components/Icons';

/**
 * 「今日提醒」设置页：一个开关 + 一个提醒时间。
 *
 * 文案要说清楚它到底推什么：**内容是您给今天安排的事**，没安排的日子不推。
 * 关闭时会立刻取消已经排好的提醒（否则用户关了还在收通知）。
 *
 * 计划本身不在这里编辑 —— 它来自「那天要做的事」（DayPlanPage），
 * 存的是前一天那条记录的 plan 字段，这里只负责"什么时候提醒"。
 */
@Entry
@Component
struct ReminderSettingsPage {
  @State private reminderOn: boolean = false;
  @State private hour: number = Constants.PLAN_REMINDER_HOUR;
  @State private minute: number = Constants.PLAN_REMINDER_MINUTE;
  @State private loaded: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  /** 从别的页面返回时重新读一次，保证显示的是落盘的设置 */
  onPageShow(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      const session = SessionManager.getInstance();
      const enabled: boolean = await session.isPlanReminderEnabled();
      const hour: number = await session.getPlanReminderHour();
      const minute: number = await session.getPlanReminderMinute();
      this.reminderOn = enabled;
      this.hour = hour;
      this.minute = minute;
    } catch (err) {
      // 读不到就保持默认值（关闭 / 09:00），页面照常可用
    } finally {
      this.loaded = true;
    }
  }

  /**
   * 切换开关。
   * 关闭：等取消真的做完再提示（"已取消"要说得准）；开启：先把开关存下来，
   * 排期放后台做，不卡住页面。
   */
  private async toggle(next: boolean): Promise<void> {
    if (next === this.reminderOn) {
      return;
    }
    this.reminderOn = next;
    try {
      await SessionManager.getInstance().setPlanReminderEnabled(next);
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '设置失败，请重试', duration: 2000 });
      await this.load();
      return;
    }
    if (next) {
      // 开启：开关已经存好了，排期放后台做（不 await，不卡住页面）
      PlanReminderService.sync();
      this.getUIContext().getPromptAction().showToast({
        message: `已开启：每天 ${formatTime(this.hour, this.minute)} 提醒您今天要做的事`,
        duration: 2000
      });
    } else {
      // 关掉就必须把已排期的提醒都取消：sync 在关闭时只做取消、不排新的
      await PlanReminderService.sync();
      this.getUIContext().getPromptAction().showToast({
        message: '已关闭今日提醒，已排期的提醒已取消',
        duration: 2000
      });
    }
  }

  /** 选时:分（24 小时制，避免午夜/中午的歧义） */
  private pickTime(): void {
    const selected: Date = new Date();
    selected.setHours(this.hour, this.minute, 0, 0);
    TimePickerDialog.show({
      selected: selected,
      format: TimePickerFormat.HOUR_MINUTE,
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        this.applyTime(value.hour, value.minute);
      }
    });
  }

  private async applyTime(hour: number, minute: number): Promise<void> {
    if (hour === this.hour && minute === this.minute) {
      return;
    }
    this.hour = hour;
    this.minute = minute;
    try {
      const session = SessionManager.getInstance();
      await session.setPlanReminderHour(hour);
      await session.setPlanReminderMinute(minute);
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '设置失败，请重试', duration: 2000 });
      await this.load();
      return;
    }
    // 开着才需要重排；关着就等用户打开开关时再排
    if (this.reminderOn) {
      PlanReminderService.sync();
    }
    this.getUIContext().getPromptAction().showToast({
      message: `已改为每天 ${formatTime(hour, minute)}`,
      duration: 1800
    });
  }

  private statusLabel(): string {
    return this.reminderOn ? '已开启' : '已关闭';
  }

  @Builder
  private buildHeader() {
    Stack() {
      Text('今日提醒')
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

  @Builder
  private buildSwitchCard() {
    Column() {
      Row() {
        Icon({ kind: IconKind.NOTE, iconSize: 24, color: Constants.COLOR_PRIMARY })
        Column() {
          Text('今日提醒')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
          Text(this.reminderOn ? `每天 ${formatTime(this.hour, this.minute)} 推送` : '当前已关闭，不会推送')
            .fontSize(14)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 10 })

        Toggle({ type: ToggleType.Switch, isOn: this.reminderOn })
          .selectedColor(Constants.COLOR_PRIMARY)
          .onChange((isOn: boolean) => {
            this.toggle(isOn);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('到点会推送一条通知，内容是您给今天安排的事。没有安排的日子不会打扰您。')
        .fontSize(14)
        .lineHeight(22)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 14 })
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .margin({ top: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildTimeCard() {
    Column() {
      Row() {
        Icon({ kind: IconKind.CALENDAR, iconSize: 24, color: Constants.COLOR_PRIMARY })
        Column() {
          Text('提醒时间')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
          Text(this.reminderOn ? '每天在这个时间提醒' : '开启后按这个时间提醒')
            .fontSize(14)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 10 })

        Text(formatTime(this.hour, this.minute))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_PRIMARY)
        Icon({ kind: IconKind.CHEVRON, iconSize: 18, color: Constants.COLOR_TEXT_TERTIARY })
          .margin({ left: 4 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.pickTime();
      })

      Divider()
        .color(Constants.COLOR_DIVIDER)
        .margin({ top: 14, bottom: 12 })

      Text('只排今天起 7 天内有安排的日子；如果今天的时间已经过了，今天就不再补发。')
        .fontSize(13)
        .lineHeight(21)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .width('100%')
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .margin({ top: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildNotice() {
    Column() {
      Row() {
        Text('当前状态')
          .fontSize(15)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
        Blank()
        Text(this.statusLabel())
          .fontSize(15)
          .fontColor(this.reminderOn ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_TERTIARY)
      }
      .width('100%')

      Text('内容取自「那天要做的事」——昨天给今天安排的计划。改完计划会自动重排，不需要手动刷新。'
        + '提醒由系统「提醒」服务在本机定时触发，不联网、不上传任何数据。')
        .fontSize(13)
        .lineHeight(22)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 12 })
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
    .margin({ top: 14 })
    .alignItems(HorizontalAlign.Start)
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
          if (this.loaded) {
            this.buildSwitchCard()
            this.buildTimeCard()
            this.buildNotice()
          } else {
            Text('加载中…')
              .fontSize(15)
              .fontColor(Constants.COLOR_TEXT_TERTIARY)
              .margin({ top: 40 })
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
