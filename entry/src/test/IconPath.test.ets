import { describe, it, expect } from '@ohos/hypium';
import { ICON_BASE, IconKind, scalePathCommands } from '../main/ets/components/Icons';

export default function iconPathTest() {
  describe('IconPath', () => {
    it('base_scale_keeps_geometry', 0, () => {
      expect(scalePathCommands('M3 11 L12 3', 1)).assertEqual('M 3 11 L 12 3');
    });

    it('scales_all_coordinates', 0, () => {
      expect(scalePathCommands('M3 11 L12 3', 2)).assertEqual('M 6 22 L 24 6');
    });

    it('keeps_arc_flags_and_rotation', 0, () => {
      // 顺序 rx ry rot largeArc sweep x y：只有 rx/ry 与终点坐标缩放
      expect(scalePathCommands('M12 4 A4 4 0 1 0 12 12', 2))
        .assertEqual('M 24 8 A 8 8 0 1 0 24 24');
    });

    it('handles_decimal_and_negative', 0, () => {
      expect(scalePathCommands('M0.5 -2 L-3 4', 2)).assertEqual('M 1 -4 L -6 8');
    });

    it('scales_cubic_control_points', 0, () => {
      expect(scalePathCommands('C1 2 3 4 5 6', 2)).assertEqual('C 2 4 6 8 10 12');
    });

    it('keeps_command_letters_without_numbers', 0, () => {
      expect(scalePathCommands('M1 2 Z', 2)).assertEqual('M 2 4 Z');
    });

    it('base_size_is_24', 0, () => {
      expect(ICON_BASE).assertEqual(24);
      expect(IconKind.HOME).assertEqual('home');
    });
  });
}
