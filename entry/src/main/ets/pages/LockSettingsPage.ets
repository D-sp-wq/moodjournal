import { Constants } from '../common/constants/Constants';
import {
  DEFAULT_GRACE_MINUTES,
  GRACE_OPTIONS,
  PIN_LENGTH,
  graceLabel,
  isValidPin
} from '../models/AppLock';
import { AppLockManager } from '../services/storage/AppLockManager';
import { Icon, IconKind } from '../components/Icons';

/** 当前正在进行的输入阶段 */
const STEP_NONE: number = 0;
const STEP_SET_NEW: number = 1;
const STEP_CONFIRM: number = 2;
const STEP_VERIFY_OLD: number = 3;

/**
 * 应用锁设置页：开启、修改密码、关闭、选择宽限期。
 *
 * 所有会改变锁状态的操作都要先验证身份（改密码与关闭锁都要求先输旧密码），
 * 避免手机被人拿到后直接把锁关掉。
 */
@Entry
@Component
struct LockSettingsPage {
  @State private on: boolean = false;
  @State private grace: number = DEFAULT_GRACE_MINUTES;
  @State private step: number = STEP_NONE;
  @State private firstPin: string = '';
  @State private input: string = '';
  @State private errorText: string = '';
  @State private loaded: boolean = false;
  /** true 表示当前这次验证通过后要关闭锁，而不是改密码 */
  @State private pendingDisable: boolean = false;

  private manager: AppLockManager = AppLockManager.getInstance();

  aboutToAppear(): void {
    this.on = this.manager.isOn();
    this.grace = this.manager.getGraceMinutes();
    this.loaded = true;
  }

  private beginSetPin(): void {
    this.step = STEP_SET_NEW;
    this.input = '';
    this.firstPin = '';
    this.errorText = '';
  }

  private beginChangePin(): void {
    this.step = STEP_VERIFY_OLD;
    this.input = '';
    this.errorText = '';
  }

  private push(digit: string): void {
    if (this.input.length >= PIN_LENGTH) {
      return;
    }
    this.input = `${this.input}${digit}`;
    this.errorText = '';
    if (this.input.length === PIN_LENGTH) {
      this.advance();
    }
  }

  private backspace(): void {
    if (this.input.length === 0) {
      return;
    }
    this.input = this.input.slice(0, this.input.length - 1);
  }

  private advance(): void {
    const pin: string = this.input;

    if (this.step === STEP_VERIFY_OLD) {
      if (!this.manager.verify(pin)) {
        this.input = '';
        this.errorText = '原密码不正确';
        return;
      }
      if (this.pendingDisable) {
        // 验证通过 → 执行关闭
        this.doDisable();
        return;
      }
      this.input = '';
      this.errorText = '';
      this.step = STEP_SET_NEW;
      this.firstPin = '';
      return;
    }

    if (this.step === STEP_SET_NEW) {
      this.firstPin = pin;
      this.input = '';
      this.step = STEP_CONFIRM;
      return;
    }

    // 确认阶段
    if (pin !== this.firstPin) {
      this.input = '';
      this.errorText = '两次输入不一致，请重新设置';
      this.step = STEP_SET_NEW;
      this.firstPin = '';
      return;
    }
    this.save(pin);
  }

  private async save(pin: string): Promise<void> {
    const ok: boolean = await this.manager.setPin(pin);
    this.input = '';
    this.firstPin = '';
    this.step = STEP_NONE;
    if (ok) {
      this.on = true;
      this.getUIContext().getPromptAction().showToast({ message: '应用锁已开启', duration: 1800 });
    } else {
      this.errorText = '保存失败，请重试';
    }
  }

