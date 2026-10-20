import { common } from '@kit.AbilityKit';
import { Constants } from '../common/constants/Constants';
import { DateUtils } from '../common/utils/DateUtils';
import { DateCalcUtils } from '../common/utils/DateCalcUtils';
import { IdUtils } from '../common/utils/IdUtils';
import { DateRouteParams, readDateParam } from '../common/utils/RouteUtils';
import {
  DailyLog,
  Mood,
  MAX_CUSTOM_MOOD_LENGTH,
  MAX_LOG_PHOTOS,
  normalizeCustomMood,
  remainingPhotoSlots
} from '../models/DailyLog';
import { MAX_LOG_TAGS, MAX_TAG_LENGTH, normalizeTagInput } from '../models/Tag';
import { SessionManager } from '../services/storage/SessionManager';
import { RepositoryFactory } from '../services/data/RepositoryFactory';
import { ReminderService } from '../services/ReminderService';
import { PlanReminderService } from '../services/PlanReminderService';
import { PhotoService } from '../services/PhotoService';
import { MoodPicker } from '../components/MoodPicker';
import { Icon, IconKind } from '../components/Icons';

/**
 * 每日记录编辑页：今天的心情 + 今天发生了什么 + 明天要做的事。
 *
 * 通过路由参数 date 可编辑**任意一天**（缺省为今天），
 * 因此同一个页面既能"记录今天"，也能从日历/详情页进来补记或修改历史。
 */
@Entry
@Component
struct RecordPage {
  @State private mood: Mood = Mood.HAPPY;
  @State private journal: string = '';
  @State private plan: string = '';
  @State private customMood: string = '';
  @State private showMoodInput: boolean = false;
  @State private moodDraft: string = '';
  @State private isLoading: boolean = false;
  @State private isEdit: boolean = false;
  @State private date: string = DateUtils.today();
  /** 过去的日子已封存：不能新建、不能修改（删除在详情页仍可用） */
  @State private sealed: boolean = false;
  /** 今天带上的照片（最多 MAX_LOG_PHOTOS 张） */
  @State private photoUris: string[] = [];
  /** 这条记录的标签（最多 MAX_LOG_TAGS 个），供标签浏览页按标签翻看 */
  @State private tags: string[] = [];
  /** 标签输入框里正在敲的内容 */
  @State private tagDraft: string = '';

  aboutToAppear(): void {
    this.date = readDateParam(this.getUIContext().getRouter().getParams());
    this.sealed = DateUtils.isSealed(this.date, DateUtils.today());
    this.loadExisting(false);
  }

  private isToday(): boolean {
    return this.date === DateUtils.today();
  }

  private shortDate(): string {
    return `${Number(this.date.slice(5, 7))}月${Number(this.date.slice(8, 10))}日`;
  }

  private pageTitle(): string {
    if (this.isToday()) {
      return this.isEdit ? '今天的记录' : '记录今天';
    }
    return `${this.shortDate()} 的记录`;
  }

  private async loadExisting(reset: boolean): Promise<void> {
    try {
      const existing: DailyLog | null = await RepositoryFactory.getRepository().getDailyLog(this.date);
      if (existing) {
        this.mood = existing.mood;
        this.customMood = existing.customMood;
        this.journal = existing.journal;
        this.plan = existing.plan;
        this.photoUris = existing.photoUris;
        // 老记录没有标签列，仓储层已兜底成空数组
        this.tags = existing.tags;
        this.isEdit = true;
      } else {
        if (reset) {
          this.mood = Mood.HAPPY;
          this.customMood = '';
          this.journal = '';
          this.plan = '';
          this.photoUris = [];
          this.tags = [];
          this.tagDraft = '';
        }
        this.isEdit = false;
      }
    } catch (err) {
      // 首次记录时读不到旧数据属正常，保持默认值
    }
  }

