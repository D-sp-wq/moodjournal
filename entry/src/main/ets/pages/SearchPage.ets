import { Constants } from '../common/constants/Constants';
import { DateUtils } from '../common/utils/DateUtils';
import { ROUTE_LOG_DETAIL, dateParams } from '../common/utils/RouteUtils';
import {
  DailyLog,
  TextSegment,
  matchSnippet,
  moodLabel,
  splitByKeyword
} from '../models/DailyLog';
import {
  RANGE_OPTIONS,
  SearchFilters,
  applyFilters,
  availableMoods,
  describeFilters,
  isFilterEmpty,
  rangeLabel
} from '../models/SearchFilter';
import { TagCount, collectTags } from '../models/Tag';
import { RepositoryFactory } from '../services/data/RepositoryFactory';
import { MoodDot } from '../components/MoodDot';
import { Icon, IconKind } from '../components/Icons';

/**
 * 搜索页：在全部记录里按关键字查找，匹配「心情 / 今天发生了什么 / 明天要做的事」。
 *
 * 关键词之外还支持四个筛选条件（心情 / 时间范围 / 只看有照片 / 标签），
 * 它们与关键词是「与」关系；筛选逻辑全部在 models/SearchFilter.ets 的纯函数里（有单元测试），
 * 本页只负责收集条件与渲染，全部本机计算，不联网、不申请任何权限。
 */
@Entry
@Component
struct SearchPage {
  @State private keyword: string = '';
  @State private mood: string = '';
  @State private rangeDays: number = 0;
  @State private photoOnly: boolean = false;
  @State private tag: string = '';
  @State private results: DailyLog[] = [];
  @State private allLogs: DailyLog[] = [];
  /** 所有记录用过的标签，按出现次数降序（来自 models/Tag.ets） */
  @State private tagOptions: TagCount[] = [];
  /** 所有记录里实际出现过的心情，按出现次数降序 */
  @State private moodOptions: string[] = [];
  @State private loaded: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  onPageShow(): void {
    // 从记录页 / 详情页返回后标签可能已经变了，重新读一次
    this.load();
  }

  private async load(): Promise<void> {
    try {
      const logs: DailyLog[] = await RepositoryFactory.getRepository().getDailyLogs();
      this.allLogs = logs;
      this.tagOptions = collectTags(logs);
      this.moodOptions = availableMoods(logs);
    } catch (err) {
      this.allLogs = [];
      this.tagOptions = [];
      this.moodOptions = [];
    } finally {
      this.loaded = true;
      // 标签可能被删了，当前选中的标签若已不存在就取消选择
      if (this.tag !== '' && !this.hasTagOption(this.tag)) {
        this.tag = '';
      }
      this.applyFilter();
    }
  }

  /** 当前可选标签里是否还有这个名字 */
  private hasTagOption(name: string): boolean {
    for (const item of this.tagOptions) {
      if (item.name === name) {
        return true;
      }
    }
    return false;
  }

  /** 把界面上的状态收成一份筛选条件 */
  private currentFilters(): SearchFilters {
    const filters: SearchFilters = {
      keyword: this.keyword,
      mood: this.mood,
      rangeDays: this.rangeDays,
      photoOnly: this.photoOnly,
      tag: this.tag
    };
    return filters;
  }

  private applyFilter(): void {
    this.results = applyFilters(this.allLogs, this.currentFilters(), DateUtils.today());
  }

  /** 点心情胶囊：再点一次取消选择 */
  private toggleMood(label: string): void {
    this.mood = this.mood === label ? '' : label;
    this.applyFilter();
  }

  /** 点标签胶囊：再点一次取消选择 */
  private toggleTag(name: string): void {
    this.tag = this.tag === name ? '' : name;
    this.applyFilter();
  }

  /** 时间范围是单选，点「不限」即取消时间条件 */
  private chooseRange(days: number): void {
    this.rangeDays = days;
    this.applyFilter();
  }

  private togglePhotoOnly(): void {
    this.photoOnly = !this.photoOnly;
    this.applyFilter();
  }

  /** 清除全部筛选条件（关键词不动，它有自己的「清空」） */
  private clearFilters(): void {
    this.mood = '';
    this.rangeDays = 0;
    this.photoOnly = false;
    this.tag = '';
    this.applyFilter();
  }

  /** 是否已经输入了关键词或选了筛选条件（决定空态显示引导还是「没找到」） */
  private hasQuery(): boolean {
    return this.keyword.trim() !== '' || !isFilterEmpty(this.currentFilters());
  }

  private goDetail(date: string): void {
    this.getUIContext().getRouter().pushUrl({
      url: ROUTE_LOG_DETAIL,
      params: dateParams(date)
    });
  }

  @Builder
  private buildHighlighted(text: string) {
    Text() {
      ForEach(splitByKeyword(text, this.keyword), (seg: TextSegment, index: number) => {
        Span(seg.text)
          .fontColor(seg.hit ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_SECONDARY)
          .fontWeight(seg.hit ? FontWeight.Medium : FontWeight.Normal)
      }, (seg: TextSegment, index: number) => `${index}_${seg.text}`)
    }
    .fontSize(14)
    .maxLines(2)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
    .margin({ top: 4 })
  }

