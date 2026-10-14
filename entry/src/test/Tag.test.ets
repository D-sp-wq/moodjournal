import { describe, it, expect } from '@ohos/hypium';
import { DailyLog, Mood, parseTags, serializeTags } from '../main/ets/models/DailyLog';
import {
  MAX_LOG_TAGS,
  MAX_TAG_LENGTH,
  TagCount,
  collectTags,
  filterByTag,
  hasTag,
  normalizeTagInput
} from '../main/ets/models/Tag';

/**
 * 标签功能测试。
 *
 * 全部数据都在用例里现构造，不读数据库、不读文件系统：
 * models/Tag.ets 与 DailyLog 的 serializeTags/parseTags 都是纯函数。
 */

/** 造一条记录；只有标签与 hasEntry 是各用例关心的 */
function makeLog(date: string, tags: string[], entry: boolean): DailyLog {
  return {
    id: date,
    date: date,
    mood: Mood.HAPPY,
    customMood: '',
    journal: '今天还行',
    plan: '',
    photoUris: [],
    tags: tags,
    hasEntry: entry,
    createdAt: 0,
    updatedAt: 0
  };
}

/** 数组拼成字符串再断言，避免依赖深比较 API */
function joined(list: string[]): string {
  return list.join('|');
}

/** 标签云的「名称」串 */
function names(tags: TagCount[]): string {
  const out: string[] = [];
  for (const item of tags) {
    out.push(item.name);
  }
  return out.join('|');
}

/** 标签云的「次数」串 */
function counts(tags: TagCount[]): string {
  const out: string[] = [];
  for (const item of tags) {
    out.push(`${item.count}`);
  }
  return out.join('|');
}

