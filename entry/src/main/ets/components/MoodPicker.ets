import { Constants } from '../common/constants/Constants';
import { Mood, MOOD_OPTIONS, MoodOption, normalizeCustomMood } from '../models/DailyLog';
import { MoodDot } from './MoodDot';

/**
 * 心情选择器：4×2 网格。
 *
 * 前 6 格是固定心情，第 7 格是「更多」——让用户自己填写心情。
 * 每项都是「渐变色点 + 中文标签」，不使用 emoji。
 * 输入弹层由页面持有（要挂在页面根节点上，放进 Scroll 会被裁切），
 * 这里只通过 onSelectCustom 请求打开。
 */
@Component
export struct MoodPicker {
  @Prop selected: Mood = Mood.HAPPY;
  /** 用户已填写的自定义心情文字 */
  @Prop customMood: string = '';
  onSelect?: (mood: Mood) => void;
  onSelectCustom?: () => void;

  private handleSelect(mood: Mood): void {
    if (this.onSelect) {
      this.onSelect(mood);
    }
  }

  /** 第 7 格显示的文字：没填过是「更多」，填过就显示填的内容 */
  private customLabel(): string {
    const text: string = normalizeCustomMood(this.customMood);
    if (text === '') {
      return '更多';
    }
    return text.length <= 5 ? text : `${text.slice(0, 5)}…`;
  }

  @Builder
  private buildMoodItem(option: MoodOption) {
    Column() {
      MoodDot({
        mood: option.mood,
        dotSize: this.selected === option.mood ? 52 : 44,
        selected: this.selected === option.mood
      })
      Text(option.label)
        .fontSize(15)
        .fontWeight(this.selected === option.mood ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selected === option.mood ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_SECONDARY)
        .margin({ top: 10 })
    }
    .width('100%')
    .height(92)
    .padding(6)
    .borderRadius(14)
    .backgroundColor(this.selected === option.mood ? Constants.COLOR_SURFACE_SECONDARY : Constants.COLOR_TRANSPARENT)
    .border({
      width: this.selected === option.mood ? 1 : 0,
      color: Constants.COLOR_PRIMARY
    })
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.handleSelect(option.mood);
    })
  }

  @Builder
  private buildCustomItem() {
    Column() {
      if (normalizeCustomMood(this.customMood) !== '') {
        // 已经写过：显示青绿色点
        MoodDot({
          mood: Mood.CUSTOM,
          dotSize: this.selected === Mood.CUSTOM ? 52 : 44,
          selected: this.selected === Mood.CUSTOM
        })
      } else {
        // 还没写过：一个加号圈，暗示"点这里自己写"
        Column() {
          Text('+')
            .fontSize(24)
            .fontColor(Constants.COLOR_TEXT_TERTIARY)
        }
        .width(this.selected === Mood.CUSTOM ? 52 : 44)
        .height(this.selected === Mood.CUSTOM ? 52 : 44)
        .borderRadius(this.selected === Mood.CUSTOM ? 26 : 22)
        .border({
          width: this.selected === Mood.CUSTOM ? 2 : 1,
          color: this.selected === Mood.CUSTOM ? Constants.COLOR_PRIMARY : Constants.COLOR_DIVIDER
        })
        .justifyContent(FlexAlign.Center)
      }

      Text(this.customLabel())
        .fontSize(15)
        .fontWeight(this.selected === Mood.CUSTOM ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selected === Mood.CUSTOM ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_SECONDARY)
        .margin({ top: 10 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(92)
    .padding(6)
    .borderRadius(14)
    .backgroundColor(this.selected === Mood.CUSTOM ? Constants.COLOR_SURFACE_SECONDARY : Constants.COLOR_TRANSPARENT)
    .border({
      width: this.selected === Mood.CUSTOM ? 1 : 0,
      color: Constants.COLOR_PRIMARY
    })
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (this.onSelectCustom) {
        this.onSelectCustom();
      }
    })
  }

  build() {
    Grid() {
      ForEach(MOOD_OPTIONS, (option: MoodOption) => {
        GridItem() {
          this.buildMoodItem(option)
        }
      }, (option: MoodOption) => option.mood.toString())
      GridItem() {
        this.buildCustomItem()
      }
    }
    .columnsTemplate('1fr 1fr 1fr 1fr')
    .rowsGap(8)
    .columnsGap(8)
    .width('100%')
    .height(200)
  }
}
