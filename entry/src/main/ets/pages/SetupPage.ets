import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../common/constants/Constants';
import { DateUtils } from '../common/utils/DateUtils';
import { SessionManager } from '../services/storage/SessionManager';
import { Icon, IconKind } from '../components/Icons';

/**
 * 首启初始化页：设置昵称与开始记录日期。
 * 纯本机设置，不需要账号，也不涉及任何网络请求。
 */
@Entry
@Component
struct SetupPage {
  @State private startDate: string = DateUtils.today();
  @State private nickname: string = '';
  @State private isLoading: boolean = false;

  aboutToAppear(): void {
    this.redirectIfReady();
  }

  private async redirectIfReady(): Promise<void> {
    const ready: boolean = await SessionManager.getInstance().isInitialized();
    if (ready) {
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/HomePage' });
    }
  }

  private openDatePicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2000-1-1'),
      end: new Date(),
      selected: DateUtils.parseDate(this.startDate),
      onDateAccept: (value: Date) => {
        this.startDate = DateUtils.formatDate(value);
      }
    });
  }

  private async handleStart(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    try {
      const session = SessionManager.getInstance();
      const name: string = this.nickname.trim();
      await session.setNickname(name !== '' ? name : '我');
      await session.setStartDate(this.startDate);
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/HomePage' });
    } catch (err) {
      this.isLoading = false;
      hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, '初始化失败: %{public}s', JSON.stringify(err));
      this.getUIContext().getPromptAction().showToast({ message: '设置失败，请重试', duration: 2000 });
    }
  }

  @Builder
  private buildHeader() {
    Column() {
      Icon({ kind: IconKind.NOTE, iconSize: 62, color: Constants.COLOR_PRIMARY })
      Text('心情手记')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .margin({ top: 8 })
      Text('每天记下心情，和今天发生的事')
        .fontSize(15)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .margin({ top: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildNameRow() {
    Column() {
      Text('你的称呼')
        .fontSize(17)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%')
      TextInput({ placeholder: '可留空，默认显示为「我」', text: this.nickname })
        .width('100%')
        .height(44)
        .fontSize(17)
        .maxLength(12)
        .backgroundColor(Constants.COLOR_BACKGROUND)
        .margin({ top: 10 })
        .onChange((value: string) => {
          this.nickname = value;
        })
    }
    .width('100%')
    .padding({ top: 4, bottom: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildDateRow() {
    Row() {
      Text('开始记录日期')
        .fontSize(17)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
      Blank()
      Text(this.startDate)
        .fontSize(17)
        .fontColor(Constants.COLOR_PRIMARY)
        .onClick(() => {
          this.openDatePicker();
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .border({ width: { top: 1 }, color: Constants.COLOR_DIVIDER })
  }

  build() {
    Column() {
      this.buildHeader()
      Column() {
        this.buildNameRow()
        this.buildDateRow()
      }
      .width('100%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor(Constants.COLOR_CARD)
      .margin({ top: 28 })

      Button('开始记录')
        .width('100%')
        .height(48)
        .fontSize(18)
        .backgroundColor(Constants.COLOR_PRIMARY)
        .fontColor(Constants.COLOR_ON_BRAND)
        .margin({ top: 24 })
        .enabled(!this.isLoading)
        .onClick(() => {
          this.handleStart();
        })

      Text('所有记录只保存在这台手机上，不会上传')
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .margin({ top: 16 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 80 })
    .backgroundColor(Constants.COLOR_BACKGROUND)
    .alignItems(HorizontalAlign.Start)
  }
}
