import { DateUtils } from '../common/utils/DateUtils';
import { Constants } from '../common/constants/Constants';
import { CalendarMark } from '../models/Calendar';
import { moodColorsByLabel } from '../models/DailyLog';

interface CalendarCell {
  day: number;
  date: string;
  isToday: boolean;
  /** 有记录 */
  checked: boolean;
  /** 当天心情标签，无记录为空串 */
  mood: string;
  hasPhoto: boolean;
  /** 这一天有没有"要做的事"的安排 */
  hasPlan: boolean;
  /** 过去且无记录 —— 不可补记 */
  sealed: boolean;
}

/**
 * 月度记录日历。
 *
 * 格子的颜色 = 当天心情色（不再是有记录就统一主题色），有照片的日期在圆下方有一个小圆点，
 * 过去没记录的日子是浅灰（暗示不可补记），今天有描边。
 *
 * 传入 onPickDate 后格子可点击（有记录进详情、无记录进记录页由调用方决定）。
 */
@Component
export struct CalendarHeatmap {
  @Prop year: number = 2024;
  @Prop month: number = 1;
  @Prop marks: CalendarMark[] = [];
  @Prop today: string = '';
  onPickDate?: (date: string) => void;

  private getCells(): CalendarCell[] {
    const cells: CalendarCell[] = [];
    const firstWeekday: number = new Date(this.year, this.month - 1, 1).getDay();
    const totalDays: number = DateUtils.daysInMonth(this.year, this.month);

    // 按日期索引，不依赖 marks 的下标顺序，避免错位
    const byDate: Map<string, CalendarMark> = new Map();
    for (const mark of this.marks) {
      byDate.set(mark.date, mark);
    }

    for (let i: number = 0; i < firstWeekday; i++) {
      cells.push({
        day: 0, date: '', isToday: false, checked: false, mood: '', hasPhoto: false, hasPlan: false, sealed: false
      });
    }
    for (let d: number = 1; d <= totalDays; d++) {
      const date: string = DateUtils.buildDateStr(this.year, this.month, d);
      const mark: CalendarMark | undefined = byDate.get(date);
      const mood: string = mark === undefined ? '' : mark.mood;
      cells.push({
        day: d,
        date: date,
        isToday: date === this.today,
        checked: mood !== '',
        mood: mood,
        hasPhoto: mark === undefined ? false : mark.hasPhoto,
        hasPlan: mark === undefined ? false : mark.hasPlan,
        sealed: mark === undefined ? false : mark.sealed
      });
    }
    return cells;
  }

  /** 格子底色：有记录用当天心情色；过去空白用浅灰；其余透明 */
  private fillOf(cell: CalendarCell): ResourceColor {
    if (cell.checked) {
      return moodColorsByLabel(cell.mood)[1];
    }
    return cell.sealed ? Constants.COLOR_TRACK : Constants.COLOR_TRANSPARENT;
  }

  private textColorOf(cell: CalendarCell): ResourceColor {
    if (cell.checked) {
      return Constants.COLOR_TEXT_PRIMARY;
    }
    return cell.sealed ? Constants.COLOR_TEXT_TERTIARY : Constants.COLOR_TEXT_PRIMARY;
  }

  @Builder
  private buildWeekHeader() {
    Row() {
      ForEach(['日', '一', '二', '三', '四', '五', '六'], (label: string) => {
        Text(label)
          .fontSize(17)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .width('14.28%')
          .textAlign(TextAlign.Center)
      }, (label: string) => label)
    }
    .width('100%')
    .padding({ bottom: 10 })
  }

  @Builder
  private buildCell(cell: CalendarCell) {
    Stack() {
      if (cell.day > 0) {
        Stack({ alignContent: Alignment.TopEnd }) {
          Column() {
            Text(`${cell.day}`)
              .fontSize(19)
              .fontColor(this.textColorOf(cell))
            // 有照片的日期标一个实心小点
            if (cell.hasPhoto) {
              Row()
                .width(4)
                .height(4)
                .borderRadius(2)
                .margin({ top: 2 })
                .backgroundColor(cell.checked ? Constants.COLOR_ON_BRAND : Constants.COLOR_PRIMARY)
            }
          }
          .width(42)
          .height(42)
          .justifyContent(FlexAlign.Center)
          .borderRadius(21)
          .backgroundColor(this.fillOf(cell))
          .border({
            width: cell.isToday ? 1.5 : (cell.checked ? 1 : 0),
            color: Constants.COLOR_PRIMARY
          })

          // 那天有安排：右上角一个空心小圈（与"有照片"的实心点区分）
          if (cell.hasPlan) {
            Row()
              .width(7)
              .height(7)
              .borderRadius(3.5)
              .backgroundColor(Constants.COLOR_TRANSPARENT)
              .border({ width: 1.5, color: Constants.COLOR_PRIMARY })
              .margin({ top: 1, right: 1 })
          }
        }
        .width(42)
        .height(42)
      }
    }
    .width('100%')
    .height(50)
    .alignContent(Alignment.Center)
    .onClick(() => {
      if (cell.day > 0 && this.onPickDate) {
        this.onPickDate(cell.date);
      }
    })
  }

  build() {
    Column() {
      this.buildWeekHeader()
      Grid() {
        ForEach(this.getCells(), (cell: CalendarCell, index: number) => {
          GridItem() {
            this.buildCell(cell)
          }
        }, (cell: CalendarCell, index: number) => `${index}-${cell.date}`)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .rowsGap(4)
      .width('100%')
    }
  }
}
