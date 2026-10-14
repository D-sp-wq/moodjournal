import { Constants } from '../common/constants/Constants';
import { DateUtils } from '../common/utils/DateUtils';
import { DateCalcUtils } from '../common/utils/DateCalcUtils';
import { ROUTE_RECORD, dateParams, readDateParam } from '../common/utils/RouteUtils';
import { DailyLog, countChars, moodLabel } from '../models/DailyLog';
import { RepositoryFactory } from '../services/data/RepositoryFactory';
import { MoodDot } from '../components/MoodDot';
import { PhotoService } from '../services/PhotoService';
import { Icon, IconKind } from '../components/Icons';

/**
 * 记录详情（阅读）页：完整看回某一天写下的心情、正文与计划，并可编辑或删除。
 *
 * 通过路由参数 date 打开任意一天；缺省为今天。
 */
@Entry
@Component
struct LogDetailPage {
  @State private date: string = DateUtils.today();
  @State private log: DailyLog | null = null;
  @State private loaded: boolean = false;
  /** 过去的日子已封存：可看、可删，但不能修改 */
  @State private sealed: boolean = false;
  /** 正在全屏查看的照片下标；-1 表示没在看 */
  @State private viewerIndex: number = -1;

  aboutToAppear(): void {
    this.date = readDateParam(this.getUIContext().getRouter().getParams());
  }

  onPageShow(): void {
    // 从编辑页返回后需要刷新，因此放在 onPageShow
    this.load();
  }

  private async load(): Promise<void> {
    try {
      this.log = await RepositoryFactory.getRepository().getDailyLog(this.date);
    } catch (err) {
      this.log = null;
    } finally {
      // 每次进页面都按当下的"今天"重算，跨零点后昨天会立刻变只读
      this.sealed = DateUtils.isSealed(this.date, DateUtils.today());
      this.loaded = true;
    }
  }

  private longDate(): string {
    return `${DateCalcUtils.toChineseDate(this.date)} ${DateCalcUtils.weekdayLabel(this.date)}`;
  }

  private goEdit(): void {
    this.getUIContext().getRouter().pushUrl({
      url: ROUTE_RECORD,
      params: dateParams(this.date)
    });
  }