  @Builder
  private buildResult(log: DailyLog) {
    Row() {
      MoodDot({ mood: log.mood, dotSize: 22 })
      Column() {
        Row() {
          Text(moodLabel(log.mood, log.customMood))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
          Blank()
          Text(log.date)
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_TERTIARY)
        }
        .width('100%')

        this.buildHighlighted(matchSnippet(log, this.keyword, 40))

        // 这条记录带的标签（有才显示）
        if (log.tags.length > 0) {
          Text(`#${log.tags.join(' #')}`)
            .fontSize(12)
            .fontColor(Constants.COLOR_TEXT_TERTIARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
        }
      }
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Icon({ kind: IconKind.CHEVRON, iconSize: 20, color: Constants.COLOR_TEXT_TERTIARY })
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 1 }, color: Constants.COLOR_DIVIDER })
    .onClick(() => {
      this.goDetail(log.date);
    })
  }

  // ---------------- 筛选栏 ----------------

  /** 分组标题：小字，与胶囊拉开层次 */
  @Builder
  private buildGroupLabel(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor(Constants.COLOR_TEXT_TERTIARY)
      .margin({ top: 10, bottom: 6 })
  }

  /** 一枚可点胶囊：选中态用品牌色实底，未选中用浅底 + 细边框 */
  @Builder
  private buildChip(label: string, active: boolean, action: () => void) {
    Text(label)
      .fontSize(14)
      .maxLines(1)
      .fontColor(active ? Constants.COLOR_ON_BRAND : Constants.COLOR_TEXT_SECONDARY)
      .padding({ left: 13, right: 13, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(active ? Constants.COLOR_PRIMARY : Constants.COLOR_SURFACE_SECONDARY)
      .border({ width: 1, color: active ? Constants.COLOR_PRIMARY : Constants.COLOR_BORDER_SUBTLE })
      .margin({ right: 8 })
      .onClick(() => {
        action();
      })
  }

  /** 心情胶囊：横向可滚动，点一个选中，再点取消 */
  @Builder
  private buildMoodRow() {
    Scroll() {
      Row() {
        ForEach(this.moodOptions, (label: string, index: number) => {
          this.buildChip(label, this.mood === label, () => {
            this.toggleMood(label);
          })
        }, (label: string, index: number) => `${index}_${label}`)
      }
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .align(Alignment.Start)
  }

  /** 标签：可能很多，横向滚动；选中的标签若已被删掉则原样显示，仍可取消 */
  @Builder
  private buildTagRow() {
    Scroll() {
      Row() {
        ForEach(this.tagOptions, (item: TagCount) => {
          this.buildChip(item.name, this.tag === item.name, () => {
            this.toggleTag(item.name);
          })
        }, (item: TagCount) => item.name)
        if (this.tag !== '' && !this.hasTagOption(this.tag)) {
          this.buildChip(this.tag, true, () => {
            this.toggleTag(this.tag);
          })
        }
      }
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .align(Alignment.Start)
  }

  /** 只看有照片：一个开关胶囊，带相机图标 */
  @Builder
  private buildPhotoChip() {
    Row() {
      Icon({
        kind: IconKind.PHOTO,
        iconSize: 14,
        color: this.photoOnly ? Constants.COLOR_ON_BRAND : Constants.COLOR_TEXT_SECONDARY
      })
      Text('只看有照片')
        .fontSize(14)
        .fontColor(this.photoOnly ? Constants.COLOR_ON_BRAND : Constants.COLOR_TEXT_SECONDARY)
        .margin({ left: 5 })
    }
    .padding({ left: 11, right: 13, top: 6, bottom: 6 })
    .borderRadius(16)
    .backgroundColor(this.photoOnly ? Constants.COLOR_PRIMARY : Constants.COLOR_SURFACE_SECONDARY)
    .border({
      width: 1,
      color: this.photoOnly ? Constants.COLOR_PRIMARY : Constants.COLOR_BORDER_SUBTLE
    })
    .margin({ right: 8 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.togglePhotoOnly();
    })
  }

  /**
   * 时间：不限 / 近 7 天 / 近 30 天 / 近一年，末尾直接接「只看有照片」开关。
   * 两行并成一行是为了不让筛选栏在手机上占掉太多屏幕。
   */
  @Builder
  private buildTimeRow() {
    Scroll() {
      Row() {
        ForEach(this.rangeLabels(), (label: string, index: number) => {
          this.buildChip(label, index === RANGE_OPTIONS.indexOf(this.rangeDays), () => {
            this.chooseRange(RANGE_OPTIONS[index]);
          })
        }, (label: string, index: number) => `${index}_${label}`)
        Row()
          .width(1)
          .height(20)
          .backgroundColor(Constants.COLOR_DIVIDER)
          .margin({ right: 8 })
        this.buildPhotoChip()
      }
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .align(Alignment.Start)
  }

  /** 筛选栏：心情 / 时间（含只看有照片）/ 标签，每组横向可滚 */
  @Builder
  private buildFilterBar() {
    Column() {
      this.buildGroupLabel('心情')
      if (this.moodOptions.length === 0) {
        Text('还没有带心情的记录')
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
      } else {
        this.buildMoodRow()
      }

      this.buildGroupLabel('时间')
      this.buildTimeRow()

      this.buildGroupLabel('标签')
      Row() {
        if (this.tagOptions.length === 0 && this.tag === '') {
          Text('还没有记录用过标签')
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_TERTIARY)
        } else {
          this.buildTagRow()
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 2, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
    .border({ width: { bottom: 1 }, color: Constants.COLOR_DIVIDER })
  }

  /** 时间范围的四个文案，顺序与 RANGE_OPTIONS 一一对应 */
  private rangeLabels(): string[] {
    const labels: string[] = [];
    for (const days of RANGE_OPTIONS) {
      labels.push(rangeLabel(days));
    }
    return labels;
  }

  /** 已选条件回显 + 清除全部（没有筛选时整行不出现） */
  @Builder
  private buildActiveSummary() {
    Row() {
      Text(describeFilters(this.currentFilters()).join(' · '))
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text('清除全部')
        .fontSize(13)
        .fontColor(Constants.COLOR_PRIMARY)
        .margin({ left: 10 })
        .onClick(() => {
          this.clearFilters();
        })
    }
    .width('100%')
    .margin({ top: 12 })
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 空态：文案按原因分三种 —— 一条记录都没有 / 筛选后没结果 / 关键词没搜到。
   * 「关键词为空但有筛选」正是「试试放宽筛选」那种情况。
   */
  @Builder
  private buildHint() {
    Column() {
      if (this.keyword.trim() === '' && !isFilterEmpty(this.currentFilters())) {
        Text('没有符合条件的记录，试试放宽筛选')
          .fontSize(16)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
        Text('可以点「清除全部」取消筛选，或者换个心情、时间范围再看')
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .margin({ top: 8 })
          .textAlign(TextAlign.Center)
      } else {
        Text('没有找到匹配的记录')
          .fontSize(16)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
        Text('换个词试试，或者检查有没有错别字')
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .margin({ top: 8 })
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .padding({ top: 50, bottom: 30 })
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      // 顶部：左上角回退图标 + 搜索框
      Row() {
        Stack() {
          Icon({ kind: IconKind.BACK, iconSize: 30, color: Constants.COLOR_TEXT_PRIMARY, strokeW: 2.4 })
        }
        .padding(12)
        .margin({ left: -6 })
        .onClick(() => {
          this.getUIContext().getRouter().back();
        })
        TextInput({ placeholder: '搜索日记内容或心情', text: this.keyword })
          .layoutWeight(1)
          .height(42)
          .fontSize(17)
          .margin({ left: 8 })
          .backgroundColor(Constants.COLOR_BACKGROUND)
          .onChange((value: string) => {
            this.keyword = value;
            this.applyFilter();
          })
        if (this.keyword !== '') {
          Text('清空')
            .fontSize(15)
            .fontColor(Constants.COLOR_PRIMARY)
            .margin({ left: 10 })
            .onClick(() => {
              this.keyword = '';
              this.applyFilter();
            })
        }
      }
      .width('100%')
      .height(60)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .border({ width: { bottom: 1 }, color: Constants.COLOR_DIVIDER })

      // 筛选栏：关键词之外的四个条件
      this.buildFilterBar()

      Scroll() {
        Column() {
          if (!this.loaded) {
            Text('加载中…')
              .fontSize(15)
              .fontColor(Constants.COLOR_TEXT_TERTIARY)
              .margin({ top: 40 })
          } else {
            if (!isFilterEmpty(this.currentFilters())) {
              this.buildActiveSummary()
            }

            if (this.results.length === 0 && !this.hasQuery()) {
              Text(this.allLogs.length === 0 ? '还没有记录' : '输入关键字开始搜索')
                .fontSize(16)
                .fontColor(Constants.COLOR_TEXT_SECONDARY)
                .margin({ top: 40 })
              Text(this.allLogs.length === 0
                ? '先去「记录」里写下今天的心情，之后就能在这里搜索'
                : '可以搜「今天发生了什么」「明天要做的事」，也可以搜心情（如 开心、元气满满），还能按上面几个条件筛选')
                .fontSize(14)
                .fontColor(Constants.COLOR_TEXT_TERTIARY)
                .margin({ top: 8 })
                .textAlign(TextAlign.Center)
            } else if (this.results.length === 0) {
              this.buildHint()
            } else {
              Row() {
                Text(`共 ${this.results.length} 条`)
                  .fontSize(14)
                  .fontColor(Constants.COLOR_TEXT_TERTIARY)
                Blank()
              }
              .width('100%')
              .margin({ top: 14, bottom: 4 })

              ForEach(this.results, (log: DailyLog) => {
                this.buildResult(log)
              }, (log: DailyLog) => log.id)
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
    .backgroundColor(Constants.COLOR_CARD)
  }
}
