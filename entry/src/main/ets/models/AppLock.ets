/**
 * 应用锁的纯函数部分：PIN 校验、SHA-256 摘要、重新锁定判定。
 *
 * 为什么自己实现 SHA-256 而不用 `@ohos.security.cryptoFramework`：
 * 系统 Md 是异步 API，在本地单元测试环境里不可用，会导致"摘要一致性"这类
 * 关键用例无法覆盖。这里用纯 ArkTS 实现，可被测试直接验证
 * （用例里断言 SHA-256("abc") 等于标准测试向量，保证实现正确）。
 *
 * 安全边界（要如实理解）：
 * 只存 `SHA-256(盐 + 密码)`，明文永不落盘；盐每次设置密码时重新随机生成。
 * 4 位数字只有 1 万种组合，这道锁防的是"手机被别人拿起来随手翻"，
 * 不防拿到设备后做取证分析的人 —— 那是本地应用无法解决的，各家日记应用同理。
 */

/** 密码位数 */
export const PIN_LENGTH: number = 4;
/** 连续输错多少次后给出「忘记密码」提示 */
export const ATTEMPTS_BEFORE_HINT: number = 5;
/** 宽限期选项（分钟），0 表示立即锁定 */
export const GRACE_OPTIONS: number[] = [0, 1, 5];
/** 默认宽限期 */
export const DEFAULT_GRACE_MINUTES: number = 1;

/** 密码必须是 PIN_LENGTH 位纯数字 */
export function isValidPin(pin: string): boolean {
  if (pin.length !== PIN_LENGTH) {
    return false;
  }
  for (let i: number = 0; i < pin.length; i++) {
    const code: number = pin.charCodeAt(i);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}

/** 只保留数字字符，并截断到 PIN_LENGTH 位（输入过程用） */
export function sanitizePinInput(text: string): string {
  let out: string = '';
  for (let i: number = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    if (code >= 48 && code <= 57) {
      out += text.charAt(i);
    }
    if (out.length >= PIN_LENGTH) {
      break;
    }
  }
  return out;
}

/** UTF-8 编码 */
function utf8Bytes(text: string): number[] {
  const out: number[] = [];
  for (let i: number = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    if (code < 0x80) {
      out.push(code);
    } else if (code < 0x800) {
      out.push(0xc0 | (code >> 6));
      out.push(0x80 | (code & 0x3f));
    } else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
      const next: number = text.charCodeAt(i + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        const cp: number = 0x10000 + ((code - 0xd800) << 10) + (next - 0xdc00);
        out.push(0xf0 | (cp >> 18));
        out.push(0x80 | ((cp >> 12) & 0x3f));
        out.push(0x80 | ((cp >> 6) & 0x3f));
        out.push(0x80 | (cp & 0x3f));
        i++;
      } else {
        out.push(0xef);
        out.push(0xbf);
        out.push(0xbd);
      }
    } else {
      out.push(0xe0 | (code >> 12));
      out.push(0x80 | ((code >> 6) & 0x3f));
      out.push(0x80 | (code & 0x3f));
    }
  }
  return out;
}

const SHA256_K: number[] = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

function rotr(x: number, n: number): number {
  return ((x >>> n) | (x << (32 - n))) >>> 0;
}

function toHex8(value: number): string {
  const hex: string = (value >>> 0).toString(16);
  let out: string = hex;
  while (out.length < 8) {
    out = `0${out}`;
  }
  return out;
}