  private confirmDelete(): void {
    const current: DailyLog | null = this.log;
    if (current === null) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '删除这天的记录',
      message: `${this.date} 的心情与正文都会被删除，且无法恢复。`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Constants.COLOR_PRIMARY,
        action: () => {
          this.doDelete(current.id);
        }
      }
    });
  }

  private async doDelete(id: string): Promise<void> {
    try {
      // 记录里的照片文件要跟着删掉，避免沙箱里留下没人引用的图片
      const current: DailyLog | null = this.log;
      if (current !== null) {
        for (const uri of current.photoUris) {
          PhotoService.removeFile(uri);
        }
      }
      await RepositoryFactory.getRepository().deleteDailyLog(id);
      this.getUIContext().getPromptAction().showToast({ message: '已删除', duration: 1500 });
      this.getUIContext().getRouter().back();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败，请重试', duration: 2000 });
    }
  }

  @Builder
  private buildTopBar() {
    Stack() {
      Text('记录详情')
        .fontSize(20)
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
        if (this.log !== null && !this.sealed) {
          Text('编辑')
            .fontSize(18)
            .fontColor(Constants.COLOR_PRIMARY)
            .onClick(() => {
              this.goEdit();
            })
        } else if (this.sealed) {
          Text('已封存')
            .fontSize(14)
            .fontColor(Constants.COLOR_TEXT_TERTIARY)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(10)
            .backgroundColor(Constants.COLOR_BACKGROUND)
        }
      }
      .width('100%')
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  private buildEmpty() {
    Column() {
      Text('这一天没有记录')
        .fontSize(17)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
      Text(this.sealed
        ? '过去的空白日子不能再补记'
        : '可以现在补写，也可以从日历挑另一天')
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .margin({ top: 8 })
      if (!this.sealed) {
        Button('去记录这一天')
          .height(44)
          .fontSize(17)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .fontColor(Constants.COLOR_ON_BRAND)
          .margin({ top: 24 })
          .onClick(() => {
            this.goEdit();
          })
      }
    }
    .width('100%')
    .padding({ top: 60, bottom: 40 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildContent(current: DailyLog) {
    Column() {
      // 日期 + 心情
      Row() {
        MoodDot({ mood: current.mood, dotSize: 44 })
        Column() {
          Text(moodLabel(current.mood, current.customMood))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
          Text(this.longDate())
            .fontSize(14)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .margin({ top: 4 })
        }
        .margin({ left: 14 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(18)
      .borderRadius(16)
      .backgroundColor(Constants.COLOR_CARD)
      .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })

      // 这天的照片（有才显示）
      if (current.photoUris.length > 0) {
        Column() {
          Text('这天的照片')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .width('100%')
          Row() {
            ForEach(current.photoUris, (uri: string, index: number) => {
              Image(uri)
                .width(96)
                .height(96)
                .borderRadius(12)
                .objectFit(ImageFit.Cover)
                .margin({ right: 10 })
                .onClick(() => {
                  this.viewerIndex = index;
                })
            }, (uri: string) => uri)
          }
          .width('100%')
          .margin({ top: 12 })
        }
        .width('100%')
        .padding(18)
        .borderRadius(16)
        .backgroundColor(Constants.COLOR_CARD)
        .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
        .margin({ top: 16 })
        .alignItems(HorizontalAlign.Start)
      }

      // 封存提示
      if (this.sealed) {
        Text('过去的记录已封存，不能再修改')
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 12 })
      }

      // 正文
      Column() {
        Text('今天发生了什么')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
          .width('100%')
        Text(current.journal.trim() === '' ? '（这天没有写正文）' : current.journal)
          .fontSize(17)
          .lineHeight(28)
          .fontColor(current.journal.trim() === '' ? Constants.COLOR_TEXT_TERTIARY : Constants.COLOR_TEXT_PRIMARY)
          .width('100%')
          .margin({ top: 12 })
      }
      .width('100%')
      .padding(18)
      .borderRadius(16)
      .backgroundColor(Constants.COLOR_CARD)
      .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
      .margin({ top: 16 })
      .alignItems(HorizontalAlign.Start)

      // 明日计划（有才显示）
      if (current.plan.trim() !== '') {
        Column() {
          Text('明天要做的事')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .width('100%')
          Text(current.plan)
            .fontSize(17)
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
        .margin({ top: 16 })
        .alignItems(HorizontalAlign.Start)
      }

      // 这天的标签（只读展示；没有标签时不出现）
      this.buildTagsSection(current)

      Text(`共 ${countChars(current)} 字 · 最后更新于 ${DateCalcUtils.toChineseDate(
        DateUtils.formatDate(new Date(current.updatedAt))) }`)
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 16 })

      Text('删除这天的记录')
        .fontSize(16)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 20, bottom: 8 })
        .onClick(() => {
          this.confirmDelete();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 这天的标签（只读展示）。
   *
   * 详情页的定位是回看，所以这里只把标签显示出来（样式同记录页的标签胶囊，去掉删除按钮），
   * 加标签 / 删标签仍然只在记录页做。没有标签时整个块不出现，不留空行也不留标题。
   */
  @Builder
  private buildTagsSection(current: DailyLog) {
    if (current.tags.length > 0) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(current.tags, (tag: string, index: number) => {
          Text(tag)
            .fontSize(14)
            .fontColor(Constants.COLOR_PRIMARY)
            .maxLines(1)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(Constants.COLOR_SURFACE_SECONDARY)
            .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
            .margin({ right: 8, top: 8 })
        }, (tag: string, index: number) => `${index}_${tag}`)
      }
      .width('100%')
      .margin({ top: 8 })
    }
  }

  /** 全屏看图：点任意处关闭 */
  @Builder
  private buildViewer() {
    Stack() {
      Image(this.log !== null ? this.log.photoUris[this.viewerIndex] : '')
        .objectFit(ImageFit.Contain)
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#E6000000')
    .onClick(() => {
      this.viewerIndex = -1;
    })
  }

  build() {
    Stack() {
      Column() {
        this.buildTopBar()
        Scroll() {
          Column() {
            if (!this.loaded) {
              Text('加载中…')
                .fontSize(15)
                .fontColor(Constants.COLOR_TEXT_TERTIARY)
                .margin({ top: 40 })
            } else if (this.log === null) {
              this.buildEmpty()
            } else {
              this.buildContent(this.log)
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 8, bottom: 32 })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Constants.COLOR_BACKGROUND)

      if (this.viewerIndex >= 0 && this.log !== null) {
        this.buildViewer()
      }
    }
    .width('100%')
    .height('100%')
  }
}
