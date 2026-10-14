import { DateUtils } from '../common/utils/DateUtils';
import { MoodTrend, StatsLog, StatsResult, computeMoodTrend, computeStats } from '../models/Stats';
import { RangeReport, ReportDay, buildRangeReport, buildReportDays } from '../models/Report';
import { AnnualReport, availableYears, buildAnnualReport } from '../models/AnnualReport';
import { DailyLog, countChars, hasEntry, moodLabel } from '../models/DailyLog';
import { RepositoryFactory } from './data/RepositoryFactory';
import { SessionManager } from './storage/SessionManager';

/**
 * 统计服务：负责读取数据并交给纯函数 computeStats / computeMoodTrend 汇总。
 * 汇总逻辑本身不在这里，便于单元测试。
 */
export class StatsService {
  /** 心情趋势默认看的天数 */
  static readonly TREND_DAYS: number = 30;

  private static async loadRecords(): Promise<StatsLog[]> {
    const logs: DailyLog[] = await RepositoryFactory.getRepository().getDailyLogs();
    const records: StatsLog[] = [];
    for (const item of logs) {
      // 只写了计划的存根不算记录，不进统计与趋势
      if (!hasEntry(item)) {
        continue;
      }
      records.push({
        date: item.date,
        mood: moodLabel(item.mood, item.customMood),
        chars: countChars(item),
        // 带上标记：年度报告按 hasEntry === true 严格判定，
        // 这里显式写 true，口径与上面 hasEntry(item) 的过滤保持一致
        hasEntry: true
      });
    }
    return records;
  }

  static async load(): Promise<StatsResult> {
    const session = SessionManager.getInstance();
    const startDate: string = await session.getStartDate();

    const repo = RepositoryFactory.getRepository();
    const records: StatsLog[] = await StatsService.loadRecords();
    const importantDays = await repo.getImportantDays();
    const photos = await repo.getPhotos();

    return computeStats(records, startDate, DateUtils.today(), importantDays.length, photos.length);
  }

  /** 近 30 天心情趋势（含今天） */
  static async loadTrend(): Promise<MoodTrend> {
    const records: StatsLog[] = await StatsService.loadRecords();
    return computeMoodTrend(records, DateUtils.today(), StatsService.TREND_DAYS);
  }

  /** 周报 / 月度回顾：days 传 7 或 30 */
  static async loadReport(days: number): Promise<RangeReport> {
    const records: StatsLog[] = await StatsService.loadRecords();
    return buildRangeReport(records, DateUtils.today(), days);
  }

  /** 回顾页的逐日条带 */
  static async loadReportDays(days: number): Promise<ReportDay[]> {
    const records: StatsLog[] = await StatsService.loadRecords();
    return buildReportDays(records, DateUtils.today(), days);
  }

  /** 年度报告：按自然年（1/1–12/31）汇总，口径见 models/AnnualReport.ets */
  static async loadAnnualReport(year: number): Promise<AnnualReport> {
    const records: StatsLog[] = await StatsService.loadRecords();
    return buildAnnualReport(records, year);
  }

  /** 年度报告页的年份胶囊：从最早记录年到今年，降序 */
  static async loadAvailableYears(): Promise<number[]> {
    const records: StatsLog[] = await StatsService.loadRecords();
    return availableYears(records, Number(DateUtils.today().substring(0, 4)));
  }
}
