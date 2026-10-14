import { Constants } from '../common/constants/Constants';
import { DateUtils } from '../common/utils/DateUtils';
import { IdUtils } from '../common/utils/IdUtils';
import { Anniversary, AnniversaryType, getAnniversaryTypeLabel } from '../models/Anniversary';
import { RepositoryFactory } from '../services/data/RepositoryFactory';
import { ReminderService } from '../services/ReminderService';
import { EmptyState } from '../components/EmptyState';
import { Icon, IconKind } from '../components/Icons';

interface AnniversaryTypeOption {
  type: string;
  label: string;
}

const TYPE_OPTIONS: AnniversaryTypeOption[] = [
  { type: AnniversaryType.ANNIVERSARY, label: '重要日子' },
  { type: AnniversaryType.BIRTHDAY, label: '生日' },
  { type: AnniversaryType.FESTIVAL, label: '节日' }
];

/**
 * 重要日子管理页
 */
@Entry
@Component
struct AnniversaryPage {
  @State private anniversaries: Anniversary[] = [];
  @State private showAddPanel: boolean = false;
  @State private newTitle: string = '';
  @State private newDate: string = DateUtils.today();
  @State private newType: string = AnniversaryType.ANNIVERSARY;
  @State private isLoading: boolean = false;
  @State private today: string = DateUtils.today();

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      this.anniversaries = await RepositoryFactory.getRepository().getImportantDays();
      this.today = DateUtils.today();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '加载失败', duration: 2000 });
    }
  }

  private typeIcon(type: string): string {
    if (type === AnniversaryType.BIRTHDAY) {
      return IconKind.STAR;
    }
    if (type === AnniversaryType.FESTIVAL) {
      return IconKind.GIFT;
    }
    return IconKind.NOTE;
  }

  private openNewDatePicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2000-1-1'),
      end: new Date('2100-12-31'),
      selected: DateUtils.parseDate(this.newDate),
      onDateAccept: (value: Date) => {
        this.newDate = DateUtils.formatDate(value);
      }
    });
  }

  private async handleSave(): Promise<void> {
    if (this.newTitle.trim() === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请输入名称', duration: 2000 });
      return;
    }
    this.isLoading = true;
    try {
      const anniversary: Anniversary = {
        id: IdUtils.generate('important'),
        title: this.newTitle.trim(),
        type: this.newType,
        date: this.newDate,
        reminderEnabled: true,
        createdAt: Date.now()
      };
      await RepositoryFactory.getRepository().upsertImportantDay(anniversary);
      await ReminderService.publishAnniversaryReminder(anniversary.title, anniversary.date);
      this.newTitle = '';
      this.newType = AnniversaryType.ANNIVERSARY;
      this.showAddPanel = false;
      await this.load();
      this.getUIContext().getPromptAction().showToast({ message: '已添加', duration: 1500 });
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败', duration: 2000 });
    } finally {
      this.isLoading = false;
    }
  }

  private handleDelete(item: Anniversary): void {
    this.getUIContext().showAlertDialog({
      title: '删除重要日子',
      message: `确定删除「${item.title}」吗？`,
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

  private async doDelete(item: Anniversary): Promise<void> {
    await RepositoryFactory.getRepository().deleteImportantDay(item.id);
    await this.load();
    this.getUIContext().getPromptAction().showToast({ message: '已删除', duration: 1500 });
  }

  private async handleToggleReminder(item: Anniversary, isOn: boolean): Promise<void> {
    item.reminderEnabled = isOn;
    await RepositoryFactory.getRepository().upsertImportantDay(item);
    if (isOn) {
      await ReminderService.publishAnniversaryReminder(item.title, item.date);
    }
  }

  @Builder
  private buildTypeSelector() {
    Row() {
      ForEach(TYPE_OPTIONS, (option: AnniversaryTypeOption) => {
        Button(option.label)
          .layoutWeight(1)
          .height(38)
          .fontSize(16)
          .backgroundColor(this.newType === option.type ? Constants.COLOR_PRIMARY : Constants.COLOR_BACKGROUND)
          .fontColor(this.newType === option.type ? Constants.COLOR_ON_BRAND : Constants.COLOR_TEXT_SECONDARY)
          .onClick(() => {
            this.newType = option.type;
          })
      }, (option: AnniversaryTypeOption) => option.type)
    }
    .width('100%')
    .margin({ top: 12 })
  }

  @Builder
  private buildAddPanel() {
    Column() {
      Text('添加重要日子')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
      TextInput({ placeholder: '名称，如：第一次旅行', text: this.newTitle })
        .width('100%')
        .height(44)
        .fontSize(17)
        .margin({ top: 14 })
        .onChange((value: string) => {
          this.newTitle = value;
        })
      Row() {
        Text('日期')
          .fontSize(17)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
        Blank()
        Text(this.newDate)
          .fontSize(17)
          .fontColor(Constants.COLOR_PRIMARY)
          .onClick(() => {
            this.openNewDatePicker();
          })
      }
      .width('100%')
      .margin({ top: 14 })

      this.buildTypeSelector()

      Row() {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontSize(17)
          .backgroundColor(Constants.COLOR_BACKGROUND)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
          .onClick(() => {
            this.showAddPanel = false;
          })
        Button('保存')
          .layoutWeight(1)
          .height(42)
          .fontSize(17)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .fontColor(Constants.COLOR_ON_BRAND)
          .enabled(!this.isLoading)
          .margin({ left: 12 })
          .onClick(() => {
            this.handleSave();
          })
      }
      .width('100%')
      .margin({ top: 18 })
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
  }

  @Builder
  private buildItem(item: Anniversary) {
    Row() {
      Icon({ kind: this.typeIcon(item.type), iconSize: 30, color: Constants.COLOR_PRIMARY, strokeW: 1.8 })
      Column() {
        Text(item.title)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
        Text(`${getAnniversaryTypeLabel(item.type)} · ${item.date}`)
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .margin({ top: 3 })
      }
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column() {
        Text(DateUtils.nextAnniversaryDays(item.date, this.today) === 0 ? '就是今天' : `还剩 ${DateUtils.nextAnniversaryDays(item.date, this.today)} 天`)
          .fontSize(14)
          .fontColor(Constants.COLOR_PRIMARY)
        Toggle({ type: ToggleType.Switch, isOn: item.reminderEnabled })
          .width(40)
          .margin({ top: 6 })
          .onChange((isOn: boolean) => {
            this.handleToggleReminder(item, isOn);
          })
      }
      .alignItems(HorizontalAlign.End)
      .margin({ left: 8 })

      Stack() {
        Icon({ kind: IconKind.TRASH, iconSize: 20, color: Constants.COLOR_TEXT_TERTIARY })
      }
      .margin({ left: 12 })
      .onClick(() => {
        this.handleDelete(item);
      })
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .margin({ top: 12 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      Stack() {
        Text('重要日子')
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
          Text(this.showAddPanel ? '收起' : '添加')
            .fontSize(17)
            .fontColor(Constants.COLOR_PRIMARY)
            .onClick(() => {
              this.showAddPanel = !this.showAddPanel;
            })
        }
        .width('100%')
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })

      Scroll() {
        Column() {
          if (this.showAddPanel) {
            this.buildAddPanel()
          }
          if (this.anniversaries.length === 0) {
            EmptyState({
              kind: IconKind.STAR,
              title: '还没有重要日子',
              subtitle: '点击右上角添加第一个重要日子'
            })
          } else {
            ForEach(this.anniversaries, (item: Anniversary) => {
              this.buildItem(item)
            }, (item: Anniversary) => item.id)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 20 })
        .alignItems(HorizontalAlign.Start)
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .backgroundColor(Constants.COLOR_BACKGROUND)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Constants.COLOR_BACKGROUND)
  }
}
