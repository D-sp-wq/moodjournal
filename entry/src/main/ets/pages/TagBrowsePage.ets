import { Constants } from '../common/constants/Constants';
import { ROUTE_LOG_DETAIL, dateParams } from '../common/utils/RouteUtils';
import { DailyLog, logSummary, moodLabel } from '../models/DailyLog';
import { TagCount, collectTags, filterByTag } from '../models/Tag';
import { RepositoryFactory } from '../services/data/RepositoryFactory';
import { Icon, IconKind } from '../components/Icons';
import { MoodDot } from '../components/MoodDot';

/**
 * 标签浏览页：先看「标签云」，点某个标签就在**同一页**看这个标签下的记录。
 *
 * 标签全部来自本机数据库的 daily_logs.tags，不联网、不申请任何权限；
 * 记录与标签的统计/筛选都由 models/Tag.ets 的纯函数完成（有单元测试）。
 */
@Entry
@Component
struct TagBrowsePage {
  /** 全部记录（仓储层已按日期倒序） */
  @State private logs: DailyLog[] = [];
  /** 标签云：按出现次数降序，次数相同按名称升序 */
  @State private tags: TagCount[] = [];
  /** 当前选中的标签；空串表示还停在标签云 */
  @State private selected: string = '';
  @State private loaded: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  onPageShow(): void {
    // 从详情页返回后标签可能已经变了（改了标签 / 删了记录），所以重新读一次
    this.load();
  }

  private async load(): Promise<void> {
    try {
      const logs: DailyLog[] = await RepositoryFactory.getRepository().getDailyLogs();
      this.logs = logs;
      this.tags = collectTags(logs);
    } catch (err) {
      // 读不到就当没有标签，页面显示引导文案而不是崩掉
      this.logs = [];
      this.tags = [];
    } finally {
      this.loaded = true;
    }
  }

  /** 当前标签下的记录（保持仓储层的日期倒序） */
  private selectedLogs(): DailyLog[] {
    return filterByTag(this.logs, this.selected);
  }

  /** 当前标签的累计篇数 */
  private selectedCount(): number {
    return this.selectedLogs().length;
  }

  private openTag(name: string): void {
    this.selected = name;
  }

  private goDetail(date: string): void {
    this.getUIContext().getRouter().pushUrl({
      url: ROUTE_LOG_DETAIL,
      params: dateParams(date)
    });
  }

  /** 页头：左上角大号回退键 + 居中标题，沿用全应用规范（渐变底 + 白字） */
  @Builder
  private buildHeader() {
    Stack() {
      Text('标签浏览')
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

  /** 空态：一个标签都没有时的引导 */
  @Builder
  private buildEmpty() {
    Column() {
      Icon({ kind: IconKind.STAR, iconSize: 56, color: Constants.COLOR_TEXT_TERTIARY, strokeW: 1.6 })
      Text('还没有标签。记日记时给它加个标签，以后就能按标签翻看')
        .fontSize(15)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .textAlign(TextAlign.Center)
        .margin({ top: 12 })
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 40, right: 40 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** 标签云：每个标签一个胶囊，显示「标签名 数量」，按次数降序 */
  @Builder
  private buildTagCloud() {
    Scroll() {
      Column() {
        Text('点一个标签，看这个标签下的所有记录')
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
          .width('100%')

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.tags, (item: TagCount) => {
            Row() {
              Text(item.name)
                .fontSize(15)
                .fontColor(Constants.COLOR_TEXT_PRIMARY)
                .maxLines(1)
              Text(`${item.count}`)
                .fontSize(12)
                .fontColor(Constants.COLOR_ON_BRAND)
                .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                .borderRadius(9)
                .backgroundColor(Constants.COLOR_PRIMARY)
                .margin({ left: 8 })
            }
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .borderRadius(20)
            .backgroundColor(Constants.COLOR_CARD)
            .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
            .margin({ right: 10, bottom: 10 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.openTag(item.name);
            })
          }, (item: TagCount) => item.name)
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  /** 某个标签下的记录：日期 + 心情色点 + 正文摘要，点进详情页 */
  @Builder
  private buildLogRow(log: DailyLog) {
    Row() {
      MoodDot({ mood: log.mood, dotSize: 22 })
      Column() {
        Row() {
          Text(log.date)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
          Text(moodLabel(log.mood, log.customMood))
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_TERTIARY)
            .margin({ left: 8 })
        }
        .width('100%')

        Text(logSummary(log, 40))
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
      }
      .layoutWeight(1)
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)
      Icon({ kind: IconKind.CHEVRON, iconSize: 16, color: Constants.COLOR_TEXT_TERTIARY })
    }
    .width('100%')
    .padding(14)
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 1 }, color: Constants.COLOR_DIVIDER })
    .onClick(() => {
      this.goDetail(log.date);
    })
  }

  /** 某个标签下的记录列表（同页状态切换，不新开页面） */
  @Builder
  private buildTagLogs() {
    Column() {
      Row() {
        Row() {
          Icon({ kind: IconKind.BACK, iconSize: 16, color: Constants.COLOR_PRIMARY, strokeW: 2.4 })
          Text('全部标签')
            .fontSize(14)
            .fontColor(Constants.COLOR_PRIMARY)
            .margin({ left: 2 })
        }
        .padding({ left: 8, right: 12, top: 6, bottom: 6 })
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_SURFACE_SECONDARY)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.selected = '';
        })
        Blank()
        Text(`#${this.selected} · ${this.selectedCount()} 篇`)
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      if (this.selectedCount() === 0) {
        Text('这个标签下还没有记录')
          .fontSize(15)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .margin({ top: 40 })
      } else {
        List() {
          ForEach(this.selectedLogs(), (log: DailyLog) => {
            ListItem() {
              this.buildLogRow(log)
            }
          }, (log: DailyLog) => log.id)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .backgroundColor(Constants.COLOR_CARD)
      }
    }
    .width('100%')
    .layoutWeight(1)
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

      if (!this.loaded) {
        Text('加载中…')
          .fontSize(15)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .margin({ top: 40 })
      } else if (this.tags.length === 0) {
        this.buildEmpty()
      } else if (this.selected === '') {
        this.buildTagCloud()
      } else {
        this.buildTagLogs()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Constants.COLOR_BACKGROUND)
  }
}
