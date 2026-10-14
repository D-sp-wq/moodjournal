import { Constants } from '../common/constants/Constants';
import { Icon, IconKind } from './Icons';

/**
 * 空状态占位组件。kind 取 IconKind 里的常量。
 */
@Component
export struct EmptyState {
  kind: string = IconKind.NOTE;
  title: string = '暂无数据';
  subtitle: string = '';

  build() {
    Column() {
      Icon({
        kind: this.kind,
        iconSize: 56,
        color: Constants.COLOR_TEXT_TERTIARY,
        strokeW: 1.6
      })
      Text(this.title)
        .fontSize(18)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .margin({ top: 12 })
      if (this.subtitle !== '') {
        Text(this.subtitle)
          .fontSize(15)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .margin({ top: 6 })
      }
    }
    .width('100%')
    .padding({ top: 60, bottom: 60 })
    .alignItems(HorizontalAlign.Center)
  }
}