/** 纯 ArkTS 实现的 SHA-256，返回 64 位小写十六进制 */
export function sha256Hex(text: string): string {
  const bytes: number[] = utf8Bytes(text);
  const bitLength: number = bytes.length * 8;

  bytes.push(0x80);
  while (bytes.length % 64 !== 56) {
    bytes.push(0);
  }
  // 64 位长度（高 32 位在实际输入下为 0）
  const hi: number = Math.floor(bitLength / 4294967296);
  for (let i: number = 3; i >= 0; i--) {
    bytes.push((hi >>> (i * 8)) & 0xff);
  }
  for (let i: number = 3; i >= 0; i--) {
    bytes.push((bitLength >>> (i * 8)) & 0xff);
  }

  const h: number[] = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
  ];
  const w: number[] = [];
  for (let i: number = 0; i < 64; i++) {
    w.push(0);
  }

  const total: number = bytes.length;
  for (let offset: number = 0; offset < total; offset += 64) {
    for (let i: number = 0; i < 16; i++) {
      const p: number = offset + i * 4;
      w[i] = ((bytes[p] << 24) | (bytes[p + 1] << 16) | (bytes[p + 2] << 8) | bytes[p + 3]) >>> 0;
    }
    for (let i: number = 16; i < 64; i++) {
      const s0: number = (rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3)) >>> 0;
      const s1: number = (rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10)) >>> 0;
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }

    let a: number = h[0];
    let b: number = h[1];
    let c: number = h[2];
    let d: number = h[3];
    let e: number = h[4];
    let f: number = h[5];
    let g: number = h[6];
    let hh: number = h[7];

    for (let i: number = 0; i < 64; i++) {
      const s1: number = (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) >>> 0;
      const ch: number = ((e & f) ^ ((~e) & g)) >>> 0;
      const temp1: number = (hh + s1 + ch + SHA256_K[i] + w[i]) >>> 0;
      const s0: number = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) >>> 0;
      const maj: number = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
      const temp2: number = (s0 + maj) >>> 0;

      hh = g;
      g = f;
      f = e;
      e = (d + temp1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) >>> 0;
    }

    h[0] = (h[0] + a) >>> 0;
    h[1] = (h[1] + b) >>> 0;
    h[2] = (h[2] + c) >>> 0;
    h[3] = (h[3] + d) >>> 0;
    h[4] = (h[4] + e) >>> 0;
    h[5] = (h[5] + f) >>> 0;
    h[6] = (h[6] + g) >>> 0;
    h[7] = (h[7] + hh) >>> 0;
  }

  let out: string = '';
  for (let i: number = 0; i < 8; i++) {
    out += toHex8(h[i]);
  }
  return out;
}

/** 密码摘要 = SHA-256(盐 + ':' + 密码) */
export function hashPin(salt: string, pin: string): string {
  return sha256Hex(`${salt}:${pin}`);
}

/**
 * 生成盐：只依赖传入的随机数（保持纯函数、可测试）。
 * 调用方用 Date.now() 与 Math.random() 提供两个互相独立的随机源。
 */
export function buildSalt(seed: number, extra: number): string {
  const a: string = Math.floor(Math.abs(seed)).toString(16);
  const b: string = Math.floor(Math.abs(extra) * 0xffffffff).toString(16);
  const merged: string = `${a}${b}${sha256Hex(`${a}-${b}`)}`;
  return merged.slice(0, 32);
}

/** 密码是否可信：盐与摘要都非空且格式正常 */
export function hasCredential(salt: string, hash: string): boolean {
  return salt.trim().length > 0 && hash.trim().length === 64;
}

/** 宽限期文案 */
export function graceLabel(minutes: number): string {
  if (minutes <= 0) {
    return '立即';
  }
  if (minutes === 1) {
    return '1 分钟';
  }
  return `${minutes} 分钟`;
}

/**
 * 回到前台后是否需要重新验证。
 *
 * @param enabled 是否开启应用锁
 * @param credentialOk 是否已设置密码（盐+摘要齐全）
 * @param lastBackgroundAt 进入后台的时间戳；0 表示本次会话内还没进过后台
 * @param now 当前时间戳
 * @param graceMinutes 宽限期（分钟），0 表示立即
 */
export function shouldLockOnForeground(
  enabled: boolean,
  credentialOk: boolean,
  lastBackgroundAt: number,
  now: number,
  graceMinutes: number
): boolean {
  if (!enabled || !credentialOk) {
    return false;
  }
  if (lastBackgroundAt <= 0) {
    return false;
  }
  const away: number = now - lastBackgroundAt;
  if (away < 0) {
    // 系统时间被回拨：保守起见要求验证
    return true;
  }
  const grace: number = (graceMinutes > 0 ? graceMinutes : 0) * 60 * 1000;
  return away >= grace;
}

/** 输错若干次后的提示文案 */
export function attemptHintText(failCount: number): string {
  if (failCount <= 0) {
    return '';
  }
  if (failCount < ATTEMPTS_BEFORE_HINT) {
    return `密码错误，还可以再试 ${ATTEMPTS_BEFORE_HINT - failCount} 次`;
  }
  return '密码错误次数较多，可以点下方「忘记密码」查看处理方式';
}
