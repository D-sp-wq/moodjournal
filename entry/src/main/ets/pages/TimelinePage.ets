import { Constants } from '../common/constants/Constants';
import { ROUTE_LOG_DETAIL, dateParams } from '../common/utils/RouteUtils';
import { Anniversary } from '../models/Anniversary';
import { DailyLog } from '../models/DailyLog';
import { TIMELINE_CHECKIN, TimelineItem, buildTimeline } from '../models/Timeline';
import { RepositoryFactory } from '../services/data/RepositoryFactory';
import { EmptyState } from '../components/EmptyState';
import { Icon, IconKind } from '../components/Icons';
import { MoodDot } from '../components/MoodDot';

/**
 * 时间轴页：每日记录与重要日子按日期倒序合并成一条线。
 * 原先是底部导航的一个 tab，改为从「我的」和首页「最近的记录 → 全部」进入。
 */
@Entry
@Component
struct TimelinePage {
  @State private items: TimelineItem[] = [];
  @State private loaded: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  onPageShow(): void {
    // 从详情页/编辑页返回后心情、照片、标签都可能已经变了，所以重新读一次。
    // （aboutToAppear 只在首次创建时执行，router.back() 回来不会重跑）
    this.load();
  }

  private async load(): Promise<void> {
    try {
      const repo = RepositoryFactory.getRepository();
      const logs: DailyLog[] = await repo.getDailyLogs();
      const anniversaries: Anniversary[] = await repo.getImportantDays();
      this.items = buildTimeline(logs, anniversaries);
    } catch (err) {
      this.items = [];
    } finally {
      this.loaded = true;
    }
  }

  private goDetail(date: string): void {
    this.getUIContext().getRouter().pushUrl({
      url: ROUTE_LOG_DETAIL,
      params: dateParams(date)
    });
  }

  /** 页头：左上角回退图标 + 标题居中 */
  @Builder
  private buildHeader() {
    Stack() {
      Text('时间轴')
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
      Row() {
        Stack() {
          Icon({ kind: IconKind.BACK, iconSize: 30, color: Constants.COLOR_TEXT_PRIMARY, strokeW: 2.4 })
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
    .height(52)
    .padding({ left: 12, right: 12 })
    .border({ width: { bottom: 1 }, color: Constants.COLOR_DIVIDER })
  }

  @Builder
  private buildItem(item: TimelineItem) {
    Row() {
      if (item.type === TIMELINE_CHECKIN) {
        MoodDot({ mood: item.mood, dotSize: 22 })
      } else {
        Row()
          .width(22)
          .height(22)
          .borderRadius(11)
          .backgroundColor(Constants.COLOR_PRIMARY)
      }
      Column() {
        Text(item.title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
        if (item.subtitle !== '') {
          Text(item.subtitle)
            .fontSize(14)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .margin({ top: 3 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(item.date)
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
    }
    .width('100%')
    .padding(14)
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 1 }, color: Constants.COLOR_DIVIDER })
    .onClick(() => {
      if (item.type === TIMELINE_CHECKIN) {
        this.goDetail(item.date);
      }
    })
  }

  build() {
    Column() {
      this.buildHeader()

      if (!this.loaded) {
        Text('加载中…')
          .fontSize(15)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .margin({ top: 40 })
      } else if (this.items.length === 0) {
        EmptyState({
          kind: IconKind.TIMELINE,
          title: '还没有记录',
          subtitle: '记录之后，你的心情时间轴会出现在这里'
        })
      } else {
        List() {
          ForEach(this.items, (item: TimelineItem) => {
            ListItem() {
              this.buildItem(item)
            }
          }, (item: TimelineItem) => item.key)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .backgroundColor(Constants.COLOR_CARD)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Constants.COLOR_BACKGROUND)
  }
}