export default function tagTest() {
  describe('Tag', () => {
    it('limits_match_spec', 0, () => {
      expect(MAX_LOG_TAGS).assertEqual(3);
      expect(MAX_TAG_LENGTH).assertEqual(8);
    });

    // ---------------- normalizeTagInput ----------------

    it('splits_on_space_comma_and_dunhao', 0, () => {
      expect(joined(normalizeTagInput('工作 读书', []))).assertEqual('工作|读书');
      expect(joined(normalizeTagInput('工作,读书', []))).assertEqual('工作|读书');
      expect(joined(normalizeTagInput('工作，读书', []))).assertEqual('工作|读书');
      expect(joined(normalizeTagInput('工作、读书', []))).assertEqual('工作|读书');
      // 混着写也要能切开（第 4 个超出上限，被丢掉）
      expect(joined(normalizeTagInput('工作、读书 运动，旅行', []))).assertEqual('工作|读书|运动');
    });

    it('trims_whitespace_around_tags', 0, () => {
      expect(joined(normalizeTagInput('   工作  ,  读书  ', []))).assertEqual('工作|读书');
    });

    it('dedupes_repeated_tags', 0, () => {
      const tags: string[] = normalizeTagInput('工作 工作 读书 工作', []);
      expect(tags.length).assertEqual(2);
      expect(joined(tags)).assertEqual('工作|读书');
    });

    it('truncates_long_tag_to_max_length', 0, () => {
      const tags: string[] = normalizeTagInput('一二三四五六七八九十', []);
      expect(tags.length).assertEqual(1);
      expect(tags[0].length).assertEqual(MAX_TAG_LENGTH);
      expect(tags[0]).assertEqual('一二三四五六七八');
    });

    it('keeps_only_first_three_tags', 0, () => {
      const tags: string[] = normalizeTagInput('a b c d e', []);
      expect(tags.length).assertEqual(MAX_LOG_TAGS);
      expect(joined(tags)).assertEqual('a|b|c');
    });

    it('blank_input_returns_empty', 0, () => {
      expect(normalizeTagInput('', []).length).assertEqual(0);
      expect(normalizeTagInput('   ', []).length).assertEqual(0);
      expect(normalizeTagInput(' , ，、 ', []).length).assertEqual(0);
    });

    it('does_not_duplicate_existing_tags', 0, () => {
      const once: string[] = normalizeTagInput('工作', ['工作']);
      expect(once.length).assertEqual(1);
      expect(joined(once)).assertEqual('工作');

      const both: string[] = normalizeTagInput('工作 读书', ['工作']);
      expect(both.length).assertEqual(2);
      expect(joined(both)).assertEqual('工作|读书');
    });

    it('existing_tags_are_kept_when_full', 0, () => {
      const tags: string[] = normalizeTagInput('d', ['a', 'b', 'c']);
      expect(tags.length).assertEqual(MAX_LOG_TAGS);
      expect(joined(tags)).assertEqual('a|b|c');
    });

    it('cleans_dirty_existing_tags', 0, () => {
      // 已有标签里的空白项与重复项都要清掉
      expect(joined(normalizeTagInput('', [' 工作 ', '工作', '', '  ']))).assertEqual('工作');
      // 已有标签超出上限时只留前 MAX_LOG_TAGS 个
      expect(joined(normalizeTagInput('d', ['a', 'b', 'c', 'e']))).assertEqual('a|b|c');
    });

    // ---------------- collectTags ----------------

    it('empty_input_returns_empty', 0, () => {
      expect(collectTags([]).length).assertEqual(0);
      expect(collectTags([makeLog('2026-10-01', [], true)]).length).assertEqual(0);
    });

    it('orders_by_count_desc_then_name_asc', 0, () => {
      const logs: DailyLog[] = [
        makeLog('2026-10-03', ['a', 'b'], true),
        makeLog('2026-10-02', ['b', 'c'], true),
        makeLog('2026-10-01', ['b'], true)
      ];
      const tags: TagCount[] = collectTags(logs);
      // b 出现 3 次；a 与 c 各 1 次，按名称升序 → a 在前
      expect(names(tags)).assertEqual('b|a|c');
      expect(counts(tags)).assertEqual('3|1|1');
    });

    it('same_count_is_sorted_by_name', 0, () => {
      const logs: DailyLog[] = [
        makeLog('2026-10-02', ['读书'], true),
        makeLog('2026-10-01', ['工作'], true)
      ];
      const tags: TagCount[] = collectTags(logs);
      expect(names(tags)).assertEqual('工作|读书');
      expect(counts(tags)).assertEqual('1|1');
    });

    it('skips_plan_stubs', 0, () => {
      const logs: DailyLog[] = [
        makeLog('2026-10-02', ['工作'], true),
        // 计划存根（hasEntry = false）不算真正的记录
        makeLog('2026-10-03', ['计划'], false)
      ];
      const tags: TagCount[] = collectTags(logs);
      expect(tags.length).assertEqual(1);
      expect(names(tags)).assertEqual('工作');
      expect(counts(tags)).assertEqual('1');
    });

    it('counts_a_tag_once_per_log', 0, () => {
      const logs: DailyLog[] = [makeLog('2026-10-01', ['工作', '工作'], true)];
      const tags: TagCount[] = collectTags(logs);
      expect(tags.length).assertEqual(1);
      expect(counts(tags)).assertEqual('1');
    });

    it('collect_trims_dirty_names', 0, () => {
      const logs: DailyLog[] = [makeLog('2026-10-01', [' 工作 ', '读书'], true)];
      const tags: TagCount[] = collectTags(logs);
      expect(names(tags)).assertEqual('工作|读书');
      expect(counts(tags)).assertEqual('1|1');
    });

    // ---------------- filterByTag / hasTag ----------------

    it('filters_matching_logs_and_keeps_order', 0, () => {
      const logs: DailyLog[] = [
        makeLog('2026-10-03', ['工作', '读书'], true),
        makeLog('2026-10-02', ['运动'], true),
        makeLog('2026-10-01', ['工作'], true)
      ];
      const hit: DailyLog[] = filterByTag(logs, '工作');
      expect(hit.length).assertEqual(2);
      expect(hit[0].date).assertEqual('2026-10-03');
      expect(hit[1].date).assertEqual('2026-10-01');
    });

    it('filter_without_match_returns_empty', 0, () => {
      const logs: DailyLog[] = [makeLog('2026-10-01', ['工作'], true)];
      expect(filterByTag(logs, '旅行').length).assertEqual(0);
      expect(filterByTag(logs, '').length).assertEqual(0);
    });

    it('matches_exactly_not_by_prefix', 0, () => {
      const log: DailyLog = makeLog('2026-10-01', ['工作复盘'], true);
      expect(filterByTag([log], '工作').length).assertEqual(0);
      expect(filterByTag([log], '工作复盘').length).assertEqual(1);
    });

    it('has_tag_hit_and_miss', 0, () => {
      const log: DailyLog = makeLog('2026-10-01', ['工作', '读书'], true);
      expect(hasTag(log, '工作')).assertTrue();
      expect(hasTag(log, '  读书  ')).assertTrue();
      expect(hasTag(log, '工作复盘')).assertFalse();
      expect(hasTag(log, '')).assertFalse();
      expect(hasTag(makeLog('2026-10-01', [], true), '工作')).assertFalse();
    });

    // ---------------- serializeTags / parseTags ----------------

    it('serialize_and_parse_round_trip', 0, () => {
      const tags: string[] = ['工作', '读书', '运动'];
      const restored: string[] = parseTags(serializeTags(tags));
      expect(restored.length).assertEqual(3);
      expect(joined(restored)).assertEqual(joined(tags));
    });

    it('empty_list_serializes_to_empty_string', 0, () => {
      expect(serializeTags([])).assertEqual('');
      expect(parseTags('').length).assertEqual(0);
    });

    it('parse_drops_dirty_items', 0, () => {
      const restored: string[] = parseTags('["工作","",3,"  ","读书",null]');
      expect(restored.length).assertEqual(2);
      expect(joined(restored)).assertEqual('工作|读书');
    });

    it('parse_broken_text_returns_empty', 0, () => {
      expect(parseTags('不是 JSON').length).assertEqual(0);
      expect(parseTags('{"a":1}').length).assertEqual(0);
    });
  });
}