  private confirmDisable(): void {
    this.getUIContext().showAlertDialog({
      title: '关闭应用锁',
      message: '关闭后打开应用不再需要密码。密码会被一并清除。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '继续',
        fontColor: Constants.COLOR_PRIMARY,
        action: () => {
          this.step = STEP_VERIFY_OLD;
          this.input = '';
          this.errorText = '';
          this.pendingDisable = true;
        }
      }
    });
  }

  private async doDisable(): Promise<void> {
    const ok: boolean = await this.manager.disable();
    this.step = STEP_NONE;
    this.input = '';
    this.pendingDisable = false;
    if (ok) {
      this.on = false;
      this.getUIContext().getPromptAction().showToast({ message: '应用锁已关闭', duration: 1800 });
    } else {
      this.errorText = '操作失败，请重试';
    }
  }

  private promptText(): string {
    if (this.step === STEP_VERIFY_OLD) {
      return this.pendingDisable ? '输入当前密码以关闭' : '先输入当前密码';
    }
    if (this.step === STEP_SET_NEW) {
      return '设置一个新密码';
    }
    return '再输入一次确认';
  }

  @Builder
  private buildHeader() {
    Stack() {
      Text('应用锁')
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

  @Builder
  private buildKey(label: string) {
    Stack() {
      if (label === 'del') {
        Icon({ kind: IconKind.DELETE, iconSize: 24, color: Constants.COLOR_TEXT_PRIMARY })
      } else {
        Text(label)
          .fontSize(24)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
      }
    }
    .width(64)
    .height(64)
    .borderRadius(32)
    .backgroundColor(Constants.COLOR_CARD)
    .stateStyles({
      pressed: {
        .opacity(0.6)
      }
    })
    .onClick(() => {
      if (label === 'del') {
        this.backspace();
      } else {
        this.push(label);
      }
    })
  }

  @Builder
  private buildPinPanel() {
    Column() {
      Text(this.promptText())
        .fontSize(17)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)

      Row() {
        ForEach([0, 1, 2, 3], (index: number) => {
          Row()
            .width(13)
            .height(13)
            .borderRadius(7)
            .backgroundColor(index < this.input.length ? Constants.COLOR_PRIMARY : Constants.COLOR_TRANSPARENT)
            .border({
              width: index < this.input.length ? 0 : 1.5,
              color: Constants.COLOR_TEXT_TERTIARY
            })
            .margin({ left: 7, right: 7 })
        }, (index: number) => `${index}`)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ top: 18 })

      Text(this.errorText)
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .margin({ top: 12 })

      Column() {
        Row() {
          this.buildKey('1')
          this.buildKey('2')
          this.buildKey('3')
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceEvenly)

        Row() {
          this.buildKey('4')
          this.buildKey('5')
          this.buildKey('6')
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceEvenly)
        .margin({ top: 12 })

        Row() {
          this.buildKey('7')
          this.buildKey('8')
          this.buildKey('9')
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceEvenly)
        .margin({ top: 12 })

        Row() {
          Row().width(64).height(64)
          this.buildKey('0')
          this.buildKey('del')
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceEvenly)
        .margin({ top: 12 })
      }
      .width('100%')
      .margin({ top: 18 })

      Text('取消')
        .fontSize(15)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
        .padding(10)
        .margin({ top: 10 })
        .onClick(() => {
          this.step = STEP_NONE;
          this.input = '';
          this.errorText = '';
          this.firstPin = '';
          this.pendingDisable = false;
        })
    }
    .width('100%')
    .padding(20)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .margin({ top: 14 })
  }

  @Builder
  private buildStatusCard() {
    Column() {
      Row() {
        Icon({ kind: IconKind.LOCK, iconSize: 24, color: Constants.COLOR_PRIMARY })
        Column() {
          Text(this.on ? '应用锁已开启' : '应用锁未开启')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
          Text(this.on
            ? '打开应用或切换回来时需要输入密码'
            : '开启后，需要输入密码才能打开应用')
            .fontSize(14)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 10 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (!this.on) {
        Row() {
          Icon({ kind: IconKind.CHECK, iconSize: 20, color: Constants.COLOR_ON_BRAND })
          Text(`设置 ${PIN_LENGTH} 位数字密码`)
            .fontSize(16)
            .fontColor(Constants.COLOR_ON_BRAND)
            .margin({ left: 8 })
        }
        .width('100%')
        .height(48)
        .borderRadius(14)
        .backgroundColor(Constants.COLOR_PRIMARY)
        .justifyContent(FlexAlign.Center)
        .margin({ top: 16 })
        .onClick(() => {
          this.beginSetPin();
        })
      } else {
        Row() {
          Text('修改密码')
            .fontSize(16)
            .fontColor(Constants.COLOR_PRIMARY)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 12, bottom: 12 })
            .onClick(() => {
              this.pendingDisable = false;
              this.beginChangePin();
            })
          Divider()
            .vertical(true)
            .height(20)
            .color(Constants.COLOR_DIVIDER)
          Text('关闭应用锁')
            .fontSize(16)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 12, bottom: 12 })
            .onClick(() => {
              this.confirmDisable();
            })
        }
        .width('100%')
        .margin({ top: 12 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .margin({ top: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildGraceCard() {
    Column() {
      Text('什么时候需要重新输入密码')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%')

      Row() {
        ForEach(GRACE_OPTIONS, (minutes: number) => {
          Text(graceLabel(minutes))
            .fontSize(15)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 9, bottom: 9 })
            .borderRadius(10)
            .backgroundColor(this.grace === minutes ? Constants.COLOR_PRIMARY : Constants.COLOR_BACKGROUND)
            .fontColor(this.grace === minutes ? Constants.COLOR_ON_BRAND : Constants.COLOR_TEXT_SECONDARY)
            .onClick(() => {
              this.setGrace(minutes);
            })
        }, (minutes: number) => `${minutes}`)
      }
      .width('100%')
      .margin({ top: 14 })

      Text(this.grace <= 0
        ? '每次切走再回来都要输密码'
        : `切走不超过 ${graceLabel(this.grace)} 再回来不用输密码；超过就要输`)
        .fontSize(13)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 12 })
    }
    .width('100%')
    .padding(18)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .margin({ top: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  private async setGrace(minutes: number): Promise<void> {
    const ok: boolean = await this.manager.setGraceMinutes(minutes);
    if (ok) {
      this.grace = minutes;
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '设置失败，请重试', duration: 1800 });
    }
  }

  @Builder
  private buildNotice() {
    Text('密码只保存在本机，不会上传。忘记密码无法找回 —— 这是为了不让「忘记密码」变成绕过锁的后门。')
      .fontSize(13)
      .lineHeight(22)
      .fontColor(Constants.COLOR_TEXT_TERTIARY)
      .width('100%')
      .margin({ top: 16 })
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

      Scroll() {
        Column() {
          if (this.loaded) {
            if (this.step === STEP_NONE) {
              this.buildStatusCard()
              this.buildGraceCard()
              this.buildNotice()
            } else {
              this.buildPinPanel()
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
    .backgroundColor(Constants.COLOR_BACKGROUND)
  }
}
