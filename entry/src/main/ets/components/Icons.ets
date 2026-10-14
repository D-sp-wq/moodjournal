import { Constants } from '../common/constants/Constants';

/**
 * 统一线性图标库 —— 基于 HarmonyOS 系统符号（SymbolGlyph + sys.symbol.*）。
 *
 * 走过的弯路（别再回头走）：
 * 1. 先用 `Shape(){ Path() }` 外层套 `viewPort(24×24)` 缩放 —— 真机上图标渲染成一个个小点。
 * 2. 再改成把路径数据按尺寸换算成 vp 坐标后直接画 `Path` —— 真机上依然是小点。
 *    （换算逻辑保留在 scalePathCommands，并有单元测试，但结论是这条路在真机上不可靠。）
 * 3. 最终改用系统符号库：名字写错**构建就会报错**（不用靠真机猜），
 *    且天然支持 fontColor 换色，与系统观感一致。
 *
 * 符号名来自 SDK 的系统资源索引（previewer/common/resources/entry/resources.txt）。
 * 颜色由调用方传入（取自 Constants 的颜色资源），资源限定符会自动适配日间/夜间。
 */
export class IconKind {
  static readonly HOME: string = 'home';
  static readonly CALENDAR: string = 'calendar';
  static readonly TIMELINE: string = 'timeline';
  static readonly MINE: string = 'mine';
  static readonly GIFT: string = 'gift';
  static readonly PHOTO: string = 'photo';
  static readonly SEARCH: string = 'search';
  static readonly WALLET: string = 'wallet';
  static readonly TARGET: string = 'target';
  static readonly CHART: string = 'chart';
  static readonly CHECK: string = 'check';
  static readonly THEME: string = 'theme';
  static readonly NOTE: string = 'note';
  static readonly STAR: string = 'star';
  static readonly CHEVRON: string = 'chevron';
  static readonly BACK: string = 'back';
  static readonly CLOSE: string = 'close';
  static readonly TRASH: string = 'trash';
  static readonly PLUS: string = 'plus';
  static readonly LOCK: string = 'lock';
  static readonly DELETE: string = 'delete';
}

/** 路径方案的设计坐标系边长（保留历史实现，见 scalePathCommands） */
export const ICON_BASE: number = 24;

const HOME: string = 'M3 11 L12 3 L21 11 V21 H14 V15 H10 V21 H3 Z';
const CALENDAR: string = 'M4 6 H20 V20 H4 Z M4 10 H20 M8 3 V7 M16 3 V7';
const TIMELINE: string = 'M6 4 V20 M6 9 H18 M6 15 H14';
const MINE: string = 'M4 20 C4 16.2 7.6 14 12 14 C16.4 14 20 16.2 20 20 '
  + 'M12 4 A4 4 0 1 0 12 12 A4 4 0 1 0 12 4';
const GIFT: string = 'M4 10 H20 V21 H4 Z M3 7 H21 V10 H3 Z M12 7 V21 '
  + 'M12 7 C10 3 6 4.5 7 7 M12 7 C14 3 18 4.5 17 7';
const PHOTO: string = 'M4 5 H20 V19 H4 Z M4 15.5 L9 10.5 L13 14.5 L16 11.5 L20 15.5 '
  + 'M9.2 8.2 A0.2 0.2 0 1 0 9.2 8.6 A0.2 0.2 0 1 0 9.2 8.2';
const SEARCH: string = 'M10 4 A6 6 0 1 0 10 16 A6 6 0 1 0 10 4 M14.4 14.4 L20 20';
const WALLET: string = 'M4 8 H18 A2 2 0 0 1 20 10 V18 A2 2 0 0 1 18 20 H4 Z '
  + 'M4 8 A2 2 0 0 1 6 6 H16 M15 13.5 H17.5';
const TARGET: string = 'M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 '
  + 'M12 7.5 A4.5 4.5 0 1 0 12 16.5 A4.5 4.5 0 1 0 12 7.5 '
  + 'M12 11.4 A0.6 0.6 0 1 0 12 12.6 A0.6 0.6 0 1 0 12 11.4';
