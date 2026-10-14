import { describe, it, expect } from '@ohos/hypium';
import {
  ATTEMPTS_BEFORE_HINT,
  DEFAULT_GRACE_MINUTES,
  GRACE_OPTIONS,
  PIN_LENGTH,
  attemptHintText,
  buildSalt,
  graceLabel,
  hasCredential,
  hashPin,
  isValidPin,
  sanitizePinInput,
  sha256Hex,
  shouldLockOnForeground
} from '../main/ets/models/AppLock';

export default function appLockTest() {
  describe('AppLock', () => {
    // 用标准测试向量验证自实现的 SHA-256 —— 这条过了，摘要逻辑才可信
    it('sha256_matches_standard_vectors', 0, () => {
      expect(sha256Hex(''))
        .assertEqual('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(sha256Hex('abc'))
        .assertEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(sha256Hex('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'))
        .assertEqual('248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
    });

    it('sha256_handles_chinese_text', 0, () => {
      // 中文（多字节 UTF-8）也要稳定；这里断言长度与稳定性，不硬编码外部值
      const a: string = sha256Hex('心情手记');
      const b: string = sha256Hex('心情手记');
      expect(a.length).assertEqual(64);
      expect(a).assertEqual(b);
      expect(a === sha256Hex('心情手记 ')).assertFalse();
    });

    it('pin_format_validation', 0, () => {
      expect(PIN_LENGTH).assertEqual(4);
      expect(isValidPin('1234')).assertTrue();
      expect(isValidPin('0000')).assertTrue();
      expect(isValidPin('123')).assertFalse();
      expect(isValidPin('12345')).assertFalse();
      expect(isValidPin('12a4')).assertFalse();
      expect(isValidPin('')).assertFalse();
      expect(isValidPin('１２３４')).assertFalse();
    });

    it('sanitize_keeps_digits_and_truncates', 0, () => {
      expect(sanitizePinInput('12a4')).assertEqual('124');
      expect(sanitizePinInput('123456')).assertEqual('1234');
      expect(sanitizePinInput('abc')).assertEqual('');
    });

    it('same_pin_and_salt_gives_same_hash', 0, () => {
      const salt: string = 'abcdef0123456789';
      expect(hashPin(salt, '1234')).assertEqual(hashPin(salt, '1234'));
    });

    it('different_salt_gives_different_hash', 0, () => {
      expect(hashPin('salt-a', '1234') === hashPin('salt-b', '1234')).assertFalse();
    });

    it('different_pin_gives_different_hash', 0, () => {
      const salt: string = 'abcdef0123456789';
      expect(hashPin(salt, '1234') === hashPin(salt, '1235')).assertFalse();
    });

    it('hash_is_hex_of_64_chars', 0, () => {
      const hash: string = hashPin('salt', '1234');
      expect(hash.length).assertEqual(64);
      expect(/^[0-9a-f]{64}$/.test(hash)).assertTrue();
    });

    it('salt_is_stable_and_32_chars', 0, () => {
      const a: string = buildSalt(1000, 0.5);
      expect(a.length).assertEqual(32);
      expect(buildSalt(1000, 0.5)).assertEqual(a);
      expect(buildSalt(1001, 0.5) === a).assertFalse();
      expect(buildSalt(1000, 0.6) === a).assertFalse();
    });

    it('credential_requires_both_parts', 0, () => {
      expect(hasCredential('salt', hashPin('salt', '1234'))).assertTrue();
      expect(hasCredential('', hashPin('salt', '1234'))).assertFalse();
      expect(hasCredential('salt', '')).assertFalse();
      expect(hasCredential('salt', 'abc')).assertFalse();
    });

    it('grace_label', 0, () => {
      expect(graceLabel(0)).assertEqual('立即');
      expect(graceLabel(1)).assertEqual('1 分钟');
      expect(graceLabel(5)).assertEqual('5 分钟');
      expect(GRACE_OPTIONS.length).assertEqual(3);
      expect(DEFAULT_GRACE_MINUTES).assertEqual(1);
    });

    it('no_lock_when_disabled_or_without_credential', 0, () => {
      const hash: string = hashPin('salt', '1234');
      // 未开启
      expect(shouldLockOnForeground(false, true, 1000, 999999, 1)).assertFalse();
      // 没设密码
      expect(shouldLockOnForeground(true, false, 1000, 999999, 1)).assertFalse();
      expect(hash.length).assertEqual(64);
    });

    it('no_lock_when_never_backgrounded', 0, () => {
      // lastBackgroundAt = 0 表示本次会话内还没进过后台
      expect(shouldLockOnForeground(true, true, 0, 999999, 1)).assertFalse();
    });

    it('grace_period_respected', 0, () => {
      const base: number = 1000000;
      // 宽限 1 分钟：走了 30 秒不锁
      expect(shouldLockOnForeground(true, true, base, base + 30 * 1000, 1)).assertFalse();
      // 走了 61 秒要锁
      expect(shouldLockOnForeground(true, true, base, base + 61 * 1000, 1)).assertTrue();
    });

    it('immediate_mode_locks_any_return', 0, () => {
      const base: number = 1000000;
      expect(shouldLockOnForeground(true, true, base, base + 1, 0)).assertTrue();
      expect(shouldLockOnForeground(true, true, base, base, 0)).assertTrue();
    });

    it('five_minute_grace', 0, () => {
      const base: number = 1000000;
      expect(shouldLockOnForeground(true, true, base, base + 4 * 60 * 1000, 5)).assertFalse();
      expect(shouldLockOnForeground(true, true, base, base + 5 * 60 * 1000, 5)).assertTrue();
    });

    it('clock_rollback_locks_conservatively', 0, () => {
      // 系统时间被回拨：away 变负，保守要求验证
      expect(shouldLockOnForeground(true, true, 2000, 1000, 5)).assertTrue();
    });

    it('attempt_hint_text', 0, () => {
      expect(ATTEMPTS_BEFORE_HINT).assertEqual(5);
      expect(attemptHintText(0)).assertEqual('');
      expect(attemptHintText(1).indexOf('4 次') >= 0).assertTrue();
      expect(attemptHintText(4).indexOf('1 次') >= 0).assertTrue();
      expect(attemptHintText(5).indexOf('忘记密码') >= 0).assertTrue();
    });
  });
}
