import { Constants } from '../common/constants/Constants';
import { DateCalcUtils } from '../common/utils/DateCalcUtils';
import { AnnualMonth, AnnualReport } from '../models/AnnualReport';
import { moodColorsByLabel } from '../models/DailyLog';
import { ReportMood } from '../models/Report';
import { StatsService } from '../services/StatsService';
import { Icon, IconKind } from '../components/Icons';

/** 柱子分几档：和账本「每日支出条」同一套分档思路，0 档单独表示"这天没有记录" */
const BAR_LEVELS: number = 4;
/** 柱子区总高，最高档的柱子留 12 的顶空 */
const BAR_BOX_HEIGHT: number = 64;
/** 心情分布最多展示几行 */
const TOP_MOOD_ROWS: number = 4;

const EMPTY_REPORT: AnnualReport = {
  year: 0,
  recordedDays: 0,
  entries: 0,
  chars: 0,
  avgChars: 0,
  topMood: '',
  moodCounts: [],
  busiestMonth: 0,
  months: [],
  longestStreak: 0,
  firstDate: '',
  lastDate: '',
  summary: ''
};

/**
 * 年度报告页。
 *
 * 与周报 / 月度回顾（ReviewPage）共用一套视觉规范，但口径不同：
 * 这一页按**自然年**（1/1–12/31）分桶，因为"今年比去年多写了多少"只有在
 * 自然年上对齐才有意义；滚动 365 天窗口会把两年切碎，也给不出 12 个自然月的分布。
 *
 * 页面里不写任何统计逻辑，只消费 models/AnnualReport.ets 的 buildAnnualReport 结果，
 * 全部本地计算，不联网、不新增任何权限。
 */
