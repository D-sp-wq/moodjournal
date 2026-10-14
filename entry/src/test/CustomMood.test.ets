import { describe, it, expect } from '@ohos/hypium';
import {
  Mood,
  CUSTOM_MOOD_LABEL,
  CUSTOM_MOOD_COLOR_START,
  CUSTOM_MOOD_COLOR_END,
  MAX_CUSTOM_MOOD_LENGTH,
  moodColors,
  moodColorsByLabel,
  moodLabel,
  normalizeCustomMood
} from '../main/ets/models/DailyLog';

export default function customMoodTest() {
  describe('CustomMood', () => {
    it('normalize_trims_whitespace', 0, () => {
      expect(normalizeCustomMood('  元气满满 ')).assertEqual('元气满满');
      expect(normalizeCustomMood('有点想家')).assertEqual('有点想家');
    });

    it('normalize_blank_becomes_empty', 0, () => {
      expect(normalizeCustomMood('')).assertEqual('');
      expect(normalizeCustomMood('   ')).assertEqual('');
      expect(normalizeCustomMood('\n\t')).assertEqual('');
    });

    it('normalize_truncates_to_limit', 0, () => {
      const out: string = normalizeCustomMood('一二三四五六七八九十');
      expect(out.length).assertEqual(MAX_CUSTOM_MOOD_LENGTH);
      expect(out).assertEqual('一二三四五六七八');
    });

    it('label_uses_custom_text', 0, () => {
      expect(moodLabel(Mood.CUSTOM, '元气满满')).assertEqual('元气满满');
      // 带空格也要先清洗
      expect(moodLabel(Mood.CUSTOM, '  元气满满  ')).assertEqual('元气满满');
    });

    it('label_falls_back_when_blank', 0, () => {
      expect(moodLabel(Mood.CUSTOM, '')).assertEqual(CUSTOM_MOOD_LABEL);
      expect(moodLabel(Mood.CUSTOM, '   ')).assertEqual(CUSTOM_MOOD_LABEL);
    });

    it('label_ignores_custom_for_fixed_moods', 0, () => {
      expect(moodLabel(Mood.HAPPY, '元气满满')).assertEqual('开心');
      expect(moodLabel(Mood.SAD, '元气满满')).assertEqual('低落');
    });

    it('colors_of_custom_is_teal', 0, () => {
      const custom: string[] = moodColors(Mood.CUSTOM);
      expect(custom[0]).assertEqual(CUSTOM_MOOD_COLOR_START);
      expect(custom[1]).assertEqual(CUSTOM_MOOD_COLOR_END);
      // 固定心情仍然拿自己的暖色
      const happy: string[] = moodColors(Mood.HAPPY);
      expect(happy[0]).assertEqual('#FFC978');
      expect(happy[1]).assertEqual('#F0A13C');
    });

    it('colors_by_label_custom_differs_from_normal', 0, () => {
      const custom: string[] = moodColorsByLabel('元气满满');
      expect(custom[0]).assertEqual(CUSTOM_MOOD_COLOR_START);
      expect(custom[1]).assertEqual(CUSTOM_MOOD_COLOR_END);
      // 关键：自定义的配色不能和「平淡」的灰米撞色
      const normal: string[] = moodColorsByLabel('平淡');
      expect(custom[0] === normal[0]).assertFalse();
      // 内置标签仍按内置色
      const happy: string[] = moodColorsByLabel('开心');
      expect(happy[0]).assertEqual('#FFC978');
    });
  });
}
