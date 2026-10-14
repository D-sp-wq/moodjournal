import { describe, it, expect } from '@ohos/hypium';
import {
  DailyLog,
  Mood,
  TextSegment,
  matchLog,
  matchSnippet,
  searchLogs,
  splitByKeyword
} from '../main/ets/models/DailyLog';
import {
  EMPTY_FILTERS,
  RANGE_30,
  RANGE_7,
  SearchFilters,
  applyFilters,
  availableMoods,
  describeFilters,
  isFilterEmpty,
  matchesFilters,
  rangeLabel
} from '../main/ets/models/SearchFilter';

function makeLog(date: string, mood: Mood, custom: string, journal: string, plan: string): DailyLog {
  return {
    id: date,
    date: date,
    mood: mood,
    customMood: custom,
    journal: journal,
    plan: plan,
    photoUris: [],
    tags: [],
    hasEntry: true,
    createdAt: 0,
    updatedAt: 0
  };
}

/** 造一条可控的记录：搜索筛选的每个条件都要能单独摆布 */
function makeFullLog(date: string, mood: Mood, custom: string, journal: string,
  photos: string[], tags: string[], entry: boolean): DailyLog {
  const log: DailyLog = makeLog(date, mood, custom, journal, '');
  log.photoUris = photos;
  log.tags = tags;
  log.hasEntry = entry;
  return log;
}

/** 数组拼成字符串再断言，避免依赖深比较 API */
function joined(list: string[]): string {
  return list.join('|');
}

/** 日期串拼成字符串，断言「留下了哪几天」 */
function dates(logs: DailyLog[]): string {
  const out: string[] = [];
  for (const log of logs) {
    out.push(log.date);
  }
  return out.join('|');
}

/** 在默认条件上改几个字段，得到一份筛选条件 */
function filtersOf(keyword: string, mood: string, rangeDays: number, photoOnly: boolean,
  tag: string): SearchFilters {
  const f: SearchFilters = {
    keyword: keyword,
    mood: mood,
    rangeDays: rangeDays,
    photoOnly: photoOnly,
    tag: tag
  };
  return f;
}

/** 只有心情与标签的筛选条件 */
function moodTagFilters(mood: string, tag: string): SearchFilters {
  return filtersOf('', mood, 0, false, tag);
}

