import { Constants } from '../common/constants/Constants';
import { DateCalcUtils } from '../common/utils/DateCalcUtils';
import { moodColorsByLabel } from '../models/DailyLog';
import { RangeReport, ReportDay, ReportMood } from '../models/Report';
import { StatsService } from '../services/StatsService';
import { Icon, IconKind } from '../components/Icons';

const WEEK_DAYS: number = 7;
const MONTH_DAYS: number = 30;

const EMPTY_REPORT: RangeReport = {
  from: '',
  to: '',
  days: WEEK_DAYS,
  recordedDays: 0,
  entries: 0,
  chars: 0,
  avgChars: 0,
  moods: [],
  topMood: '',
  busiestDate: '',
  daysDelta: 0,
  summary: ''
};

/**
 * 周报 / 月度回顾页。
 *
 * 这是应用「创意」最集中的一页：把零散的每日记录自动汇成一段可读的回顾，
 * 并与上一个同样长的周期对比——系统备忘录和系统日历都做不到这件事。
 * 全部本地计算，不联网、不需要任何权限。
 */
@Entry
@Component
struct ReviewPage {
  @State private report: RangeReport = EMPTY_REPORT;
  @State private days: ReportDay[] = [];
  @State private span: number = WEEK_DAYS;
  @State private loaded: boolean = false;
  // 提前算好，避免每次渲染都 slice 出一个新数组
  @State private topMoods: ReportMood[] = [];
  @State private moodTotal: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      this.report = await StatsService.loadReport(this.span);
      this.days = await StatsService.loadReportDays(this.span);
    } catch (err) {
      this.report = EMPTY_REPORT;
      this.days = [];
    } finally {
      this.topMoods = this.report.moods.slice(0, 4);
      this.moodTotal = this.report.entries;
      this.loaded = true;
    }
  }

  private switchSpan(span: number): void {
    if (this.span === span) {
      return;
    }
    this.span = span;
    this.loaded = false;
    this.load();
  }

  private spanLabel(): string {
    return this.span === WEEK_DAYS ? '本周回顾' : '近 30 天回顾';
  }

  private rangeLabel(): string {
    if (this.report.from === '') {
      return '';
    }
    return `${DateCalcUtils.toChineseDate(this.report.from)} — ${DateCalcUtils.toChineseDate(this.report.to)}`;
  }

  private deltaLabel(): string {
    const delta: number = this.report.daysDelta;
    if (delta > 0) {
      return `比上一个同样长的周期多记了 ${delta} 天`;
    }
    if (delta < 0) {
      return `比上一个同样长的周期少记了 ${-delta} 天`;
    }
    return '与上一个同样长的周期持平';
  }

  @Builder
  private buildHeader() {
    Stack() {
      Text(this.spanLabel())
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
  private buildSpanTabs() {
    Row() {
      Text('本周')
        .fontSize(15)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .padding({ top: 8, bottom: 8 })
        .borderRadius(10)
        .backgroundColor(this.span === WEEK_DAYS ? Constants.COLOR_PRIMARY : Constants.COLOR_TRANSPARENT)
        .fontColor(this.span === WEEK_DAYS ? Constants.COLOR_ON_BRAND : Constants.COLOR_TEXT_SECONDARY)
        .onClick(() => {
          this.switchSpan(WEEK_DAYS);
        })
      Text('近 30 天')
        .fontSize(15)
        .textAlign(TextAlign.Center)
        .layoutWeight(1)
        .padding({ top: 8, bottom: 8 })
        .borderRadius(10)
        .margin({ left: 8 })
        .backgroundColor(this.span === MONTH_DAYS ? Constants.COLOR_PRIMARY : Constants.COLOR_TRANSPARENT)
        .fontColor(this.span === MONTH_DAYS ? Constants.COLOR_ON_BRAND : Constants.COLOR_TEXT_SECONDARY)
        .onClick(() => {
          this.switchSpan(MONTH_DAYS);
        })
    }
    .width('100%')
    .padding(4)
    .borderRadius(12)
    .backgroundColor(Constants.COLOR_CARD)
  }

  /** 自动生成的一句话总结 */
  @Builder
  private buildSummaryCard() {
    Column() {
      Row() {
        Icon({ kind: IconKind.NOTE, iconSize: 24, color: Constants.COLOR_PRIMARY })
        Text('自动生成的总结')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
          .margin({ left: 8 })
        Blank()
      }
      .width('100%')

      Text(this.report.summary)
        .fontSize(16)
        .lineHeight(28)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%')
        .margin({ top: 12 })

      Text(this.deltaLabel())
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 10 })

      Text(this.rangeLabel())
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 6 })
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .margin({ top: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 一天一格的心情条带 */
  @Builder
  private buildDayStrip() {
    Column() {
      Row() {
        Text('每天的心情')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
        Blank()
        Text(`${this.report.recordedDays} / ${this.report.days} 天`)
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
      }
      .width('100%')

      Row() {
        ForEach(this.days, (day: ReportDay) => {
          Column()
            .layoutWeight(1)
            .height(40)
            .borderRadius(6)
            .backgroundColor(day.mood === '' ? Constants.COLOR_TRACK : moodColorsByLabel(day.mood)[0])
            .margin({ right: 3 })
        }, (day: ReportDay) => day.date)
      }
      .width('100%')
      .margin({ top: 12 })
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
  private buildNumbers() {
    Column() {
      Row() {
        this.buildCell(`${this.report.entries}`, '记录篇数')
        this.buildCell(`${this.report.chars}`, '总字数')
        this.buildCell(`${this.report.avgChars}`, '平均每篇字数')
      }
      .width('100%')

      Text(this.report.busiestDate === ''
        ? '还没有记录'
        : `写得最多的一天：${this.report.busiestDate}`)
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 16 })
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
  private buildCell(value: string, label: string) {
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
  private buildMoods() {
    Column() {
      Text('这段时间的心情')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%')

      if (this.report.moods.length === 0) {
        Text('还没有记录，写下今天的第一篇吧')
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 12 })
      } else {
        ForEach(this.topMoods, (item: ReportMood) => {
          Column() {
            Row() {
              Row()
                .width(12)
                .height(12)
                .borderRadius(6)
                .backgroundColor(moodColorsByLabel(item.label)[0])
              Text(item.label)
                .fontSize(15)
                .fontColor(Constants.COLOR_TEXT_PRIMARY)
                .margin({ left: 8 })
              Blank()
              Text(`${item.count} 次`)
                .fontSize(14)
                .fontColor(Constants.COLOR_TEXT_SECONDARY)
            }
            .width('100%')

            Row() {
              Row()
                .width(`${this.moodTotal > 0 ? item.count * 100 / this.moodTotal : 0}%`)
                .height(8)
                .borderRadius(4)
                .backgroundColor(Constants.COLOR_PRIMARY)
            }
            .width('100%')
            .height(8)
            .borderRadius(4)
            .backgroundColor(Constants.COLOR_TRACK)
            .margin({ top: 6 })
          }
          .width('100%')
          .margin({ top: 14 })
        }, (item: ReportMood) => item.label)
      }
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
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
          if (!this.loaded) {
            Text('正在整理…')
              .fontSize(15)
              .fontColor(Constants.COLOR_TEXT_TERTIARY)
              .margin({ top: 40 })
          } else {
            this.buildSpanTabs()
            this.buildSummaryCard()
            if (this.days.length > 0) {
              this.buildDayStrip()
            }
            this.buildNumbers()
            this.buildMoods()
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
