import { Constants } from '../common/constants/Constants';
import { DateUtils } from '../common/utils/DateUtils';
import { DateCalcUtils } from '../common/utils/DateCalcUtils';
import { IdUtils } from '../common/utils/IdUtils';
import {
  TaskPlan,
  TaskProgress,
  computeTaskProgress,
  clampPlannedDays,
  MAX_TASK_PLANS,
  MAX_PLANNED_DAYS,
  MIN_PLANNED_DAYS
} from '../models/TaskPlan';
import { RepositoryFactory } from '../services/data/RepositoryFactory';
import { Icon, IconKind } from '../components/Icons';

interface TaskItem {
  plan: TaskPlan;
  progress: TaskProgress;
}

/**
 * 任务规划页：为一件重要的事规划用多少天完成，最多同时规划 6 个。
 * 全部本地存储，不联网。
 */
@Entry
@Component
struct TaskPlanPage {
  @State private plans: TaskPlan[] = [];
  @State private items: TaskItem[] = [];
  @State private loaded: boolean = false;
  @State private saving: boolean = false;

  @State private newTitle: string = '';
  @State private newStartDate: string = DateUtils.today();
  @State private newDaysText: string = '7';

  aboutToAppear(): void {
    this.load();
  }

  onPageShow(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      this.plans = await RepositoryFactory.getRepository().getTaskPlans();
      this.rebuild();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '加载失败', duration: 2000 });
    } finally {
      this.loaded = true;
    }
  }

  /** 计算进度并排序：未完成在前（按剩余天数升序），已完成沉底 */
  private rebuild(): void {
    const today: string = DateUtils.today();
    const list: TaskItem[] = [];
    for (const p of this.plans) {
      list.push({ plan: p, progress: computeTaskProgress(p, today) });
    }
    list.sort((a: TaskItem, b: TaskItem): number => {
      if (a.plan.completed !== b.plan.completed) {
        return a.plan.completed ? 1 : -1;
      }
      if (a.plan.completed) {
        return b.plan.completedAt - a.plan.completedAt;
      }
      return a.progress.remainingDays - b.progress.remainingDays;
    });
    this.items = list;
  }

  private openStartDatePicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2000-1-1'),
      end: new Date('2100-12-31'),
      selected: DateUtils.parseDate(this.newStartDate),
      onDateAccept: (value: Date) => {
        this.newStartDate = DateUtils.formatDate(value);
      }
    });
  }

  private async handleAdd(): Promise<void> {
    const title: string = this.newTitle.trim();
    if (title === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请输入任务名称', duration: 2000 });
      return;
    }
    if (this.plans.length >= MAX_TASK_PLANS) {
      this.getUIContext().getPromptAction().showToast({ message: `最多只能规划 ${MAX_TASK_PLANS} 个任务`, duration: 2000 });
      return;
    }
    const raw: number = Number(this.newDaysText.trim());
    if (this.newDaysText.trim() === '' || Number.isNaN(raw)) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入计划天数', duration: 2000 });
      return;
    }

    this.saving = true;
    try {
      const plan: TaskPlan = {
        id: IdUtils.generate('task'),
        title: title.slice(0, 30),
        startDate: this.newStartDate,
        plannedDays: clampPlannedDays(raw),
        completed: false,
        completedAt: 0,
        createdAt: Date.now()
      };
      await RepositoryFactory.getRepository().upsertTaskPlan(plan);
      this.newTitle = '';
      this.newDaysText = '7';
      this.newStartDate = DateUtils.today();
      await this.load();
      this.getUIContext().getPromptAction().showToast({ message: '任务已添加', duration: 1500 });
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '添加失败，请重试', duration: 2000 });
    } finally {
      this.saving = false;
    }
  }

  private async toggleCompleted(item: TaskItem): Promise<void> {
    try {
      const updated: TaskPlan = {
        id: item.plan.id,
        title: item.plan.title,
        startDate: item.plan.startDate,
        plannedDays: item.plan.plannedDays,
        completed: !item.plan.completed,
        completedAt: item.plan.completed ? 0 : Date.now(),
        createdAt: item.plan.createdAt
      };
      await RepositoryFactory.getRepository().upsertTaskPlan(updated);
      await this.load();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '操作失败，请重试', duration: 2000 });
    }
  }

  private confirmDelete(item: TaskItem): void {
    this.getUIContext().showAlertDialog({
      title: '删除任务',
      message: `确定删除「${item.plan.title}」吗？`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Constants.COLOR_PRIMARY,
        action: () => {
          this.doDelete(item);
        }
      }
    });
  }

  private async doDelete(item: TaskItem): Promise<void> {
    try {
      await RepositoryFactory.getRepository().deleteTaskPlan(item.plan.id);
      await this.load();
      this.getUIContext().getPromptAction().showToast({ message: '已删除', duration: 1500 });
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败，请重试', duration: 2000 });
    }
  }

  private remainLabel(item: TaskItem): string {
    if (item.plan.completed) {
      return '已完成';
    }
    const r: number = item.progress.remainingDays;
    if (r < 0) {
      return `已超期 ${-r} 天`;
    }
    if (r === 0) {
      return '今天到期';
    }
    if (item.progress.notStarted) {
      return `未开始 · 还有 ${r} 天`;
    }
    return `还剩 ${r} 天`;
  }

  private isUrgent(item: TaskItem): boolean {
    return !item.plan.completed && item.progress.overdue;
  }

  @Builder
  private buildHeader() {
    Column() {
      Stack() {
        Text('任务规划')
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
          Text(`${this.plans.length} / ${MAX_TASK_PLANS}`)
            .fontSize(15)
            .fontColor(Constants.COLOR_ON_BRAND)
            .opacity(0.9)
        }
        .width('100%')
      }
      .width('100%')

      Text('为一件重要的事，规划用多少天完成')
        .fontSize(14)
        .fontColor(Constants.COLOR_ON_BRAND)
        .opacity(0.9)
        .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 14, bottom: 20 })
    .linearGradient({
      angle: 135,
      colors: [[Constants.COLOR_HERO_START, 0.0], [Constants.COLOR_HERO_END, 1.0]]
    })
  }

  @Builder
  private buildAddCard() {
    Column() {
      Text('新建任务')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%')

      TextInput({ placeholder: '要完成的重要事情', text: this.newTitle })
        .width('100%')
        .height(44)
        .fontSize(17)
        .maxLength(30)
        .backgroundColor(Constants.COLOR_BACKGROUND)
        .margin({ top: 12 })
        .onChange((value: string) => {
          this.newTitle = value;
        })

      Row() {
        Text('开始日期')
          .fontSize(16)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
        Blank()
        Text(this.newStartDate)
          .fontSize(16)
          .fontColor(Constants.COLOR_PRIMARY)
          .onClick(() => {
            this.openStartDatePicker();
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .border({ width: { top: 1 }, color: Constants.COLOR_DIVIDER })

      Row() {
        Text('计划天数')
          .fontSize(16)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
        Blank()
        TextInput({ text: this.newDaysText })
          .width(90)
          .height(38)
          .fontSize(16)
          .type(InputType.Number)
          .textAlign(TextAlign.Center)
          .backgroundColor(Constants.COLOR_BACKGROUND)
          .onChange((value: string) => {
            this.newDaysText = value;
          })
        Text('天')
          .fontSize(16)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
          .margin({ left: 6 })
      }
      .width('100%')
      .padding({ bottom: 4 })

      Text(`${MIN_PLANNED_DAYS} – ${MAX_PLANNED_DAYS} 天，超出范围会自动收敛`)
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 8 })

      Button('添加任务')
        .width('100%')
        .height(44)
        .fontSize(17)
        .backgroundColor(Constants.COLOR_PRIMARY)
        .fontColor(Constants.COLOR_ON_BRAND)
        .margin({ top: 14 })
        .enabled(!this.saving)
        .onClick(() => {
          this.handleAdd();
        })
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildFullHint() {
    Column() {
      Text(`已规划满 ${MAX_TASK_PLANS} 个任务`)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
      Text('完成或删除一个任务后，就可以继续新建了')
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildEmpty() {
    Column() {
      Text('还没有任务规划')
        .fontSize(16)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
      Text('在上面写下第一件要紧的事吧')
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .margin({ top: 8 })
    }
    .width('100%')
    .padding({ top: 36, bottom: 36 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildTaskCard(item: TaskItem) {
    Column() {
      Row() {
        Text(item.plan.title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(item.plan.completed ? Constants.COLOR_TEXT_TERTIARY : Constants.COLOR_TEXT_PRIMARY)
          .decoration({ type: item.plan.completed ? TextDecorationType.LineThrough : TextDecorationType.None })
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.remainLabel(item))
          .fontSize(14)
          .fontColor(this.isUrgent(item) ? Constants.COLOR_PRIMARY
            : (item.plan.completed ? Constants.COLOR_TEXT_TERTIARY : Constants.COLOR_TEXT_SECONDARY))
          .margin({ left: 10 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Text(`${item.plan.startDate} → ${DateCalcUtils.toChineseDate(item.progress.targetDate)} · 共 ${item.plan.plannedDays} 天`)
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 8 })

      Row() {
        Row()
          .width(item.plan.completed ? '100%' : `${item.progress.percent}%`)
          .height(6)
          .borderRadius(3)
          .backgroundColor(item.plan.completed ? Constants.COLOR_TEXT_TERTIARY : Constants.COLOR_PRIMARY)
      }
      .width('100%')
      .height(6)
      .borderRadius(3)
      .backgroundColor(Constants.COLOR_TRACK)
      .margin({ top: 10 })

      Row() {
        Text(`已过 ${item.progress.elapsedDays} / ${item.plan.plannedDays} 天`)
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
        Blank()
        Button(item.plan.completed ? '恢复' : '标记完成')
          .height(32)
          .fontSize(15)
          .fontColor(Constants.COLOR_PRIMARY)
          .backgroundColor(Constants.COLOR_BACKGROUND)
          .onClick(() => {
            this.toggleCompleted(item);
          })
        Button('删除')
          .height(32)
          .fontSize(15)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
          .backgroundColor(Constants.COLOR_BACKGROUND)
          .margin({ left: 8 })
          .onClick(() => {
            this.confirmDelete(item);
          })
      }
      .width('100%')
      .margin({ top: 10 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(16)
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
            Text('加载中…')
              .fontSize(15)
              .fontColor(Constants.COLOR_TEXT_TERTIARY)
              .margin({ top: 40 })
          } else {
            if (this.plans.length < MAX_TASK_PLANS) {
              this.buildAddCard()
            } else {
              this.buildFullHint()
            }

            if (this.items.length === 0) {
              this.buildEmpty()
            } else {
              ForEach(this.items, (item: TaskItem) => {
                this.buildTaskCard(item)
              }, (item: TaskItem) => item.plan.id)
            }
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 32 })
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
