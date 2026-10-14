import { Constants } from '../common/constants/Constants';
import { DateUtils } from '../common/utils/DateUtils';
import { IdUtils } from '../common/utils/IdUtils';
import {
  LedgerRecord,
  LedgerSummary,
  LedgerType,
  LedgerFeeling,
  FeelingOption,
  FEELING_OPTIONS,
  EXPENSE_CATEGORIES,
  INCOME_CATEGORIES,
  CategoryAmount,
  formatAmount,
  normalizeAmount,
  monthOf,
  summarizeLedger,
  buildDailySpendStrip,
  buildLedgerSummaryLine,
  buildSpendingInsights,
  computeDailyLeft,
  SpendInsight
} from '../models/Ledger';
import { DailyLog, hasEntry, moodLabel } from '../models/DailyLog';
import { RepositoryFactory } from '../services/data/RepositoryFactory';
import { SessionManager } from '../services/storage/SessionManager';
import { Icon, IconKind } from '../components/Icons';

interface DayGroup {
  date: string;
  records: LedgerRecord[];
}

/**
 * 账本页：记支出与收入，按月汇总支出/收入/结余与分类占比，并对比月度预算。
 * 与每日心情记录完全独立。
 */
@Component
export struct LedgerView {
  @State private records: LedgerRecord[] = [];
  @State private budget: number = 0;
  @State private month: string = DateUtils.today().slice(0, 7);
  /** 当前是否为激活的 tab（由 HomePage 传入），用于切回时刷新 */
  @Prop @Watch('onActiveChanged') active: boolean = false;
  @State private loaded: boolean = false;
  @State private saving: boolean = false;
  private scroller: Scroller = new Scroller();

  // 记一笔
  @State private inputType: LedgerType = LedgerType.EXPENSE;
  @State private amountText: string = '';
  @State private category: string = EXPENSE_CATEGORIES[0];
  @State private note: string = '';
  @State private inputDate: string = DateUtils.today();
  /** 这笔支出给你的感受：值得 / 一般 / 后悔（可不选） */
  @State private feeling: LedgerFeeling = LedgerFeeling.NONE;
  /** 心情 × 花费洞察（来自日记心情，本机汇合） */
  @State private insights: SpendInsight[] = [];
  /** 日期 → 当天心情标签，仅供洞察使用，不必参与渲染，所以不做 @State */
  private moodByDate: Map<string, string> = new Map();

  // 预算设置
  @State private showBudgetInput: boolean = false;
  @State private budgetDraft: string = '';

  aboutToAppear(): void {
    this.load();
  }

  /** tab 内容不会触发 onPageShow，改为由 active 变化驱动刷新 */
  onActiveChanged(): void {
    if (this.active) {
      this.load();
    }
  }

