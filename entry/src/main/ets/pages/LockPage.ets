import { Constants } from '../common/constants/Constants';
import { common } from '@kit.AbilityKit';
import {
  ATTEMPTS_BEFORE_HINT,
  PIN_LENGTH,
  attemptHintText
} from '../models/AppLock';
import { AppLockManager } from '../services/storage/AppLockManager';
import { Icon, IconKind } from '../components/Icons';

/**
 * 解锁页。
 *
 * 设计要点：
 * - 自定义数字键盘（不用系统弹窗），样式与应用一致
 * - 返回键不能绕过：onBackPress 直接消费掉，只能退出应用
 * - 忘记密码不提供应用内绕过，只引导去系统设置清除数据
 *   （否则"忘记密码"就成了任何人都能进的后门）
 */
@Entry
@Component
struct LockPage {
  @State private input: string = '';
  @State private failCount: number = 0;
  @State private shake: number = 0;
  @State private hint: string = '';

  private manager: AppLockManager = AppLockManager.getInstance();

  /** 返回键拦截：锁屏页不允许后退 */
  onBackPress(): boolean {
    this.getUIContext().getPromptAction().showToast({
      message: '请先输入密码解锁',
      duration: 1500
    });
    return true;
  }

  private push(digit: string): void {
    if (this.input.length >= PIN_LENGTH) {
      return;
    }
    this.input = `${this.input}${digit}`;
    this.hint = '';
    if (this.input.length === PIN_LENGTH) {
      this.submit();
    }
  }

  private backspace(): void {
    if (this.input.length === 0) {
      return;
    }
    this.input = this.input.slice(0, this.input.length - 1);
    this.hint = '';
  }

  private submit(): void {
    const pin: string = this.input;
    if (this.manager.verify(pin)) {
      this.manager.clearPending();
      this.failCount = 0;
      this.input = '';
      this.getUIContext().getRouter().back();
      return;
    }
    this.failCount += 1;
    this.input = '';
    this.hint = attemptHintText(this.failCount);
    // 抖动一次（换值触发动画）
    this.shake = this.shake === 0 ? 1 : 0;
    this.getUIContext().getPromptAction().showToast({ message: '密码错误', duration: 1200 });
  }

  private showForgot(): void {
    this.getUIContext().showAlertDialog({
      title: '忘记密码',
      message: '为保护你的日记，密码无法找回，应用内也不提供绕过方式。\n\n'
        + '如果确实需要重新开始，请到「系统设置 → 应用 → 心情手记 → 存储 → 清除数据」，'
        + '清除后所有记录都会被删除且无法恢复。',
      primaryButton: {
        value: '我知道了',
        action: () => {
        }
      },
      secondaryButton: {
        value: '打开系统设置',
        fontColor: Constants.COLOR_PRIMARY,
        action: () => {
          this.openSystemSettings();
        }
      }
    });
  }

  private openSystemSettings(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (context === undefined) {
        return;
      }
      context.startAbility({
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'application_info_entry'
      });
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({
        message: '请手动到系统设置里清除应用数据',
        duration: 2500
      });
    }
  }

  @Builder
  private buildDots() {
    Row() {
      ForEach([0, 1, 2, 3], (index: number) => {
        Row()
          .width(14)
          .height(14)
          .borderRadius(7)
          .backgroundColor(index < this.input.length ? Constants.COLOR_PRIMARY : Constants.COLOR_TRANSPARENT)
          .border({
            width: index < this.input.length ? 0 : 1.5,
            color: Constants.COLOR_TEXT_TERTIARY
          })
          .margin({ left: 8, right: 8 })
      }, (index: number) => `${index}`)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .margin({ top: 28 })
  }

  @Builder
  private buildKey(label: string) {
    Stack() {
      if (label === 'del') {
        Icon({ kind: IconKind.DELETE, iconSize: 26, color: Constants.COLOR_TEXT_PRIMARY })
      } else {
        Text(label)
          .fontSize(26)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
      }
    }
    .width(72)
    .height(72)
    .borderRadius(36)
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
  private buildKeypad() {
    Column() {
      Row() {
        this.buildKey('1')
        this.buildKey('2')
        this.buildKey('3')
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .margin({ top: 14 })

      Row() {
        this.buildKey('4')
        this.buildKey('5')
        this.buildKey('6')
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .margin({ top: 14 })

      Row() {
        this.buildKey('7')
        this.buildKey('8')
        this.buildKey('9')
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .margin({ top: 14 })

      Row() {
        Row().width(72).height(72)
        this.buildKey('0')
        this.buildKey('del')
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
      .margin({ top: 14 })
    }
    .width('100%')
  }

  build() {
    Column() {
      Column() {
        Icon({ kind: IconKind.LOCK, iconSize: 44, color: Constants.COLOR_PRIMARY })
        Text('输入密码解锁')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
          .margin({ top: 14 })
        Text('心情手记')
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .margin({ top: 6 })

        this.buildDots()

        Text(this.hint === '' ? ' ' : this.hint)
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .margin({ top: 14 })
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .padding({ left: 32, right: 32 })

      this.buildKeypad()

      if (this.failCount >= ATTEMPTS_BEFORE_HINT) {
        Text('忘记密码？')
          .fontSize(15)
          .fontColor(Constants.COLOR_PRIMARY)
          .padding(10)
          .margin({ top: 6, bottom: 24 })
          .onClick(() => {
            this.showForgot();
          })
      } else {
        Row().height(24)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, bottom: 12 })
    .backgroundColor(Constants.COLOR_BACKGROUND)
  }
}
