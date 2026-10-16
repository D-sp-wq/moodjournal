import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../common/constants/Constants';
import { PrivacySection, PrivacyText } from '../common/constants/PrivacyText';
import { DatabaseHelper } from '../services/storage/DatabaseHelper';
import { SessionManager } from '../services/storage/SessionManager';
import { AppLockManager } from '../services/storage/AppLockManager';
import { Icon, IconKind } from '../components/Icons';

/**
 * 启动页：初始化数据库与会话，先处理隐私政策同意，再按是否完成初始设置分流
 */
@Entry
@Component
struct Index {
  @State private showPrivacy: boolean = false;
  /** 初始化失败：显示可重试的错误页，而不是把用户丢在一个不存在的页面上 */
  @State private initFailed: boolean = false;

  aboutToAppear(): void {
    this.bootstrap();
  }

  private async bootstrap(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '获取上下文失败');
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/SetupPage' });
        return;
      }
      await DatabaseHelper.getInstance().init(context);
      await SessionManager.getInstance().init(context);
      // 读出应用锁配置；冷启动是否需要验证由 AppLockManager 判定，首页呈现锁屏
      await AppLockManager.getInstance().load();

      const agreed: boolean = await SessionManager.getInstance().isPrivacyAgreed();
      if (!agreed) {
        // 首启：先展示隐私政策，同意后再分流
        this.showPrivacy = true;
        return;
      }
      await this.routeByBindingState();
    } catch (err) {
      // 这里原本跳的是 pages/BindPage —— 那是「情侣绑定」时期的页面，页面早已删除、
      // 也没在 main_pages.json 注册，跳转会**静默失败**：用户永远停在启动页，
      // 连"为什么打不开"都看不到。改为就地显示带「重试」的错误页。
      hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, '初始化失败: %{public}s', JSON.stringify(err));
      this.initFailed = true;
    }
  }

  private async routeByBindingState(): Promise<void> {
    const ready: boolean = await SessionManager.getInstance().isInitialized();
    if (ready) {
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/HomePage' });
    } else {
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/SetupPage' });
    }
  }

  private async handleAgree(): Promise<void> {
    await SessionManager.getInstance().setPrivacyAgreed(true);
    this.showPrivacy = false;
    await this.routeByBindingState();
  }

  private handleDecline(): void {
    const context = this.getUIContext().getHostContext();
    try {
      if (context !== undefined) {
        (context as common.UIAbilityContext).terminateSelf();
        return;
      }
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '退出应用失败: %{public}s', JSON.stringify(err));
    }
    this.getUIContext().getPromptAction().showToast({
      message: '需要同意隐私政策后才能使用心情手记',
      duration: 2500
    });
  }

  @Builder
  private buildSplash() {
    Column() {
      Icon({ kind: IconKind.NOTE, iconSize: 72, color: Constants.COLOR_PRIMARY })
      Text('心情手记')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_PRIMARY)
        .margin({ top: 12 })
      Text('每天记下心情，和今天发生的事')
        .fontSize(16)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Constants.COLOR_BACKGROUND)
  }

  @Builder
  private buildPrivacyView() {
    Column() {
      Text(PrivacyText.TITLE)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
      Text(`版本 ${PrivacyText.VERSION} · 生效日期 ${PrivacyText.EFFECTIVE_DATE}`)
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .margin({ top: 6 })
      Text(PrivacyText.SUMMARY)
        .fontSize(15)
        .fontColor(Constants.COLOR_PRIMARY)
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor(Constants.COLOR_CARD)
        .margin({ top: 12 })

      Scroll() {
        Column() {
          ForEach(PrivacyText.SECTIONS, (section: PrivacySection) => {
            Text(section.heading)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Constants.COLOR_TEXT_PRIMARY)
              .width('100%')
              .margin({ top: 14 })
            Text(section.body)
              .fontSize(14)
              .fontColor(Constants.COLOR_TEXT_SECONDARY)
              .width('100%')
              .margin({ top: 6 })
          }, (section: PrivacySection) => section.heading)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 8 })
      .scrollBar(BarState.Off)

      Row() {
        Button('不同意')
          .layoutWeight(1)
          .height(44)
          .fontSize(17)
          .backgroundColor(Constants.COLOR_CARD)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
          .onClick(() => {
            this.handleDecline();
          })
        Button('同意并继续')
          .layoutWeight(1)
          .height(44)
          .fontSize(17)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .fontColor(Constants.COLOR_ON_BRAND)
          .margin({ left: 12 })
          .onClick(() => {
            this.handleAgree();
          })
      }
      .width('100%')
      .margin({ top: 14 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 56, bottom: 20 })
    .backgroundColor(Constants.COLOR_BACKGROUND)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildInitErrorView() {
    Column() {
      Icon({ kind: IconKind.CLOSE, iconSize: 56, color: Constants.COLOR_TEXT_TERTIARY })
      Text('初始化失败')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .margin({ top: 12 })
      Text('可能是存储空间不足，或本机数据文件损坏。可以先点「重试」；'
        + '如果一直失败，建议卸载后重新安装应用。')
        .fontSize(14)
        .lineHeight(22)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .margin({ top: 8 })
      Button('重试')
        .width('100%')
        .height(44)
        .fontSize(17)
        .backgroundColor(Constants.COLOR_PRIMARY)
        .fontColor(Constants.COLOR_ON_BRAND)
        .margin({ top: 20 })
        .onClick(() => {
          this.initFailed = false;
          this.bootstrap();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(Constants.COLOR_BACKGROUND)
  }

  build() {
    if (this.initFailed) {
      this.buildInitErrorView()
    } else if (this.showPrivacy) {
      this.buildPrivacyView()
    } else {
      this.buildSplash()
    }
  }
}