@Entry
@Component
struct AnnualReportPage {
  @State private report: AnnualReport = EMPTY_REPORT;
  @State private years: number[] = [];
  @State private year: number = 0;
  @State private moods: ReportMood[] = [];
  @State private maxMonthDays: number = 0;
  @State private loaded: boolean = false;

  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.loaded = false;
    try {
      this.years = await StatsService.loadAvailableYears();
      const current: number = this.years.length > 0
        ? this.years[0]
        : new Date().getFullYear();
      this.year = current;
      await this.loadYear(current);
    } catch (err) {
      this.report = EMPTY_REPORT;
      this.moods = [];
      this.maxMonthDays = 0;
    } finally {
      this.loaded = true;
    }
  }

  private async loadYear(year: number): Promise<void> {
    const report: AnnualReport = await StatsService.loadAnnualReport(year);
    this.report = report;
    // 提前算好，避免每次渲染都 slice 出一个新数组 / 扫一遍月份；
    // 这里用显式循环而不是 Array.slice(0, N)（见 models/AnnualReport.ets 里关于 slice 的说明）
    const top: ReportMood[] = [];
    for (const item of report.moodCounts) {
      if (top.length >= TOP_MOOD_ROWS) {
        break;
      }
      top.push(item);
    }
    this.moods = top;
    let max: number = 0;
    for (const item of report.months) {
      if (item.recordedDays > max) {
        max = item.recordedDays;
      }
    }
    this.maxMonthDays = max;
  }

  /** 同页内切年：重新算一份报告，不跳页 */
  private switchYear(year: number): void {
    if (this.year === year) {
      return;
    }
    this.year = year;
    this.loaded = false;
    this.loadYear(year).then(() => {
      this.loaded = true;
      this.scroller.scrollEdge(Edge.Top);
    }).catch(() => {
      this.report = EMPTY_REPORT;
      this.moods = [];
      this.maxMonthDays = 0;
      this.loaded = true;
    });
  }

  /** 当月记录天数占总量的比例，0-1 */
  private barRatio(days: number): number {
    if (days <= 0 || this.maxMonthDays <= 0) {
      return 0;
    }
    return days / this.maxMonthDays;
  }

  /** 相对最大值分档，0 档表示这个月没有记录 */
  private barLevel(days: number): number {
    if (days <= 0) {
      return 0;
    }
    return Math.max(1, Math.ceil(this.barRatio(days) * BAR_LEVELS));
  }

  private rangeLabel(): string {
    if (this.report.firstDate === '') {
      return '';
    }
    return `${DateCalcUtils.toChineseDate(this.report.firstDate)} — ${DateCalcUtils.toChineseDate(this.report.lastDate)}`;
  }

  @Builder
  private buildHeader() {
    Stack() {
      Text('年度报告')
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

  /** 年份胶囊：点一下切年，同页内状态切换 */
  @Builder
  private buildYearPills() {
    Scroll() {
      Row() {
        ForEach(this.years, (year: number) => {
          Text(`${year}年`)
            .fontSize(15)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .borderRadius(18)
            .backgroundColor(this.year === year ? Constants.COLOR_PRIMARY : Constants.COLOR_CARD)
            .fontColor(this.year === year ? Constants.COLOR_ON_BRAND : Constants.COLOR_TEXT_SECONDARY)
            .margin({ right: 8 })
            .onClick(() => {
              this.switchYear(year);
            })
        }, (year: number) => `${year}`)
      }
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .align(Alignment.Start)
  }

  /** 大字概览：这一年记了 N 天 / N 篇 / N 字 */
  @Builder
  private buildOverview() {
    Column() {
      Row() {
        this.buildCell(`${this.report.recordedDays}`, '记录天数')
        this.buildCell(`${this.report.entries}`, '记录篇数')
        this.buildCell(`${this.report.chars}`, '总字数')
      }
      .width('100%')

      Text(this.rangeLabel())
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
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

  /** 自动生成的一句话总结 */
  @Builder
  private buildSummaryCard() {
    Column() {
      Row() {
        Icon({ kind: IconKind.NOTE, iconSize: 24, color: Constants.COLOR_PRIMARY })
        Text('这一年的总结')
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
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .margin({ top: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 12 个月柱状图：Column 手绘，高度按当月记录天数相对最大值分档 */
  @Builder
  private buildMonthBars() {
    Column() {
      Row() {
        Text('每个月的记录')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
        Blank()
        Text(`最多 ${this.maxMonthDays} 天`)
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
      }
      .width('100%')

      Row() {
        ForEach(this.report.months, (item: AnnualMonth) => {
          Column() {
            Column() {
              Column()
                .width('100%')
                .height(this.barLevel(item.recordedDays) === 0
                  ? 4
                  : 12 + this.barLevel(item.recordedDays) * 11)
                .borderRadius(4)
                .backgroundColor(this.barLevel(item.recordedDays) === 0
                  ? Constants.COLOR_TRACK
                  : Constants.COLOR_PRIMARY)
            }
            .width('100%')
            .height(BAR_BOX_HEIGHT)
            .justifyContent(FlexAlign.End)

            Text(`${item.month}`)
              .fontSize(11)
              .fontColor(Constants.COLOR_TEXT_TERTIARY)
              .margin({ top: 6 })
          }
          .layoutWeight(1)
        }, (item: AnnualMonth) => `${item.month}`)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
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

  /** 心情分布：色点 + 心情名 + 次数 + 占比条 */
  @Builder
  private buildMoods() {
    Column() {
      Text('这一年的心情')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%')

      ForEach(this.moods, (item: ReportMood) => {
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
            Text(`${item.count} 次 · ${this.moodPercent(item)}%`)
              .fontSize(14)
              .fontColor(Constants.COLOR_TEXT_SECONDARY)
          }
          .width('100%')

          Row() {
            Row()
              .width(`${this.moodPercent(item)}%`)
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
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .margin({ top: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 该心情占全年记录篇数的百分比，0-100 */
  private moodPercent(item: ReportMood): number {
    const total: number = this.report.entries;
    return total > 0 ? Math.round(item.count * 100 / total) : 0;
  }

  /** 数字卡：最长连续 / 记录最多的月份 / 平均每篇字数 */
  @Builder
  private buildNumbers() {
    Column() {
      Row() {
        this.buildCell(`${this.report.longestStreak}`, '最长连续天数')
        this.buildCell(this.report.busiestMonth > 0 ? `${this.report.busiestMonth} 月` : '—', '记录最多的月份')
        this.buildCell(`${this.report.avgChars}`, '平均每篇字数')
      }
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

  /** 空态：这一年没有记录时只给一句引导，不铺一堆 0 */
  @Builder
  private buildEmpty() {
    Column() {
      Text('这一年还没有记录')
        .fontSize(16)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
      Text('回到首页写下今天的心情，明年就有年度报告了')
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .margin({ top: 8 })
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

      Scroll(this.scroller) {
        Column() {
          if (!this.loaded) {
            Text('正在整理…')
              .fontSize(15)
              .fontColor(Constants.COLOR_TEXT_TERTIARY)
              .margin({ top: 40 })
          } else {
            this.buildYearPills()
            if (this.report.recordedDays === 0) {
              this.buildEmpty()
            } else {
              this.buildOverview()
              this.buildSummaryCard()
              this.buildMonthBars()
              if (this.moods.length > 0) {
                this.buildMoods()
              }
              this.buildNumbers()
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