  private async load(): Promise<void> {
    try {
      const repo = RepositoryFactory.getRepository();
      this.records = await repo.getLedgerRecords();
      this.budget = await SessionManager.getInstance().getMonthlyBudget();
      // 读日记心情，用于"心情 × 花费"洞察（纯本地，不联网）
      const logs: DailyLog[] = await repo.getDailyLogs();
      const moodMap: Map<string, string> = new Map();
      for (const item of logs) {
        if (hasEntry(item)) {
          moodMap.set(item.date, moodLabel(item.mood, item.customMood));
        }
      }
      this.moodByDate = moodMap;
      this.insights = buildSpendingInsights(this.records, moodMap, this.month);
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '加载失败', duration: 2000 });
    } finally {
      this.loaded = true;
    }
  }

  /** 今天还能花多少；未设预算返回 -1 */
  private dailyLeft(): number {
    const now: Date = new Date();
    const daysInMonth: number = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    return computeDailyLeft(this.summary().expense, this.budget, now.getDate(), daysInMonth);
  }

  /** 本月每天一条支出柱；高度按本月单日最大值分档 */
  private spendStrip(): number[] {
    const now: Date = new Date();
    const daysInMonth: number = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    return buildDailySpendStrip(this.records, this.month, daysInMonth);
  }

  private stripLevel(amount: number, max: number): number {
    if (amount <= 0) {
      return 0;
    }
    if (max <= 0) {
      return 1;
    }
    const ratio: number = amount / max;
    if (ratio <= 0.25) {
      return 1;
    }
    if (ratio <= 0.5) {
      return 2;
    }
    if (ratio <= 0.75) {
      return 3;
    }
    return 4;
  }

  private summary(): LedgerSummary {
    return summarizeLedger(this.records, this.month, this.budget);
  }

  private monthLabel(): string {
    return `${this.month.slice(0, 4)}年${Number(this.month.slice(5, 7))}月`;
  }

  private shiftMonth(delta: number): void {
    const y: number = Number(this.month.slice(0, 4));
    const m: number = Number(this.month.slice(5, 7)) + delta;
    let yy: number = y;
    let mm: number = m;
    while (mm <= 0) {
      mm += 12;
      yy -= 1;
    }
    while (mm > 12) {
      mm -= 12;
      yy += 1;
    }
    this.month = `${yy}-${mm < 10 ? '0' : ''}${mm}`;
  }

  private categories(): string[] {
    return this.inputType === LedgerType.INCOME ? INCOME_CATEGORIES : EXPENSE_CATEGORIES;
  }

  private switchType(type: LedgerType): void {
    if (this.inputType === type) {
      return;
    }
    this.inputType = type;
    this.category = this.categories()[0];
  }

  private openDatePicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date('2000-1-1'),
      end: new Date('2100-12-31'),
      selected: DateUtils.parseDate(this.inputDate),
      onDateAccept: (value: Date) => {
        this.inputDate = DateUtils.formatDate(value);
      }
    });
  }

  private async handleAdd(): Promise<void> {
    if (this.saving) {
      return;
    }
    const amount: number = normalizeAmount(Number(this.amountText.trim()));
    if (this.amountText.trim() === '' || Number.isNaN(Number(this.amountText.trim())) || amount <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入大于 0 的金额', duration: 2000 });
      return;
    }
    this.saving = true;
    try {
      const record: LedgerRecord = {
        id: IdUtils.generate('ledger'),
        date: this.inputDate,
        type: this.inputType,
        amount: amount,
        category: this.category,
        note: this.note.trim().slice(0, 30),
        // 感受只对支出有意义；收入一律未标记
        feeling: this.inputType === LedgerType.EXPENSE ? this.feeling : LedgerFeeling.NONE,
        createdAt: Date.now()
      };
      await RepositoryFactory.getRepository().upsertLedgerRecord(record);
      this.amountText = '';
      this.note = '';
      this.feeling = LedgerFeeling.NONE;
      this.month = monthOf(this.inputDate);
      await this.load();
      this.getUIContext().getPromptAction().showToast({ message: '已记下这一笔', duration: 1500 });
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试', duration: 2000 });
    } finally {
      this.saving = false;
    }
  }

  private confirmDelete(record: LedgerRecord): void {
    this.getUIContext().showAlertDialog({
      title: '删除这笔记录',
      message: `${record.category} ${formatAmount(record.amount)} 元，删除后无法恢复。`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Constants.COLOR_PRIMARY,
        action: () => {
          this.doDelete(record.id);
        }
      }
    });
  }

  private async doDelete(id: string): Promise<void> {
    try {
      await RepositoryFactory.getRepository().deleteLedgerRecord(id);
      await this.load();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败，请重试', duration: 2000 });
    }
  }

  private async saveBudget(): Promise<void> {
    const value: number = normalizeAmount(Number(this.budgetDraft.trim()));
    if (this.budgetDraft.trim() === '' || Number.isNaN(Number(this.budgetDraft.trim()))) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入预算金额', duration: 2000 });
      return;
    }
    await SessionManager.getInstance().setMonthlyBudget(value);
    this.budget = value;
    this.showBudgetInput = false;
    this.getUIContext().getPromptAction().showToast({ message: '预算已更新', duration: 1500 });
  }

  /** 本月记录按日期分组（已在仓储层按日期倒序） */
  private dayGroups(): DayGroup[] {
    const groups: DayGroup[] = [];
    let current: DayGroup | null = null;
    for (const r of this.records) {
      if (monthOf(r.date) !== this.month) {
        continue;
      }
      if (current === null || current.date !== r.date) {
        current = { date: r.date, records: [] };
        groups.push(current);
      }
      current.records.push(r);
    }
    return groups;
  }

  @Builder
  private buildHeader() {
    Column() {
      Row() {
        Text('账本')
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_ON_BRAND)
        Blank()
        Text(`结余 ${formatAmount(this.summary().balance)} 元`)
          .fontSize(15)
          .fontColor(Constants.COLOR_ON_BRAND)
      }
      .width('100%')

      Row() {
        Stack() {
          Icon({ kind: IconKind.BACK, iconSize: 18, color: Constants.COLOR_ON_BRAND })
        }
          .onClick(() => {
            this.shiftMonth(-1);
          })
        Text(this.monthLabel())
          .fontSize(16)
          .fontColor(Constants.COLOR_ON_BRAND)
          .margin({ left: 14, right: 14 })
        Stack() {
          Icon({ kind: IconKind.CHEVRON, iconSize: 18, color: Constants.COLOR_ON_BRAND })
        }
          .onClick(() => {
            this.shiftMonth(1);
          })
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 14, bottom: 18 })
    .linearGradient({
      angle: 135,
      colors: [[Constants.COLOR_HERO_START, 0.0], [Constants.COLOR_HERO_END, 1.0]]
    })
  }

  @Builder
  private buildSummary() {
    Column() {
      Row() {
        Column() {
          Text(formatAmount(this.summary().expense))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
          Text('本月支出')
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        Column() {
          Text(formatAmount(this.summary().income))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_PRIMARY)
          Text('本月收入')
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        Column() {
          Text(formatAmount(this.summary().balance))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.summary().balance < 0 ? Constants.COLOR_TEXT_SECONDARY : Constants.COLOR_TEXT_PRIMARY)
          Text('结余')
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
      }
      .width('100%')

      // 预算
      Row() {
        Text(this.budget > 0 ? `月度预算 ${formatAmount(this.budget)} 元` : '未设置月度预算')
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
        Blank()
        Text(this.budget > 0 ? '修改' : '去设置')
          .fontSize(14)
          .fontColor(Constants.COLOR_PRIMARY)
          .onClick(() => {
            this.budgetDraft = this.budget > 0 ? formatAmount(this.budget) : '';
            this.showBudgetInput = true;
          })
      }
      .width('100%')
      .margin({ top: 16 })

      if (this.budget > 0) {
        Row() {
          Row()
            .width(`${this.summary().budgetPercent}%`)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.summary().overBudget ? Constants.COLOR_TEXT_TERTIARY : Constants.COLOR_PRIMARY)
        }
        .width('100%')
        .height(8)
        .borderRadius(4)
        .backgroundColor(Constants.COLOR_TRACK)
        .margin({ top: 8 })

        Text(this.summary().overBudget
          ? `已超预算 ${formatAmount(-this.summary().budgetLeft)} 元`
          : `已用 ${this.summary().budgetPercent}% · 剩余 ${formatAmount(this.summary().budgetLeft)} 元`)
          .fontSize(13)
          .fontColor(this.summary().overBudget ? Constants.COLOR_TEXT_PRIMARY : Constants.COLOR_TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 8 })
      }

      // 值得指数：把"花了多少"和"花得值不值"分开看，这是纯记账应用给不了的
      if (this.summary().worthScore >= 0) {
        Row() {
          Column() {
            Text(`${this.summary().worthScore}`)
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor(Constants.COLOR_PRIMARY)
            Text('值得指数')
              .fontSize(13)
              .fontColor(Constants.COLOR_TEXT_TERTIARY)
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)

          Column() {
            Text(`值得 ${this.summary().worthCount} · 一般 ${this.summary().neutralCount} · 后悔 ${this.summary().regretCount}`)
              .fontSize(14)
              .fontColor(Constants.COLOR_TEXT_SECONDARY)
            Text('指数 = 值得占比 × 70 + 预算达成度 × 30')
              .fontSize(12)
              .fontColor(Constants.COLOR_TEXT_TERTIARY)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 16 })
        }
        .width('100%')
        .margin({ top: 14 })
        .alignItems(VerticalAlign.Center)
      } else if (this.summary().count > 0) {
        Text('给支出标一下「值得 / 一般 / 后悔」，就能看到这个月的值得指数')
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 12 })
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildInputCard() {
    Column() {
      Text('记一笔')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
        .width('100%')

      Row() {
        Text('支出')
          .fontSize(16)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(36)
          .borderRadius(10)
          .backgroundColor(this.inputType === LedgerType.EXPENSE ? Constants.COLOR_PRIMARY : Constants.COLOR_BACKGROUND)
          .fontColor(this.inputType === LedgerType.EXPENSE ? Constants.COLOR_ON_BRAND : Constants.COLOR_TEXT_SECONDARY)
          .onClick(() => {
            this.switchType(LedgerType.EXPENSE);
          })
        Text('收入')
          .fontSize(16)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
          .height(36)
          .borderRadius(10)
          .backgroundColor(this.inputType === LedgerType.INCOME ? Constants.COLOR_PRIMARY : Constants.COLOR_BACKGROUND)
          .fontColor(this.inputType === LedgerType.INCOME ? Constants.COLOR_ON_BRAND : Constants.COLOR_TEXT_SECONDARY)
          .margin({ left: 10 })
          .onClick(() => {
            this.switchType(LedgerType.INCOME);
          })
      }
      .width('100%')
      .margin({ top: 12 })

      Row() {
        Text('¥')
          .fontSize(20)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
        TextInput({ placeholder: '0.00', text: this.amountText })
          .layoutWeight(1)
          .height(46)
          .fontSize(20)
          .type(InputType.NUMBER_DECIMAL)
          .backgroundColor(Constants.COLOR_BACKGROUND)
          .margin({ left: 8 })
          .onChange((value: string) => {
            this.amountText = value;
          })
      }
      .width('100%')
      .margin({ top: 12 })

      // 分类整块换行铺开：原来横向滚动会把最右边那个裁掉一截
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.categories(), (name: string) => {
          Text(name)
            .fontSize(15)
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .borderRadius(14)
            .backgroundColor(this.category === name ? Constants.COLOR_PRIMARY : Constants.COLOR_BACKGROUND)
            .fontColor(this.category === name ? Constants.COLOR_ON_BRAND : Constants.COLOR_TEXT_SECONDARY)
            .margin({ right: 8, bottom: 8 })
            // 按下时压暗一点，给触摸反馈
            .stateStyles({
              pressed: {
                .opacity(0.6)
              }
            })
            .onClick(() => {
              this.category = name;
            })
        }, (name: string) => name)
      }
      .width('100%')
      .margin({ top: 6 })

      TextInput({ placeholder: '备注（可不填）', text: this.note })
        .width('100%')
        .height(42)
        .fontSize(16)
        .maxLength(30)
        .backgroundColor(Constants.COLOR_BACKGROUND)
        .margin({ top: 12 })
        .onChange((value: string) => {
          this.note = value;
        })

      // 给这笔支出标一个感受 —— 只有同时装着心情日记的应用做得到
      if (this.inputType === LedgerType.EXPENSE) {
        Column() {
          Row() {
            Text('这笔花得')
              .fontSize(14)
              .fontColor(Constants.COLOR_TEXT_TERTIARY)
            Blank()
            Text('可以不选')
              .fontSize(13)
              .fontColor(Constants.COLOR_TEXT_TERTIARY)
          }
          .width('100%')

          Row() {
            ForEach(FEELING_OPTIONS, (option: FeelingOption) => {
              Text(option.label)
                .fontSize(15)
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .padding({ top: 8, bottom: 8 })
                .borderRadius(10)
                .backgroundColor(this.feeling === option.value ? Constants.COLOR_PRIMARY : Constants.COLOR_BACKGROUND)
                .fontColor(this.feeling === option.value ? Constants.COLOR_ON_BRAND : Constants.COLOR_TEXT_SECONDARY)
                .onClick(() => {
                  // 再点一次取消标记
                  this.feeling = this.feeling === option.value ? LedgerFeeling.NONE : option.value;
                })
            }, (option: FeelingOption) => `${option.value}`)
          }
          .width('100%')
          .margin({ top: 8 })
        }
        .width('100%')
        .margin({ top: 12 })
        .alignItems(HorizontalAlign.Start)
      }

      Row() {
        Text(this.inputDate)
          .fontSize(15)
          .fontColor(Constants.COLOR_PRIMARY)
          .onClick(() => {
            this.openDatePicker();
          })
        Blank()
        Button('记下这一笔')
          .height(40)
          .fontSize(16)
          .backgroundColor(Constants.COLOR_PRIMARY)
          .fontColor(Constants.COLOR_ON_BRAND)
          .enabled(!this.saving)
          .onClick(() => {
            this.handleAdd();
          })
      }
      .width('100%')
      .margin({ top: 12 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .margin({ top: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildCategoryBreakdown() {
    if (this.summary().byCategory.length > 0) {
      Column() {
        Text('支出分类')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
          .width('100%')
        ForEach(this.summary().byCategory, (item: CategoryAmount) => {
          Column() {
            Row() {
              Text(item.name)
                .fontSize(15)
                .fontColor(Constants.COLOR_TEXT_PRIMARY)
              Blank()
              Text(`${formatAmount(item.amount)} 元 · ${item.percent}%`)
                .fontSize(13)
                .fontColor(Constants.COLOR_TEXT_SECONDARY)
            }
            .width('100%')

            Row() {
              Row()
                .width(`${item.percent}%`)
                .height(6)
                .borderRadius(3)
                .backgroundColor(Constants.COLOR_PRIMARY)
            }
            .width('100%')
            .height(6)
            .borderRadius(3)
            .backgroundColor(Constants.COLOR_TRACK)
            .margin({ top: 6 })
          }
          .width('100%')
          .margin({ top: 12 })
        }, (item: CategoryAmount) => item.name)
      }
      .width('100%')
      .padding(16)
      .borderRadius(16)
      .backgroundColor(Constants.COLOR_CARD)
      .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
      .margin({ top: 14 })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private buildList() {
    ForEach(this.dayGroups(), (group: DayGroup) => {
      Column() {
        Text(group.date)
          .fontSize(14)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .width('100%')
        ForEach(group.records, (record: LedgerRecord) => {
          Row() {
            Column() {
              Text(record.category)
                .fontSize(16)
                .fontColor(Constants.COLOR_TEXT_PRIMARY)
              if (record.note !== '') {
                Text(record.note)
                  .fontSize(13)
                  .fontColor(Constants.COLOR_TEXT_TERTIARY)
                  .margin({ top: 2 })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text(`${record.type === LedgerType.INCOME ? '+' : '-'}${formatAmount(record.amount)}`)
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(record.type === LedgerType.INCOME ? Constants.COLOR_PRIMARY : Constants.COLOR_TEXT_PRIMARY)
          }
          .width('100%')
          .padding({ top: 10, bottom: 10 })
          .alignItems(VerticalAlign.Center)
          .border({ width: { bottom: 1 }, color: Constants.COLOR_DIVIDER })
          .onClick(() => {
            this.confirmDelete(record);
          })
        }, (record: LedgerRecord) => record.id)
      }
      .width('100%')
      .padding(16)
      .borderRadius(16)
      .backgroundColor(Constants.COLOR_CARD)
      .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
      .margin({ top: 14 })
      .alignItems(HorizontalAlign.Start)
    }, (group: DayGroup) => group.date)
  }

  @Builder
  private buildEmpty() {
    Column() {
      Text('这个月还没有记账')
        .fontSize(16)
        .fontColor(Constants.COLOR_TEXT_SECONDARY)
      Text('在上面记下第一笔支出或收入吧')
        .fontSize(14)
        .fontColor(Constants.COLOR_TEXT_TERTIARY)
        .margin({ top: 8 })
    }
    .width('100%')
    // 底部留够空间，别让右下角悬浮按钮压到空态文案
    .padding({ top: 30, bottom: 96 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildBudgetDialog() {
    Column() {
      Column()
        .width('100%')
        .layoutWeight(1)
        .onClick(() => {
          this.showBudgetInput = false;
        })

      Column() {
        Text('设置月度预算')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
          .width('100%')
        Text('用来对照本月支出，接近或超出时会给出提示')
          .fontSize(13)
          .fontColor(Constants.COLOR_TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 4 })

        TextInput({ placeholder: '比如 3000', text: this.budgetDraft })
          .width('100%')
          .height(46)
          .fontSize(18)
          .type(InputType.NUMBER_DECIMAL)
          .backgroundColor(Constants.COLOR_BACKGROUND)
          .margin({ top: 14 })
          .onChange((value: string) => {
            this.budgetDraft = value;
          })

        Row() {
          Button('取消')
            .layoutWeight(1)
            .height(42)
            .fontSize(17)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .backgroundColor(Constants.COLOR_BACKGROUND)
            .onClick(() => {
              this.showBudgetInput = false;
            })
          Button('保存')
            .layoutWeight(1)
            .height(42)
            .fontSize(17)
            .backgroundColor(Constants.COLOR_PRIMARY)
            .fontColor(Constants.COLOR_ON_BRAND)
            .margin({ left: 10 })
            .onClick(() => {
              this.saveBudget();
            })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('100%')
      .padding(20)
      .borderRadius({ topLeft: 20, topRight: 20 })
      .backgroundColor(Constants.COLOR_CARD)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
  }

  private maxSpend(): number {
    let max: number = 0;
    for (const value of this.spendStrip()) {
      if (value > max) {
        max = value;
      }
    }
    return max;
  }

  /**
   * 账本独有的洞察：今天还能花多少 / 最后悔的三笔 / 心情×花费 / 每日节奏 / 本月小结。
   * 这些是纯记账应用给不了的 —— 因为它们不知道你那天什么心情。
   */
  @Builder
  private buildLedgerInsights() {
    Column() {
      if (this.budget > 0) {
        Row() {
          Icon({ kind: IconKind.WALLET, iconSize: 24, color: Constants.COLOR_PRIMARY })
          Text(this.dailyLeft() < 0
            ? `本月已超支 ${formatAmount(-this.dailyLeft())} 元`
            : `今天还能花 ${formatAmount(this.dailyLeft())} 元`)
            .fontSize(16)
            .fontColor(Constants.COLOR_TEXT_PRIMARY)
            .margin({ left: 8 })
          Blank()
          Text('按剩余天数摊')
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_TERTIARY)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      if (this.summary().regretTop.length > 0) {
        Text('最后悔的三笔')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
          .width('100%')
          .margin({ top: this.budget > 0 ? 16 : 0 })

        ForEach(this.summary().regretTop, (item: LedgerRecord) => {
          Row() {
            Column() {
              Text(item.category)
                .fontSize(15)
                .fontColor(Constants.COLOR_TEXT_PRIMARY)
              Text(item.note === '' ? item.date : `${item.date} · ${item.note}`)
                .fontSize(13)
                .fontColor(Constants.COLOR_TEXT_TERTIARY)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text(`-${formatAmount(item.amount)}`)
              .fontSize(15)
              .fontColor(Constants.COLOR_TEXT_PRIMARY)
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .alignItems(VerticalAlign.Center)
        }, (item: LedgerRecord) => item.id)
      }

      if (this.insights.length > 0) {
        Text('心情和花费的关系')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
          .width('100%')
          .margin({ top: 16 })

        ForEach(this.insights, (item: SpendInsight) => {
          Text(`· ${item.text}`)
            .fontSize(14)
            .lineHeight(22)
            .fontColor(Constants.COLOR_TEXT_SECONDARY)
            .width('100%')
            .margin({ top: 8 })
        }, (item: SpendInsight) => item.text)
      }

      if (this.summary().count > 0) {
        Text('每天的支出')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Constants.COLOR_TEXT_PRIMARY)
          .width('100%')
          .margin({ top: 16 })

        Row() {
          ForEach(this.spendStrip(), (amount: number, index: number) => {
            Column()
              .layoutWeight(1)
              .height(this.stripLevel(amount, this.maxSpend()) === 0
                ? 4
                : 6 + this.stripLevel(amount, this.maxSpend()) * 6)
              .borderRadius(3)
              .backgroundColor(this.stripLevel(amount, this.maxSpend()) === 0
                ? Constants.COLOR_TRACK
                : Constants.COLOR_PRIMARY)
              .margin({ right: 2 })
          }, (amount: number, index: number) => `${index}`)
        }
        .width('100%')
        .height(40)
        .alignItems(VerticalAlign.Bottom)
        .margin({ top: 10 })

        Text(buildLedgerSummaryLine(this.summary()))
          .fontSize(14)
          .lineHeight(24)
          .fontColor(Constants.COLOR_TEXT_SECONDARY)
          .width('100%')
          .margin({ top: 14 })
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(Constants.COLOR_CARD)
    .shadow({ radius: 12, color: Constants.COLOR_SHADOW, offsetY: 4 })
    .margin({ top: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.buildHeader()
        Scroll(this.scroller) {
          Column() {
            if (!this.loaded) {
              Text('加载中…')
                .fontSize(15)
                .fontColor(Constants.COLOR_TEXT_TERTIARY)
                .margin({ top: 40 })
            } else {
              this.buildSummary()
              this.buildInputCard()
              this.buildCategoryBreakdown()
              if (this.records.length > 0) {
                this.buildLedgerInsights()
              }
              if (this.dayGroups().length === 0) {
                this.buildEmpty()
              } else {
                this.buildList()
              }
            }
          }
          .width('100%')
          // 底部多留 96：右下角悬浮按钮会盖在内容上，留够空间就不会压住
          // 「这笔花得」和「记下这一笔」这些可点控件
          .padding({ left: 16, right: 16, top: 16, bottom: 96 })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Constants.COLOR_BACKGROUND)

      if (this.showBudgetInput) {
        this.buildBudgetDialog()
      }

      // 悬浮按钮：一键回到「记一笔」
      if (!this.showBudgetInput) {
        Stack() {
          Icon({ kind: IconKind.PLUS, iconSize: 28, color: Constants.COLOR_ON_BRAND, strokeW: 2.2 })
        }
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor(Constants.COLOR_HERO_START)
        .shadow({ radius: 16, color: Constants.COLOR_SHADOW, offsetY: 6 })
        .margin({ right: 20, bottom: 28 })
        .onClick(() => {
          this.scroller.scrollEdge(Edge.Top);
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
