import { describe, it, expect } from '@ohos/hypium';
import { PathUtils } from '../main/ets/common/utils/PathUtils';

export default function pathUtilsTest() {
  describe('PathUtils', () => {
    it('extOf', 0, () => {
      expect(PathUtils.extOf('file://media/Photo/10/IMG_1.jpg')).assertEqual('.jpg');
      expect(PathUtils.extOf('file://x/a.b.png')).assertEqual('.png');
      // 无扩展名 → 缺省 .jpg
      expect(PathUtils.extOf('file://x/noext')).assertEqual('.jpg');
      // 目录里有点但文件名没有 → 仍取缺省
      expect(PathUtils.extOf('file://a.b/file')).assertEqual('.jpg');
    });

    it('stripFilePrefix', 0, () => {
      expect(PathUtils.stripFilePrefix('file:///data/x')).assertEqual('/data/x');
      expect(PathUtils.stripFilePrefix('/data/x')).assertEqual('/data/x');
      expect(PathUtils.stripFilePrefix('')).assertEqual('');
    });
  });
}