const CHART: string = 'M4 4 V20 H20 M8 20 V13 M12.5 20 V9 M17 20 V16';
const CHECK: string = 'M5 12.5 L10 17.5 L19 7';
const THEME: string = 'M20.2 14.4 A8.2 8.2 0 1 1 9.6 3.8 A6.6 6.6 0 0 0 20.2 14.4 Z';
const NOTE: string = 'M5 4 H14.5 L19 8.5 V20 H5 Z M14.5 4 V8.5 H19 M8.5 12.5 H15.5 M8.5 16.5 H13';
const STAR: string = 'M12 3.2 L14.6 9.2 L21 9.8 L16.1 14.1 L17.6 20.4 L12 17 L6.4 20.4 '
  + 'L7.9 14.1 L3 9.8 L9.4 9.2 Z';
const CHEVRON: string = 'M9.5 5 L16.5 12 L9.5 19';
const BACK: string = 'M14.5 5 L7.5 12 L14.5 19';
const CLOSE: string = 'M6 6 L18 18 M18 6 L6 18';
const TRASH: string = 'M5 7 H19 M10 7 V4.8 H14 V7 M7 7 V20 H17 V7 M10 11 V16.5 M14 11 V16.5';
const PLUS: string = 'M12 5.5 V18.5 M5.5 12 H18.5';
const LOCK_PATH: string = 'M6 10.5 H18 V20.5 H6 Z M8.5 10.5 V7.5 A3.5 3.5 0 0 1 15.5 7.5 V10.5';
const DELETE_PATH: string = 'M9 5 H20 V19 H9 L3 12 Z M12 9.5 L17 14.5 M17 9.5 L12 14.5';

/** 各命令里「需要跟着缩放」的数字个数；A 的旋转角与两个标志位不缩放 */
function scalesOf(cmd: string, count: number): boolean[] {
  const flags: boolean[] = [];
  if (cmd === 'A' || cmd === 'a') {
    // 顺序是 rx ry rot largeArc sweep x y
    const pattern: boolean[] = [true, true, false, false, false, true, true];
    for (let i: number = 0; i < count; i++) {
      flags.push(pattern[i % 7]);
    }
    return flags;
  }
  for (let i: number = 0; i < count; i++) {
    flags.push(true);
  }
  return flags;
}

const NUM_RE: RegExp = /-?\d+(?:\.\d+)?/g;
const SEG_RE: RegExp = /([MmLlHhVvCcSsQqTtAaZz])([^MmLlHhVvCcSsQqTtAaZz]*)/g;

/**
 * 把 24×24 设计坐标下的路径数据按 factor 缩放到实际 vp 坐标。
 *
 * ⚠️ 历史实现：这条路线在真机上渲染成小点，已不再使用（现用系统符号库）。
 * 函数与单元测试保留，是为了留下「弧线标志位不能跟着缩放」这个结论与验证手段。
 */
export function scalePathCommands(cmds: string, factor: number): string {
  let out: string = '';
  let match: RegExpExecArray | null = SEG_RE.exec(cmds);
  while (match !== null) {
    const cmd: string = match[1];
    const numbers: string[] = match[2].match(NUM_RE) ?? [];
    const scaleFlags: boolean[] = scalesOf(cmd, numbers.length);
    out += out === '' ? cmd : ` ${cmd}`;
    for (let i: number = 0; i < numbers.length; i++) {
      const raw: number = Number(numbers[i]);
      const value: number = scaleFlags[i] ? raw * factor : raw;
      out += ` ${Math.round(value * 1000) / 1000}`;
    }
    match = SEG_RE.exec(cmds);
  }
  return out;
}

