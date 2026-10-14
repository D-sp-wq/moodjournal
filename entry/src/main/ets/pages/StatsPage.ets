import { Constants } from '../common/constants/Constants';
import { MoodCount, MoodTrend, MonthCount, StatsResult, TrendPoint } from '../models/Stats';
import { moodColorsByLabel } from '../models/DailyLog';
import { StatsService } from '../services/StatsService';
import { Icon, IconKind } from '../components/Icons';

const EMPTY_STATS: StatsResult = {
  total: 0,
  activeDays: 0,
  recordDays: 0,
  ratePercent: 0,
  currentStreak: 0,
  bestStreak: 0,
  loggedToday: false,
  totalChars: 0,
  moods: [],
  months: [],
  importantCount: 0,
  photoCount: 0
};

const EMPTY_TREND: MoodTrend = {
  points: [],
  recordedDays: 0,
  topMood: '',
  avgChars: 0
};

@Entry
@Component
struct StatsPage {
  @State private stats: StatsResult = EMPTY_STATS;
  @State private trend: MoodTrend = EMPTY_TREND;
  @State private loaded: boolean = false;
  @State private failed: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      this.stats = await StatsService.load();
      this.trend = await StatsService.loadTrend();
      this.failed = false;
    } catch (err) {
      this.failed = true;
    } finally {
      this.loaded = true;
    }
  }

  @Builder
  private buildHeader() {
    Column() {
      Stack() {
        Text('数据统计')
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

      Row() {
        Text(`${this.stats.activeDays}`)
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_ON_BRAND)
        Text(' 天有记录')
          .fontSize(16)
          .fontColor(Constants.COLOR_ON_BRAND)
          .margin({ bottom: 6 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: 14 })

      Text(`已使用 ${this.stats.recordDays} 天 · 记录覆盖率 ${this.stats.ratePercent}%`)
        .fontSize(14)
        .fontColor(Constants.COLOR_ON_BRAND)
        .opacity(0.9)
        .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 14, bottom: 20 })
    .linearGradient({
      angle: 135,
      colors: [[Constants.COLOR_HERO_START, 0.0], [Constants.COLOR_HERO_END, 1.0]]
    })
  }

  @Builder
  private buildOverview() {
    Column() {
      Text('记录概览')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%')

      Row() {
        this.buildMetric(`${this.stats.total}`, '记录总篇数')
        this.buildMetric(`${this.stats.recordDays}`, '记录天数')
        this.buildMetric(`${this.stats.ratePercent}%`, '记录覆盖率')
      }
      .width('100%')
      .margin({ top: 14 })

      Row() {
        this.buildMetric(`${this.stats.currentStreak}`, '当前连续(天)')
        this.buildMetric(`${this.stats.bestStreak}`, '最长连续(天)')
        this.buildMetric(`${this.stats.loggedToday ? '是' : '否'}`, '今日已记录')
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
  }

  @Builder
  private buildMetric(value: string, label: string) {
    Column() {
      Text(value)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_PRIMARY)
      Text(label)
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
  }

  @Builder
  private buildMoods() {
    Column() {
      Text('心情分布')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%')

      if (this.stats.moods.length === 0) {
        Text('还没有记录，回到首页记下今天吧')
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .margin({ top: 12 })
      } else {
        ForEach(this.stats.moods, (item: MoodCount) => {
          Column() {
            Row() {
              Row()
                .width(10)
                .height(10)
                .borderRadius(5)
                .linearGradient({
                  angle: 135,
                  colors: [
                    [moodColorsByLabel(item.mood)[0], 0.0],
                    [moodColorsByLabel(item.mood)[1], 1.0]
                  ]
                })
              Text(item.mood)
                .fontSize(15)
                .fontColor(Constants.COLOR_TEXT_PRIMARY)
                .margin({ left: 8 })
              Blank()
              Text(`${item.count} 次 · ${item.percent}%`)
                .fontSize(13)
                .fontColor(Constants.COLOR_TEXT_SECONDARY)
            }
            .width('100%')

            Row() {
              Row()
                .width(`${item.percent}%`)
                .height(8)
                .borderRadius(4)
                .linearGradient({
                  angle: 135,
                  colors: [
                    [moodColorsByLabel(item.mood)[0], 0.0],
                    [moodColorsByLabel(item.mood)[1], 1.0]
                  ]
                })
            }
            .width('100%')
            .height(8)
            .borderRadius(4)
            .backgroundColor(Constants.COLOR_TRACK)
            .margin({ top: 6 })
          }
          .width('100%')
          .margin({ top: 14 })
        }, (item: MoodCount) => item.mood)
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
  private buildMonths() {
    Column() {
      Text('近 6 个月记录')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%')

      Row() {
        ForEach(this.stats.months, (item: MonthCount) => {
          Column() {
            Text(`${item.count}`)
              .fontSize(13)
              .fontColor(Constants.COLOR_TEXT_SECONDARY)
            Column()
              .width(18)
              .height(6 + item.count * 6)
              .borderRadius(6)
              .backgroundColor(item.count > 0 ? Constants.COLOR_PRIMARY : Constants.COLOR_TRACK)
              .margin({ top: 6 })
            Text(item.label)
              .fontSize(13)
              .fontColor(Constants.COLOR_TEXT_SECONDARY)
              .margin({ top: 6 })
          }
          .layoutWeight(1)
        }, (item: MonthCount) => item.label)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: 14 })
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
  private buildContent() {
    Column() {
      Text('内容积累')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%')
      Row() {
        this.buildMetric(`${this.stats.totalChars}`, '日记总字数')
        this.buildMetric(`${this.stats.importantCount}`, '重要日子(个)')
      }
      .width('100%')
      .margin({ top: 14 })
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .margin({ top: 12 })
  }

  /** 折线坐标：x 按天数均分（固定 300 宽），y 由情绪值 1~5 映射；没有记录的日期不留点 */
  private trendLines(): number[][] {
    const pts: number[][] = [];
    const total: number = this.trend.points.length;
    if (total < 2) {
      return pts;
    }
    const step: number = 300 / (total - 1);
    for (let i: number = 0; i < total; i++) {
      const point: TrendPoint = this.trend.points[i];
      if (point.score <= 0) {
        continue;
      }
      const pair: number[] = [i * step, 82 - (point.score - 1) * 18];
      pts.push(pair);
    }
    return pts;
  }

  @Builder
  private buildTrend() {
    Column() {
      Row() {
        Text('心情趋势')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
        Blank()
        Text(`近 ${this.trend.points.length} 天`)
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
      }
      .width('100%')

      // 一天一格，颜色就是当天的心情；没记录的显示为浅色
      Row() {
        ForEach(this.trend.points, (point: TrendPoint) => {
          Column()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(point.score > 0
              ? moodColorsByLabel(point.label)[0]
              : Constants.COLOR_TRACK)
            .margin({ right: 3 })
        }, (point: TrendPoint) => point.date)
      }
      .width('100%')
      .margin({ top: 14 })

      if (this.trendLines().length >= 2) {
        Polyline({ width: 300, height: 90 })
          .points(this.trendLines())
          .stroke(Constants.COLOR_PRIMARY)
          .strokeWidth(2)
          .fill(Color.Transparent)
          .margin({ top: 14 })
      } else if (this.trend.recordedDays === 0) {
        // 完全没有记录时给一句提示，否则只有一排灰点，看着像坏了
        Text('近 30 天还没有记录，回到首页记下今天吧')
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .margin({ top: 16 })
      }

      Row() {
        Column() {
          Text(`${this.trend.recordedDays}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
          Text('有记录的天数')
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        Column() {
          Text(this.trend.topMood !== '' ? this.trend.topMood : '—')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_PRIMARY)
          Text('最常出现的心情')
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        Column() {
          Text(`${this.trend.avgChars}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
          Text('平均字数')
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 18 })
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .margin({ top: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      this.buildHeader()
      Scroll() {
        Column() {
          if (!this.loaded) {
            Text('统计中…')
              .fontSize(15)
              .fontColor(Constants.COLOR_TEXT_TERTIARY)
              .margin({ top: 40 })
          } else if (this.failed) {
            Text('统计数据加载失败，请返回重试')
              .fontSize(15)
              .fontColor(Constants.COLOR_TEXT_SECONDARY)
              .margin({ top: 40 })
          } else {
            this.buildOverview()
            this.buildTrend()
            this.buildMoods()
            this.buildMonths()
            this.buildContent()
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 32 })
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