  private openDatePicker(): void {
    // 起始日限定为今天：封存的日子根本选不到
    this.getUIContext().showDatePickerDialog({
      start: DateUtils.parseDate(DateUtils.today()),
      end: new Date('2100-12-31'),
      selected: DateUtils.parseDate(this.date),
      onDateAccept: (value: Date) => {
        const picked: string = DateUtils.formatDate(value);
        if (picked !== this.date) {
          this.date = picked;
          this.sealed = DateUtils.isSealed(picked, DateUtils.today());
          this.loadExisting(true);
        }
      }
    });
  }

  private async handleSave(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    // 最后一道防线：封存的日子绝不写库（即使被过期参数带进来）
    if (DateUtils.isSealed(this.date, DateUtils.today())) {
      this.getUIContext().getPromptAction().showToast({
        message: '过去的记录不能再修改',
        duration: 2000
      });
      return;
    }
    this.isLoading = true;
    try {
      const repo = RepositoryFactory.getRepository();
      const existing: DailyLog | null = await repo.getDailyLog(this.date);
      const now: number = Date.now();
      const log: DailyLog = {
        id: existing ? existing.id : IdUtils.generate('log'),
        date: this.date,
        mood: this.mood,
        customMood: normalizeCustomMood(this.customMood),
        journal: this.journal.slice(0, Constants.MAX_JOURNAL_LENGTH),
        plan: this.plan.slice(0, Constants.MAX_PLAN_LENGTH),
        photoUris: this.photoUris,
        tags: this.tags,
        // 正常保存的一定是"真正的记录"，覆盖掉可能存在的计划存根标记
        hasEntry: true,
        createdAt: existing ? existing.createdAt : now,
        updatedAt: now
      };
      await repo.upsertDailyLog(log);

      // 关键：只有记录"今天"时才更新今日状态与提醒。
      // 补记历史日期若也写这些，首页与服务卡片会被误标成"今日已记录"。
      const today: boolean = this.isToday();
      if (today) {
        const session = SessionManager.getInstance();
        await session.setLastLoggedDate(this.date);
        await session.setTodayMood(Number(this.mood));
        await session.setTodayCustomMood(normalizeCustomMood(this.customMood));
        await ReminderService.publishDailyRecordReminder();
      }

      // 昨天给今天留的计划可能变了 → 重排「今日提醒」。
      // 不 await：排期要过系统提醒服务，别拖慢保存后的返回；sync 内部已吞掉所有异常。
      PlanReminderService.sync();

      let message: string = today ? '已记下今天' : `已保存 ${this.shortDate()} 的记录`;
      if (this.isEdit) {
        message = today ? '已更新今天的记录' : `已更新 ${this.shortDate()} 的记录`;
      }
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
      this.getUIContext().getRouter().back();
    } catch (err) {
      this.isLoading = false;
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试', duration: 2000 });
    }
  }

  /** 还能再加几张照片 */
  private photoSlots(): number {
    return remainingPhotoSlots(this.photoUris.length);
  }