export default function searchTest() {
  describe('Search', () => {
    it('match_journal', 0, () => {
      const log: DailyLog = makeLog('2026-10-01', Mood.HAPPY, '', '今天去爬山了', '');
      expect(matchLog(log, '爬山')).assertTrue();
    });

    it('match_plan_and_mood_label', 0, () => {
      const log: DailyLog = makeLog('2026-10-01', Mood.HAPPY, '', '', '明天写报告');
      expect(matchLog(log, '报告')).assertTrue();
      expect(matchLog(log, '开心')).assertTrue();
    });

    it('match_custom_mood_text', 0, () => {
      const log: DailyLog = makeLog('2026-10-01', Mood.CUSTOM, '元气满满', '', '');
      expect(matchLog(log, '元气')).assertTrue();
    });

    it('no_match_and_blank_keyword', 0, () => {
      const log: DailyLog = makeLog('2026-10-01', Mood.SAD, '', '今天有点难受', '');
      expect(matchLog(log, '爬山')).assertFalse();
      expect(matchLog(log, '   ')).assertFalse();
      expect(searchLogs([log], '').length).assertEqual(0);
      expect(searchLogs([log], '   ').length).assertEqual(0);
    });

    it('search_filters_and_keeps_order', 0, () => {
      const hit: DailyLog = makeLog('2026-10-02', Mood.HAPPY, '', '去爬山', '');
      const miss: DailyLog = makeLog('2026-10-01', Mood.SAD, '', '在家待着', '');
      const result: DailyLog[] = searchLogs([hit, miss], '爬山');
      expect(result.length).assertEqual(1);
      expect(result[0].date).assertEqual('2026-10-02');
    });

    it('split_by_keyword', 0, () => {
      const segments: TextSegment[] = splitByKeyword('今天去爬山，明天也爬山', '爬山');
      expect(segments.length).assertEqual(4);
      expect(segments[0].hit).assertFalse();
      expect(segments[1].hit).assertTrue();
      expect(segments[1].text).assertEqual('爬山');
      expect(segments[3].hit).assertTrue();
    });

    it('split_with_blank_keyword_returns_whole', 0, () => {
      const segments: TextSegment[] = splitByKeyword('随便一段话', '  ');
      expect(segments.length).assertEqual(1);
      expect(segments[0].hit).assertFalse();
      expect(segments[0].text).assertEqual('随便一段话');
    });

    it('snippet_contains_hit', 0, () => {
      const log: DailyLog = makeLog('2026-10-01', Mood.HAPPY, '', '一二三四五六七八九十今天去爬山了真开心', '');
      const snippet: string = matchSnippet(log, '爬山', 12);
      expect(snippet.indexOf('爬山') >= 0).assertTrue();
    });

    // ---------------- SearchFilters: applyFilters / matchesFilters ----------------

    // 时间范围用例统一以 2026-10-10 为「今天」：
    // 近 7 天 = [2026-10-04, 2026-10-10]；近 30 天 = [2026-09-11, 2026-10-10]。
    const TODAY: string = '2026-10-10';

    it('filters_default_keeps_all_real_logs', 0, () => {
      const logs: DailyLog[] = [
        makeFullLog('2026-10-03', Mood.HAPPY, '', '去爬山', [], ['工作'], true),
        makeFullLog('2020-01-01', Mood.SAD, '', '很久以前', ['file://a.jpg'], [], true),
        // 计划存根（hasEntry = false）不算记录，即使条件全默认也要排除
        makeFullLog('2026-10-04', Mood.HAPPY, '', '只写了明天的计划', [], [], false)
      ];
      const result: DailyLog[] = applyFilters(logs, EMPTY_FILTERS, TODAY);
      expect(result.length).assertEqual(2);
      expect(dates(result)).assertEqual('2026-10-03|2020-01-01');
      // 空输入返回空数组
      expect(applyFilters([], EMPTY_FILTERS, TODAY).length).assertEqual(0);
    });

    it('filters_by_keyword_only', 0, () => {
      const hit: DailyLog = makeFullLog('2026-10-02', Mood.HAPPY, '', '去爬山', [], [], true);
      const miss: DailyLog = makeFullLog('2026-10-01', Mood.SAD, '', '在家待着', [], [], true);
      const result: DailyLog[] = applyFilters([hit, miss], filtersOf('爬山', '', 0, false, ''), TODAY);
      expect(result.length).assertEqual(1);
      expect(result[0].date).assertEqual('2026-10-02');
      // 只输空格等于没输关键词，不做关键词过滤
      expect(applyFilters([hit, miss], filtersOf('   ', '', 0, false, ''), TODAY).length).assertEqual(2);
    });

    it('filters_by_mood_only', 0, () => {
      const happy: DailyLog = makeFullLog('2026-10-02', Mood.HAPPY, '', '爬山', [], [], true);
      const sad: DailyLog = makeFullLog('2026-10-01', Mood.SAD, '', '在家', [], [], true);
      const result: DailyLog[] = applyFilters([happy, sad], moodTagFilters('开心', ''), TODAY);
      expect(result.length).assertEqual(1);
      expect(result[0].date).assertEqual('2026-10-02');
      // 心情是精确匹配标签，不做包含匹配
      expect(applyFilters([happy, sad], moodTagFilters('开', ''), TODAY).length).assertEqual(0);
    });

    it('filters_by_range_only', 0, () => {
      const today: DailyLog = makeFullLog('2026-10-10', Mood.HAPPY, '', '今天', [], [], true);
      const fiveDaysAgo: DailyLog = makeFullLog('2026-10-05', Mood.HAPPY, '', '五天前', [], [], true);
      const halfYearAgo: DailyLog = makeFullLog('2025-11-01', Mood.HAPPY, '', '半年前', [], [], true);
      const oneYearAgo: DailyLog = makeFullLog('2025-10-10', Mood.HAPPY, '', '一年前', [], [], true);
      const monthAgo: DailyLog = makeFullLog('2026-09-01', Mood.HAPPY, '', '一个月前', [], [], true);
      const logs: DailyLog[] = [today, fiveDaysAgo, halfYearAgo, oneYearAgo, monthAgo];

      // 近 7 天 = [2026-10-04, 2026-10-10]
      const week: SearchFilters = filtersOf('', '', RANGE_7, false, '');
      const weekResult: DailyLog[] = applyFilters(logs, week, TODAY);
      expect(weekResult.length).assertEqual(2);
      expect(dates(weekResult)).assertEqual('2026-10-10|2026-10-05');
      expect(matchesFilters(today, week, TODAY)).assertTrue();
      expect(matchesFilters(fiveDaysAgo, week, TODAY)).assertTrue();

      // 近 30 天 = [2026-09-11, 2026-10-10]，2026-09-01 差 39 天，落在区间外
      const month: SearchFilters = filtersOf('', '', RANGE_30, false, '');
      const monthResult: DailyLog[] = applyFilters(logs, month, TODAY);
      expect(monthResult.length).assertEqual(2);
      expect(matchesFilters(monthAgo, month, TODAY)).assertFalse();
      expect(matchesFilters(halfYearAgo, month, TODAY)).assertFalse();

      // 近一年 = [2025-10-11, 2026-10-10]：
      // 2026-09-01（39 天前）在区间内；2025-10-10（刚好 365 天）落在区间外
      const year: SearchFilters = filtersOf('', '', 365, false, '');
      const yearResult: DailyLog[] = applyFilters(logs, year, TODAY);
      expect(yearResult.length).assertEqual(4);
      expect(dates(yearResult)).assertEqual('2026-10-10|2026-10-05|2025-11-01|2026-09-01');
      expect(matchesFilters(halfYearAgo, year, TODAY)).assertTrue();
      expect(matchesFilters(monthAgo, year, TODAY)).assertTrue();
      expect(matchesFilters(oneYearAgo, year, TODAY)).assertFalse();
      // 364 天为界时，差 365 天的记录同样在区间外（区间末日 = today - 363）
      expect(matchesFilters(oneYearAgo, filtersOf('', '', 364, false, ''), TODAY)).assertFalse();
      // 差 343 天的记录在 344 天为界时仍在区间内
      expect(matchesFilters(halfYearAgo, filtersOf('', '', 344, false, ''), TODAY)).assertTrue();
      expect(matchesFilters(halfYearAgo, filtersOf('', '', 343, false, ''), TODAY)).assertFalse();
    });

    it('range_boundaries_are_inclusive', 0, () => {
      const first: DailyLog = makeFullLog('2026-10-04', Mood.HAPPY, '', '区间首日', [], [], true);
      const last: DailyLog = makeFullLog('2026-10-10', Mood.HAPPY, '', '区间末日', [], [], true);
      const before: DailyLog = makeFullLog('2026-10-03', Mood.HAPPY, '', '区间外一天', [], [], true);
      const after: DailyLog = makeFullLog('2026-10-11', Mood.HAPPY, '', '明天', [], [], true);
      expect(matchesFilters(first, filtersOf('', '', RANGE_7, false, ''), TODAY)).assertTrue();
      expect(matchesFilters(last, filtersOf('', '', RANGE_7, false, ''), TODAY)).assertTrue();
      expect(matchesFilters(before, filtersOf('', '', RANGE_7, false, ''), TODAY)).assertFalse();
      // 未来日期不算「近 7 天」
      expect(matchesFilters(after, filtersOf('', '', RANGE_7, false, ''), TODAY)).assertFalse();
      const result: DailyLog[] = applyFilters([first, last, before, after],
        filtersOf('', '', RANGE_7, false, ''), TODAY);
      expect(dates(result)).assertEqual('2026-10-04|2026-10-10');
    });

    it('filters_by_photo_only', 0, () => {
      const withPhoto: DailyLog = makeFullLog('2026-10-02', Mood.HAPPY, '', '有照片',
        ['file://a.jpg'], [], true);
      const without: DailyLog = makeFullLog('2026-10-01', Mood.HAPPY, '', '没照片', [], [], true);
      const result: DailyLog[] = applyFilters([withPhoto, without], filtersOf('', '', 0, true, ''), TODAY);
      expect(result.length).assertEqual(1);
      expect(result[0].date).assertEqual('2026-10-02');
    });

    it('filters_by_tag_only', 0, () => {
      const work: DailyLog = makeFullLog('2026-10-02', Mood.HAPPY, '', '写报告', [], ['工作'], true);
      const read: DailyLog = makeFullLog('2026-10-01', Mood.HAPPY, '', '读书', [], ['读书'], true);
      const result: DailyLog[] = applyFilters([work, read], moodTagFilters('', '工作'), TODAY);
      expect(result.length).assertEqual(1);
      expect(result[0].date).assertEqual('2026-10-02');
      // 标签是精确匹配：'工作' 不该命中 '工作复盘'
      const review: DailyLog = makeFullLog('2026-10-03', Mood.HAPPY, '', '复盘', [], ['工作复盘'], true);
      expect(applyFilters([review], moodTagFilters('', '工作'), TODAY).length).assertEqual(0);
    });

    it('filters_combine_with_and', 0, () => {
      const full: DailyLog = makeFullLog('2026-10-08', Mood.HAPPY, '', '和同事去爬山',
        ['file://a.jpg'], ['工作'], true);
      const noPhoto: DailyLog = makeFullLog('2026-10-08', Mood.HAPPY, '', '和同事去爬山', [], ['工作'], true);
      const noTag: DailyLog = makeFullLog('2026-10-08', Mood.HAPPY, '', '和同事去爬山',
        ['file://a.jpg'], ['读书'], true);
      const old: DailyLog = makeFullLog('2026-08-01', Mood.HAPPY, '', '和同事去爬山',
        ['file://a.jpg'], ['工作'], true);
      const otherMood: DailyLog = makeFullLog('2026-10-08', Mood.SAD, '', '和同事去爬山',
        ['file://a.jpg'], ['工作'], true);
      const logs: DailyLog[] = [full, noPhoto, noTag, old, otherMood];
      const filters: SearchFilters = filtersOf('爬山', '开心', RANGE_30, true, '工作');
      const result: DailyLog[] = applyFilters(logs, filters, TODAY);
      expect(result.length).assertEqual(1);
      expect(result[0].date).assertEqual('2026-10-08');
      // 同一条数据对 matchesFilters 也必须成立
      expect(matchesFilters(full, filters, TODAY)).assertTrue();
      expect(matchesFilters(noPhoto, filters, TODAY)).assertFalse();
      expect(matchesFilters(noTag, filters, TODAY)).assertFalse();
      expect(matchesFilters(old, filters, TODAY)).assertFalse();
      expect(matchesFilters(otherMood, filters, TODAY)).assertFalse();
    });

    it('photo_and_tag_together', 0, () => {
      const both: DailyLog = makeFullLog('2026-10-05', Mood.HAPPY, '', '旅行',
        ['file://a.jpg', 'file://b.jpg'], ['旅行'], true);
      const tagOnly: DailyLog = makeFullLog('2026-10-04', Mood.HAPPY, '', '旅行', [], ['旅行'], true);
      const photoOnly: DailyLog = makeFullLog('2026-10-03', Mood.HAPPY, '', '随手拍',
        ['file://c.jpg'], ['随手'], true);
      const logs: DailyLog[] = [both, tagOnly, photoOnly];

      // 只按标签：两条带「旅行」的都在
      const byTag: DailyLog[] = applyFilters(logs, moodTagFilters('', '旅行'), TODAY);
      expect(byTag.length).assertEqual(2);
      expect(dates(byTag)).assertEqual('2026-10-05|2026-10-04');

      // 标签 + 只看有照片：只剩既有照片又有标签的那条
      const withPhoto: SearchFilters = filtersOf('', '', 0, true, '旅行');
      const byBoth: DailyLog[] = applyFilters(logs, withPhoto, TODAY);
      expect(byBoth.length).assertEqual(1);
      expect(byBoth[0].date).assertEqual('2026-10-05');
      expect(matchesFilters(both, withPhoto, TODAY)).assertTrue();
      expect(matchesFilters(tagOnly, withPhoto, TODAY)).assertFalse();
      expect(matchesFilters(photoOnly, withPhoto, TODAY)).assertFalse();
    });

    it('matches_filters_agrees_with_apply_filters', 0, () => {
      const logs: DailyLog[] = [
        makeFullLog('2026-10-10', Mood.HAPPY, '', '爬山', ['file://a.jpg'], ['运动'], true),
        makeFullLog('2026-10-09', Mood.SAD, '', '爬山', [], ['运动'], true),
        makeFullLog('2026-10-02', Mood.HAPPY, '', '在家躺着', ['file://b.jpg'], [], true),
        makeFullLog('2026-09-01', Mood.HAPPY, '', '爬山', ['file://c.jpg'], ['运动'], true),
        makeFullLog('2026-10-08', Mood.HAPPY, '', '爬山', ['file://d.jpg'], ['运动'], false)
      ];
      const combos: SearchFilters[] = [
        filtersOf('', '', 0, false, ''),
        filtersOf('爬山', '', 0, false, ''),
        filtersOf('', '开心', 0, false, ''),
        filtersOf('', '', RANGE_7, false, ''),
        filtersOf('', '', 0, true, ''),
        filtersOf('', '', 0, false, '运动'),
        filtersOf('爬山', '开心', RANGE_30, true, '运动'),
        filtersOf('不存在的词', '', 0, false, '')
      ];
      for (const filters of combos) {
        const byApply: string = dates(applyFilters(logs, filters, TODAY));
        const oneByOne: string[] = [];
        for (const log of logs) {
          if (matchesFilters(log, filters, TODAY)) {
            oneByOne.push(log.date);
          }
        }
        expect(byApply).assertEqual(oneByOne.join('|'));
      }
    });

    it('custom_mood_participates_in_filtering', 0, () => {
      const custom: DailyLog = makeFullLog('2026-10-07', Mood.CUSTOM, '元气满满', '去跑步', [], [], true);
      const happy: DailyLog = makeFullLog('2026-10-06', Mood.HAPPY, '', '去跑步', [], [], true);
      const logs: DailyLog[] = [custom, happy];
      const result: DailyLog[] = applyFilters(logs, moodTagFilters('元气满满', ''), TODAY);
      expect(result.length).assertEqual(1);
      expect(result[0].date).assertEqual('2026-10-07');
      expect(describeFilters(moodTagFilters('元气满满', ''))[0]).assertEqual('心情：元气满满');
      // 自定义心情与「开心」都只出现 1 次；次数相同时固定心情在前，顺序稳定
      expect(joined(availableMoods(logs))).assertEqual('开心|元气满满');
    });

    // ---------------- describeFilters / isFilterEmpty / availableMoods ----------------

    it('describe_empty_filters_is_empty', 0, () => {
      expect(describeFilters(EMPTY_FILTERS).length).assertEqual(0);
      expect(describeFilters(filtersOf('爬山', '', 0, false, '')).length).assertEqual(0);
      expect(isFilterEmpty(EMPTY_FILTERS)).assertTrue();
    });

    it('describe_single_filters', 0, () => {
      expect(joined(describeFilters(moodTagFilters('开心', '')))).assertEqual('心情：开心');
      expect(joined(describeFilters(filtersOf('', '', RANGE_7, false, '')))).assertEqual('时间：近 7 天');
      expect(joined(describeFilters(filtersOf('', '', RANGE_30, false, '')))).assertEqual('时间：近 30 天');
      expect(joined(describeFilters(filtersOf('', '', 365, false, '')))).assertEqual('时间：近一年');
      expect(joined(describeFilters(filtersOf('', '', 0, true, '')))).assertEqual('有照片');
      expect(joined(describeFilters(moodTagFilters('', '工作')))).assertEqual('标签：工作');
    });

    it('describe_combines_in_fixed_order', 0, () => {
      expect(joined(describeFilters(filtersOf('', '开心', RANGE_30, true, '工作'))))
        .assertEqual('心情：开心|时间：近 30 天|有照片|标签：工作');
      // 只挑后三项，顺序依然固定
      expect(joined(describeFilters(filtersOf('', '', RANGE_7, true, '旅行'))))
        .assertEqual('时间：近 7 天|有照片|标签：旅行');
      expect(joined(describeFilters(filtersOf('关键词不算筛选', '开心', 0, true, ''))))
        .assertEqual('心情：开心|有照片');
    });

    it('is_filter_empty_reacts_to_each_field', 0, () => {
      expect(isFilterEmpty(moodTagFilters('', ''))).assertTrue();
      expect(isFilterEmpty(filtersOf('爬山', '', 0, false, ''))).assertTrue();
      expect(isFilterEmpty(moodTagFilters('开心', ''))).assertFalse();
      expect(isFilterEmpty(filtersOf('', '', RANGE_7, false, ''))).assertFalse();
      expect(isFilterEmpty(filtersOf('', '', 0, true, ''))).assertFalse();
      expect(isFilterEmpty(moodTagFilters('', '工作'))).assertFalse();
      // 只输空格不算筛选
      expect(isFilterEmpty(moodTagFilters('   ', ''))).assertTrue();
    });

    it('available_moods_orders_by_count_desc', 0, () => {
      const logs: DailyLog[] = [
        makeFullLog('2026-10-03', Mood.HAPPY, '', '还行', [], [], true),
        makeFullLog('2026-10-02', Mood.SAD, '', '低落', [], [], true),
        makeFullLog('2026-10-01', Mood.HAPPY, '', '还行', [], [], true)
      ];
      const moods: string[] = availableMoods(logs);
      expect(moods.length).assertEqual(2);
      expect(joined(moods)).assertEqual('开心|低落');
    });

    it('available_moods_empty_input_and_stubs', 0, () => {
      expect(availableMoods([]).length).assertEqual(0);
      // 存根不算；只写了计划、心情是默认值的存根不该出现在胶囊里
      const stub: DailyLog = makeFullLog('2026-10-04', Mood.HAPPY, '', '明天的计划', [], [], false);
      expect(availableMoods([stub]).length).assertEqual(0);
      const real: DailyLog = makeFullLog('2026-10-05', Mood.SAD, '', '在家', [], [], true);
      expect(joined(availableMoods([stub, real]))).assertEqual('低落');
    });

    it('range_labels_and_range_options', 0, () => {
      expect(rangeLabel(0)).assertEqual('不限');
      expect(rangeLabel(RANGE_7)).assertEqual('近 7 天');
      expect(rangeLabel(RANGE_30)).assertEqual('近 30 天');
      expect(rangeLabel(365)).assertEqual('近一年');
    });
  });
}
