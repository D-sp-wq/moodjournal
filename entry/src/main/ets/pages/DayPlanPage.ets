import { Constants } from '../common/constants/Constants';
import { DateCalcUtils } from '../common/utils/DateCalcUtils';
import { DateUtils } from '../common/utils/DateUtils';
import { IdUtils } from '../common/utils/IdUtils';
import { readDateParam } from '../common/utils/RouteUtils';
import { DailyLog, Mood } from '../models/DailyLog';
import { RepositoryFactory } from '../services/data/RepositoryFactory';
import { Icon, IconKind } from '../components/Icons';

/**
 * 「X月X日 要做的事」编辑页。
 *
 * 为什么有这个页：还没到的日子不该出现「今天的心情 / 今天发生了什么」——
 * 给未来的日子写"今天"是自相矛盾的。点日历上的未来日期，来这里安排那天要做什么。
 *
 * 存储上复用 DailyLog.plan：它的既有语义是"次日要做的事"（写在日期 D 的记录里表示 D+1 的任务），
 * 所以"日期 D 那天要做什么"落在 **D-1** 的 plan 上。
 * 这样全应用只有一个字段在表达"某天要做什么"，不需要新表、不需要新概念。
 *
 * 只写计划的记录会被标记 hasEntry = false（计划存根），不算一条真正的记录：
 * 不会进入连续天数、累计篇数、日历心情色、统计与时间轴。
 */
@Entry
@Component
struct DayPlanPage {
  /** 用户点的那一天 */
  @State private date: string = '';
  /** 实际写入的日期，= date - 1 天 */
  @State private targetDate: string = '';
  @State private plan: string = '';
  @State private loaded: boolean = false;
  @State private saving: boolean = false;

  aboutToAppear(): void {
    this.date = readDateParam(this.getUIContext().getRouter().getParams());
    this.targetDate = DateUtils.addDays(this.date, -1);
    this.load();
  }

  private async load(): Promise<void> {
    try {
      const existing: DailyLog | null = await RepositoryFactory.getRepository().getDailyLog(this.targetDate);
      this.plan = existing === null ? '' : existing.plan;
    } catch (err) {
      this.plan = '';
    } finally {
      this.loaded = true;
    }
  }

  private dateLabel(): string {
    const month: number = Number(this.date.slice(5, 7));
    const day: number = Number(this.date.slice(8, 10));
    return `${month}月${day}日`;
  }

  private async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    // 正常路径不会触发：D 是未来 ⇒ D-1 ≥ 今天，永远不封存。这里只做兜底。
    if (DateUtils.isSealed(this.targetDate, DateUtils.today())) {
      this.getUIContext().getPromptAction().showToast({
        message: '这一天已经过去了，不能再改安排',
        duration: 2000
      });
      return;
    }
    this.saving = true;
    const text: string = this.plan.trim().slice(0, Constants.MAX_PLAN_LENGTH);
    try {
      const repo = RepositoryFactory.getRepository();
      const existing: DailyLog | null = await repo.getDailyLog(this.targetDate);
      if (text === '') {
        // 清空安排：本来就只是个计划存根的话，直接删掉，别留空壳数据
        if (existing !== null && !existing.hasEntry) {
          await repo.deleteDailyLog(existing.id);
        } else if (existing !== null) {
          existing.plan = '';
          existing.updatedAt = Date.now();
          await repo.upsertDailyLog(existing);
        }
      } else if (existing !== null) {
        // 已有记录（可能是正常记录）：只改 plan，绝不动别人的心情/正文/照片
        existing.plan = text;
        existing.updatedAt = Date.now();
        await repo.upsertDailyLog(existing);
      } else {
        await repo.upsertDailyLog({
          id: IdUtils.generate('log'),
          date: this.targetDate,
          mood: Mood.HAPPY,
          customMood: '',
          journal: '',
          plan: text,
          photoUris: [],
          tags: [],
          hasEntry: false,
          createdAt: Date.now(),
          updatedAt: Date.now()
        });
      }
      this.getUIContext().getPromptAction().showToast({ message: '已记下那天要做的事', duration: 1500 });
      this.getUIContext().getRouter().back();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试', duration: 2000 });
    } finally {
      this.saving = false;
    }
  }

  @Builder
  private buildHeader() {
    Stack() {
      Text('那天要做的事')
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
            // 日期胶囊
            Row() {
              Icon({ kind: IconKind.CALENDAR, iconSize: 24, color: Constants.COLOR_PRIMARY })
              Text(`${this.dateLabel()} ${DateCalcUtils.weekdayLabel(this.date)}`)
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor(Constants.COLOR_TEXT_PRIMARY)
                .margin({ left: 8 })
              Blank()
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .borderRadius(14)
            .backgroundColor(Constants.COLOR_CARD)
            .alignItems(VerticalAlign.Center)

            Text('给那天安排几件事，到那天打开应用就会看到')
              .fontSize(14)
              .fontColor(Constants.COLOR_TEXT_SECONDARY)
              .width('100%')
              .margin({ top: 14 })

            Column() {
              TextArea({ placeholder: '那天要做什么…', text: this.plan })
                .width('100%')
                .height(160)
                .fontSize(16)
                .backgroundColor(Constants.COLOR_TRANSPARENT)
                .maxLength(Constants.MAX_PLAN_LENGTH)
                .onChange((value: string) => {
                  this.plan = value;
                })
              Text(`${this.plan.length}/${Constants.MAX_PLAN_LENGTH}`)
                .fontSize(13)
                .fontColor(Constants.COLOR_TEXT_TERTIARY)
                .width('100%')
                .textAlign(TextAlign.End)
            }
            .width('100%')
            .padding(16)
            .borderRadius(16)
            .backgroundColor(Constants.COLOR_CARD)
            .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
            .margin({ top: 12 })
            .alignItems(HorizontalAlign.Start)

            Row() {
              Icon({ kind: IconKind.NOTE, iconSize: 20, color: Constants.COLOR_ON_BRAND })
              Text('保存这天要做的事')
                .fontSize(17)
                .fontColor(Constants.COLOR_ON_BRAND)
                .margin({ left: 8 })
            }
            .width('100%')
            .height(52)
            .borderRadius(16)
            .backgroundColor(Constants.COLOR_PRIMARY)
            .justifyContent(FlexAlign.Center)
            .margin({ top: 20 })
            .opacity(this.saving ? 0.6 : 1)
            .onClick(() => {
              this.save();
            })

            Text('这一天只记录"要做的事"，不会要求你写今天的心情——\n那天到了再记录当天的心情和经历。')
              .fontSize(13)
              .lineHeight(22)
              .fontColor(Constants.COLOR_TEXT_TERTIARY)
              .width('100%')
              .margin({ top: 14 })
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