function pathOf(kind: string): string {
  if (kind === IconKind.HOME) {
    return HOME;
  }
  if (kind === IconKind.CALENDAR) {
    return CALENDAR;
  }
  if (kind === IconKind.TIMELINE) {
    return TIMELINE;
  }
  if (kind === IconKind.MINE) {
    return MINE;
  }
  if (kind === IconKind.GIFT) {
    return GIFT;
  }
  if (kind === IconKind.PHOTO) {
    return PHOTO;
  }
  if (kind === IconKind.SEARCH) {
    return SEARCH;
  }
  if (kind === IconKind.WALLET) {
    return WALLET;
  }
  if (kind === IconKind.TARGET) {
    return TARGET;
  }
  if (kind === IconKind.CHECK) {
    return CHECK;
  }
  if (kind === IconKind.CHART) {
    return CHART;
  }
  if (kind === IconKind.THEME) {
    return THEME;
  }
  if (kind === IconKind.STAR) {
    return STAR;
  }
  if (kind === IconKind.CHEVRON) {
    return CHEVRON;
  }
  if (kind === IconKind.BACK) {
    return BACK;
  }
  if (kind === IconKind.CLOSE) {
    return CLOSE;
  }
  if (kind === IconKind.TRASH) {
    return TRASH;
  }
  if (kind === IconKind.PLUS) {
    return PLUS;
  }
  if (kind === IconKind.LOCK) {
    return LOCK_PATH;
  }
  if (kind === IconKind.DELETE) {
    return DELETE_PATH;
  }
  return NOTE;
}

/**
 * 图标种类 → 系统符号资源。
 * 符号名取自 SDK 的系统资源索引，写错构建会报错。
 */
export function symbolOf(kind: string): Resource {
  if (kind === IconKind.HOME) {
    return $r('sys.symbol.house');
  }
  if (kind === IconKind.CALENDAR) {
    return $r('sys.symbol.calendar');
  }
  if (kind === IconKind.TIMELINE) {
    return $r('sys.symbol.clock');
  }
  if (kind === IconKind.MINE) {
    return $r('sys.symbol.person');
  }
  if (kind === IconKind.GIFT) {
    return $r('sys.symbol.gift');
  }
  if (kind === IconKind.PHOTO) {
    return $r('sys.symbol.camera');
  }
  if (kind === IconKind.SEARCH) {
    return $r('sys.symbol.magnifyingglass');
  }
  if (kind === IconKind.WALLET) {
    return $r('sys.symbol.wallet');
  }
  if (kind === IconKind.TARGET) {
    return $r('sys.symbol.flag');
  }
  if (kind === IconKind.CHECK) {
    return $r('sys.symbol.checkmark_circle');
  }
  if (kind === IconKind.CHART) {
    return $r('sys.symbol.waveform');
  }
  if (kind === IconKind.THEME) {
    return $r('sys.symbol.moon');
  }
  if (kind === IconKind.STAR) {
    return $r('sys.symbol.star');
  }
  if (kind === IconKind.CHEVRON) {
    return $r('sys.symbol.chevron_forward');
  }
  if (kind === IconKind.BACK) {
    return $r('sys.symbol.chevron_left');
  }
  if (kind === IconKind.CLOSE) {
    return $r('sys.symbol.xmark');
  }
  if (kind === IconKind.TRASH) {
    return $r('sys.symbol.trash');
  }
  if (kind === IconKind.PLUS) {
    return $r('sys.symbol.plus');
  }
  if (kind === IconKind.LOCK) {
    return $r('sys.symbol.lock');
  }
  if (kind === IconKind.DELETE) {
    return $r('sys.symbol.delete_left');
  }
  return $r('sys.symbol.square_and_pencil');
}

/**
 * 线性图标。kind 取 IconKind 常量，iconSize 为字号（vp），color 传颜色资源。
 *
 * strokeW 保留是为了不改动既有调用方：>= 2.2 时用中等字重表达「更实」的观感。
 */
@Component
export struct Icon {
  kind: string = IconKind.NOTE;
  iconSize: number = 24;
  color: ResourceColor = Constants.COLOR_TEXT_SECONDARY;
  strokeW: number = 2;

  build() {
    SymbolGlyph(symbolOf(this.kind))
      .fontSize(this.iconSize)
      .fontColor([this.color])
      .fontWeight(this.strokeW >= 2.2 ? FontWeight.Medium : FontWeight.Regular)
      .renderingStrategy(SymbolRenderingStrategy.SINGLE)
  }
}
