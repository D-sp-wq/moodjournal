import { describe, it, expect } from '@ohos/hypium';
import {
  MAX_LOG_PHOTOS,
  parsePhotoUris,
  remainingPhotoSlots,
  serializePhotoUris
} from '../main/ets/models/DailyLog';

export default function logPhotoTest() {
  describe('LogPhoto', () => {
    it('round_trip', 0, () => {
      const list: string[] = ['file:///a/b.jpg', 'file:///a/c.png'];
      expect(parsePhotoUris(serializePhotoUris(list))).assertDeepEquals(list);
    });

    it('empty_list_stores_empty_string', 0, () => {
      expect(serializePhotoUris([])).assertEqual('');
      expect(parsePhotoUris('').length).assertEqual(0);
    });

    it('bad_data_falls_back_to_empty', 0, () => {
      expect(parsePhotoUris('not json').length).assertEqual(0);
      expect(parsePhotoUris('{"a":1}').length).assertEqual(0);
      expect(parsePhotoUris('123').length).assertEqual(0);
      expect(parsePhotoUris('null').length).assertEqual(0);
    });

    it('filters_non_string_items', 0, () => {
      const parsed: string[] = parsePhotoUris('["a",1,"","b"]');
      expect(parsed.length).assertEqual(2);
      expect(parsed[0]).assertEqual('a');
      expect(parsed[1]).assertEqual('b');
    });

    it('keeps_special_characters', 0, () => {
      // URI 里可能出现逗号、竖线等分隔符，用 JSON 存取不会被拆坏
      const list: string[] = ['file:///data/a,b|c.jpg'];
      expect(parsePhotoUris(serializePhotoUris(list))[0]).assertEqual('file:///data/a,b|c.jpg');
    });

    it('remaining_slots', 0, () => {
      expect(MAX_LOG_PHOTOS).assertEqual(3);
      expect(remainingPhotoSlots(0)).assertEqual(3);
      expect(remainingPhotoSlots(2)).assertEqual(1);
      expect(remainingPhotoSlots(3)).assertEqual(0);
      expect(remainingPhotoSlots(4)).assertEqual(0);
    });
  });
}