  /** 从相册选今天的照片，最多补到 MAX_LOG_PHOTOS 张 */
  private async addPhotos(): Promise<void> {
    const context: common.Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return;
    }
    const left: number = this.photoSlots();
    if (left <= 0) {
      return;
    }
    try {
      const added: string[] = await PhotoService.pickLogPhotos(context, left);
      if (added.length > 0) {
        this.photoUris = this.photoUris.concat(added);
      }
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '照片保存失败，请重试', duration: 2000 });
    }
  }

  /** 删掉一张照片：先从列表移除，再清理沙箱文件 */
  private removePhoto(index: number): void {
    const dropped: string = this.photoUris[index];
    const next: string[] = [];
    for (let i: number = 0; i < this.photoUris.length; i++) {
      if (i !== index) {
        next.push(this.photoUris[i]);
      }
    }
    this.photoUris = next;
    PhotoService.removeFile(dropped);
  }

  /** 回车或点「添加」：把输入框里的标签并进这条记录（已在的记录不会被重复加入） */
  private addTag(): void {
    if (this.tagDraft.trim() === '') {
      return;
    }
    if (this.tags.length >= MAX_LOG_TAGS) {
      this.getUIContext().getPromptAction().showToast({
        message: `最多 ${MAX_LOG_TAGS} 个标签`,
        duration: 2000
      });
      return;
    }
    const next: string[] = normalizeTagInput(this.tagDraft, this.tags);
    if (next.length === this.tags.length) {
      this.getUIContext().getPromptAction().showToast({ message: '这个标签已经加过了', duration: 2000 });
      return;
    }
    this.tags = next;
    this.tagDraft = '';
  }

  /** 删掉一个标签 */
  private removeTag(index: number): void {
    const next: string[] = [];
    for (let i: number = 0; i < this.tags.length; i++) {
      if (i !== index) {
        next.push(this.tags[i]);
      }
    }
    this.tags = next;
  }

  /** 确认自定义心情：空文字不放行，弹层保持打开 */
  private confirmCustomMood(): void {
    const text: string = normalizeCustomMood(this.moodDraft);
    if (text === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请写下你的心情', duration: 2000 });
      return;
    }
    this.customMood = text;
    this.mood = Mood.CUSTOM;
    this.showMoodInput = false;
  }

  @Builder
  private buildTopBar() {
    Stack() {
      Text(this.pageTitle())
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
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
    .height(56)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  private buildMoodSection() {
    Column() {
      // 日期胶囊：点它唤出日期选择器，可补记/回看任意一天
      Row() {
        Icon({ kind: IconKind.CALENDAR, iconSize: 18, color: Constants.COLOR_PRIMARY })
        Text(`${this.date} ${DateCalcUtils.weekdayLabel(this.date)}`)
          .fontSize(15)
          .fontColor(Constants.COLOR_PRIMARY)
          .margin({ left: 6 })
        Blank()
        Icon({ kind: IconKind.CHEVRON, iconSize: 16, color: Constants.COLOR_TEXT_TERTIARY })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 9, bottom: 9 })
      .borderRadius(19)
      .backgroundColor(Constants.COLOR_BACKGROUND)
      .onClick(() => {
        this.openDatePicker();
      })

      Text(this.isToday() ? '今天心情怎么样？' : `${this.shortDate()}心情怎么样？`)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .margin({ top: 16 })

      MoodPicker({
        selected: this.mood,
        customMood: this.customMood,
        onSelect: (mood: Mood) => {
          this.mood = mood;
        },
        onSelectCustom: () => {
          this.moodDraft = this.customMood;
          this.showMoodInput = true;
        }
      })
        .margin({ top: 12 })
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
    .alignItems(HorizontalAlign.Start)
  }

  /** 今天的照片：最多 3 张，可加可删；封存态只读 */
  @Builder
  private buildPhotoSection() {
    Column() {
      Row() {
        Text('今天的照片')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
        Blank()
        Text(`${this.photoUris.length}/${MAX_LOG_PHOTOS}`)
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
      }
      .width('100%')

      Row() {
        ForEach(this.photoUris, (uri: string, index: number) => {
          Stack({ alignContent: Alignment.TopEnd }) {
            Image(uri)
              .width(88)
              .height(88)
              .borderRadius(12)
              .objectFit(ImageFit.Cover)
            if (!this.sealed) {
              Stack() {
                Icon({ kind: IconKind.CLOSE, iconSize: 13, color: Constants.COLOR_ON_BRAND })
              }
              .width(22)
              .height(22)
              .borderRadius(11)
              .backgroundColor('#99000000')
              .margin({ top: 4, right: 4 })
              .onClick(() => {
                this.removePhoto(index);
              })
            }
          }
          .margin({ right: 10 })
        }, (uri: string) => uri)

        if (!this.sealed && this.photoSlots() > 0) {
          Column() {
            Icon({ kind: IconKind.PLUS, iconSize: 24, color: Constants.COLOR_TEXT_TERTIARY })
            Text('添加')
              .fontSize(13)
              .fontColor(Constants.COLOR_TEXT_TERTIARY)
              .margin({ top: 4 })
          }
          .width(88)
          .height(88)
          .borderRadius(12)
          .backgroundColor(Constants.COLOR_BACKGROUND)
          .border({ width: 1, color: Constants.COLOR_DIVIDER })
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.addPhotos();
          })
        }
      }
      .width('100%')
      .margin({ top: 12 })

      Text(`最多 ${MAX_LOG_PHOTOS} 张，只保存在应用内`)
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .margin({ top: 10 })
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
    .margin({ top: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildJournalSection() {
    Column() {
      Row() {
        Text('今天发生了什么')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
        Blank()
        Text(`${this.journal.length}/${Constants.MAX_JOURNAL_LENGTH}`)
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
      }
      .width('100%')

      TextArea({ placeholder: '写下今天发生的事、遇到的人、一点小情绪…', text: this.journal })
        .width('100%')
        .height(140)
        .fontSize(17)
        .maxLength(Constants.MAX_JOURNAL_LENGTH)
        .backgroundColor(Constants.COLOR_BACKGROUND)
        .margin({ top: 8 })
        .onChange((value: string) => {
          this.journal = value;
        })
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
    .margin({ top: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 标签卡片：给这一天贴几个标签，之后可以在「标签浏览」里按标签翻看 */
  @Builder
  private buildTagSection() {
    Column() {
      Row() {
        Text('标签')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
        Blank()
        Text(`${this.tags.length}/${MAX_LOG_TAGS}`)
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
      }
      .width('100%')

      // 已有标签：胶囊 + 点 × 删除
      if (this.tags.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.tags, (tag: string, index: number) => {
            Row() {
              Text(tag)
                .fontSize(14)
                .fontColor(Constants.COLOR_PRIMARY)
                .maxLines(1)
              if (!this.sealed) {
                Stack() {
                  Icon({ kind: IconKind.CLOSE, iconSize: 12, color: Constants.COLOR_TEXT_SECONDARY })
                }
                .width(20)
                .height(20)
                .borderRadius(10)
                .margin({ left: 4 })
                .onClick(() => {
                  this.removeTag(index);
                })
              }
            }
            .padding({ left: 12, right: 8, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(Constants.COLOR_SURFACE_SECONDARY)
            .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
            .margin({ right: 8, top: 8 })
            .alignItems(VerticalAlign.Center)
          }, (tag: string) => tag)
        }
        .width('100%')
        .margin({ top: 4 })
      }

      if (!this.sealed) {
        Row() {
          TextInput({ placeholder: '输入标签，空格或逗号分隔', text: this.tagDraft })
            .layoutWeight(1)
            .height(42)
            .fontSize(15)
            .maxLength(MAX_TAG_LENGTH * MAX_LOG_TAGS)
            .backgroundColor(Constants.COLOR_BACKGROUND)
            .enterKeyType(EnterKeyType.Done)
            .onChange((value: string) => {
              this.tagDraft = value;
            })
            .onSubmit(() => {
              this.addTag();
            })
          Button('添加')
            .height(42)
            .fontSize(15)
            .backgroundColor(Constants.COLOR_PRIMARY)
            .fontColor(Constants.COLOR_ON_BRAND)
            .margin({ left: 10 })
            .onClick(() => {
              this.addTag();
            })
        }
        .width('100%')
        .margin({ top: 10 })
      }

      Text(`最多 ${MAX_LOG_TAGS} 个标签，每个不超过 ${MAX_TAG_LENGTH} 字`)
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .margin({ top: 10 })
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
    .margin({ top: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildPlanSection() {
    Column() {
      Row() {
        Text('明天要做的事')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
        Blank()
        Text(`${this.plan.length}/${Constants.MAX_PLAN_LENGTH}`)
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
      }
      .width('100%')

      TextArea({ placeholder: '给明天的自己留几件事…', text: this.plan })
        .width('100%')
        .height(96)
        .fontSize(17)
        .maxLength(Constants.MAX_PLAN_LENGTH)
        .backgroundColor(Constants.COLOR_BACKGROUND)
        .margin({ top: 8 })
        .onChange((value: string) => {
          this.plan = value;
        })

      Text('明天打开应用时，这里写下的计划会提醒你')
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .border({ width: 1, color: Constants.COLOR_BORDER_SUBTLE })
    .margin({ top: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 锁定态：正常路径进不来（选择器选不到过去，各入口也已拦截），仅作兜底 */
  @Builder
  private buildSealedNotice() {
    Column() {
      Text('这一天已封存')
        .fontSize(19)
        .fontWeight(FontWeight.Medium)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
      Text('过去的记录不能再修改')
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .margin({ top: 8 })
      Button('返回')
        .height(44)
        .fontSize(17)
        .backgroundColor(Constants.COLOR_PRIMARY)
        .fontColor(Constants.COLOR_ON_BRAND)
        .margin({ top: 24 })
        .onClick(() => {
          this.getUIContext().getRouter().back();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** 自己写心情的输入弹层。必须挂在页面根节点上，放进 Scroll 会被裁切 */
  @Builder
  private buildMoodInput() {
    Column() {
      Column()
        .width('100%')
        .layoutWeight(1)
        .onClick(() => {
          this.showMoodInput = false;
        })

      Column() {
        Text('自己写一个心情')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
          .width('100%')
        Text('写下此刻的心情，它会和其他心情一样被记录')
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 4 })

        TextInput({ placeholder: '比如：元气满满', text: this.moodDraft })
          .width('100%')
          .height(46)
          .fontSize(17)
          .maxLength(MAX_CUSTOM_MOOD_LENGTH)
          .backgroundColor(Constants.COLOR_BACKGROUND)
          .margin({ top: 14 })
          .onChange((value: string) => {
            this.moodDraft = value;
          })

        Row() {
          Text(`最多 ${MAX_CUSTOM_MOOD_LENGTH} 字`)
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_TERTIARY)
          Blank()
          Text(`${normalizeCustomMood(this.moodDraft).length}/${MAX_CUSTOM_MOOD_LENGTH}`)
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_TERTIARY)
        }
        .width('100%')
        .margin({ top: 8 })

        Row() {
          Button('取消')
            .layoutWeight(1)
            .height(42)
            .fontSize(17)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .backgroundColor(Constants.COLOR_BACKGROUND)
            .onClick(() => {
              this.showMoodInput = false;
            })
          Button('确定')
            .layoutWeight(1)
            .height(42)
            .fontSize(17)
            .backgroundColor(Constants.COLOR_PRIMARY)
            .fontColor(Constants.COLOR_ON_BRAND)
            .margin({ left: 10 })
            .onClick(() => {
              this.confirmCustomMood();
            })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('100%')
      .padding(20)
      .borderRadius({ topLeft: 20, topRight: 20 })
      .backgroundColor(Constants.COLOR_CARD)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
  }

  build() {
    Stack() {
      Column() {
        this.buildTopBar()
        if (this.sealed) {
          this.buildSealedNotice()
        } else {
          Scroll() {
            Column() {
              this.buildMoodSection()
              this.buildPhotoSection()
              this.buildJournalSection()
              this.buildTagSection()
              this.buildPlanSection()
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 20 })
            .alignItems(HorizontalAlign.Start)
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)

          // 底部固定大按钮：比右上角小字好点很多
          Row() {
            Button('保存今天的记录')
              .layoutWeight(1)
              .height(50)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .borderRadius(14)
              .backgroundColor(Constants.COLOR_PRIMARY)
              .fontColor(Constants.COLOR_ON_BRAND)
              .enabled(!this.isLoading)
              .onClick(() => {
                this.handleSave();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 6, bottom: 16 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Constants.COLOR_BACKGROUND)

      if (this.showMoodInput) {
        this.buildMoodInput()
      }
    }
    .width('100%')
    .height('100%')
  }
}
