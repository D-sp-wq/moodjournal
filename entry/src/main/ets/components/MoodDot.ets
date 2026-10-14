import { Constants } from '../common/constants/Constants';
import { Mood, getMoodOption } from '../models/DailyLog';

/** 选中时外圈柔光的直径增量 */
const HALO_EXTRA: number = 12;

/**
 * 心情色点：用一个渐变色圆表达心情，替代 emoji（emoji 在不同设备上渲染不一致）。
 * 首页、记录页、时间轴、统计页统一使用它。
 *
 * 选中时外圈加一层半透明柔光 + 更实的描边，让点击有明确反馈；
 * 未选中时组件尺寸就等于 dotSize，不占多余空间。
 * 注意：属性名不能叫 size —— 会与 ArkUI 组件基类的内置属性冲突。
 */
@Component
export struct MoodDot {
  @Prop mood: Mood = Mood.HAPPY;
  @Prop dotSize: number = 44;
  @Prop selected: boolean = false;

  build() {
    Stack() {
      if (this.selected) {
        Row()
          .width(this.dotSize + HALO_EXTRA)
          .height(this.dotSize + HALO_EXTRA)
          .borderRadius((this.dotSize + HALO_EXTRA) / 2)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .opacity(0.18)
      }
      Row()
        .width(this.dotSize)
        .height(this.dotSize)
        .borderRadius(this.dotSize / 2)
        .linearGradient({
          angle: 135,
          colors: [
            [getMoodOption(this.mood).colorStart, 0.0],
            [getMoodOption(this.mood).colorEnd, 1.0]
          ]
        })
        .border({
          width: this.selected ? 2 : 1,
          color: this.selected ? Constants.COLOR_PRIMARY : Constants.COLOR_TRANSPARENT
        })
        // 选中时轻微放大，让点击有即时反馈（animation 只作用于它上面声明的属性）
        .scale({
          x: this.selected ? 1 : 0.92,
          y: this.selected ? 1 : 0.92
        })
        .animation({ duration: 180, curve: Curve.EaseOut })
        .shadow({
          radius: this.selected ? 8 : 0,
          color: Constants.COLOR_SHADOW,
          offsetY: this.selected ? 3 : 0
        })
    }
    .width(this.selected ? this.dotSize + HALO_EXTRA : this.dotSize)
    .height(this.selected ? this.dotSize + HALO_EXTRA : this.dotSize)
  }
}
