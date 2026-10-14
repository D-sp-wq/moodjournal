/**
 * ID 生成工具：本地模式下生成稳定唯一 ID
 */
export class IdUtils {
  /** 生成带前缀的唯一 ID，例如 user_1690000000000_123456 */
  static generate(prefix: string): string {
    const ts: number = Date.now();
    const rand: number = Math.floor(Math.random() * 1000000);
    return `${prefix}_${ts}_${rand}`;
  }

  /** 生成 6 位数字邀请码 */
  static generateInviteCode(): string {
    const code: number = Math.floor(100000 + Math.random() * 900000);
    return `${code}`;
  }
}
