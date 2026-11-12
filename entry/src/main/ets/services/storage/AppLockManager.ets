import userAuth from '@ohos.userIAM.userAuth';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../../common/constants/Constants';
import {
  DEFAULT_GRACE_MINUTES,
  buildSalt,
  graceLabel,
  hasCredential,
  hashPin,
  isValidPin,
  shouldLockOnForeground
} from '../../models/AppLock';
import { SessionManager } from './SessionManager';

/**
 * 应用锁状态机。
 *
 * 它只回答一个问题：**现在要不要先验证密码**。
 * 判定规则（详见 models/AppLock.ts 的 shouldLockOnForeground）：
 * - 未开启或没设密码 → 永不拦
 * - 冷启动（进程被杀后重开）→ 一律拦：内存里的时间戳丢了，宁可多锁一次
 * - 应用内页面跳转 → 不拦（否则没法用）
 * - 切后台超过宽限期回来 → 拦
 *
 * 密码只存摘要（SHA-256 + 盐），明文不落盘。
 */
export class AppLockManager {
  private static instance: AppLockManager | undefined = undefined;

  /** 只尝试指纹与人脸；系统 PIN 不用 —— 解锁用的是应用自己的 4 位密码 */
  private static readonly BIOMETRIC_TYPES: userAuth.UserAuthType[] =
    [userAuth.UserAuthType.FINGERPRINT, userAuth.UserAuthType.FACE];

  /** 进入后台的时间戳；0 表示本次会话还没进过后台 */
  private lastBackgroundAt: number = 0;
  /** 冷启动后、或超宽限期后置为 true，验证通过后清掉 */
  private pending: boolean = false;
  private enabled: boolean = false;
  private salt: string = '';
  private hash: string = '';
  private graceMinutes: number = DEFAULT_GRACE_MINUTES;

  static getInstance(): AppLockManager {
    if (!AppLockManager.instance) {
      AppLockManager.instance = new AppLockManager();
    }
    return AppLockManager.instance;
  }

  /** 启动时读一次偏好；之后设置变更由设置页调用 setPin/disable 同步内存 */
  async load(): Promise<void> {
    const session: SessionManager = SessionManager.getInstance();
    try {
      this.enabled = await session.isLockEnabled();
      this.salt = await session.getLockSalt();
      this.hash = await session.getLockHash();
      this.graceMinutes = await session.getLockGraceMinutes();
    } catch (err) {
      // 读取失败一律按"未开启"处理，绝不让用户被自己锁在门外
      this.enabled = false;
      this.salt = '';
      this.hash = '';
    }
  }

  /** 是否已配置并开启（设置页展示状态用） */
  isOn(): boolean {
    return this.enabled && hasCredential(this.salt, this.hash);
  }

  getGraceMinutes(): number {
    return this.graceMinutes;
  }

  getGraceLabel(): string {
    return graceLabel(this.graceMinutes);
  }

  /** 冷启动：进程刚起来，内存时间戳无效，需要验证 */
  markColdStart(): void {
    if (this.isOn()) {
      this.pending = true;
    }
  }

  /** 进入后台 */
  onBackground(): void {
    this.lastBackgroundAt = Date.now();
  }

  /** 回到前台；超过宽限期则要求验证 */
  onForeground(): void {
    if (shouldLockOnForeground(this.enabled, hasCredential(this.salt, this.hash),
      this.lastBackgroundAt, Date.now(), this.graceMinutes)) {
      this.pending = true;
    }
    this.lastBackgroundAt = 0;
  }

  /** 当前是否处于"待解锁"状态 */
  needsUnlock(): boolean {
    return this.pending;
  }

  /** 验证通过后清除待解锁状态 */
  clearPending(): void {
    this.pending = false;
    this.lastBackgroundAt = 0;
  }

  /** 校验密码 */
  verify(pin: string): boolean {
    if (!this.isOn() || !isValidPin(pin)) {
      return false;
    }
    return hashPin(this.salt, pin) === this.hash;
  }

  /** 设置（或修改）密码并开启应用锁 */
  async setPin(pin: string): Promise<boolean> {
    if (!isValidPin(pin)) {
      return false;
    }
    const salt: string = buildSalt(Date.now(), Math.random());
    const hash: string = hashPin(salt, pin);
    try {
      await SessionManager.getInstance().setLockCredential(salt, hash, true);
    } catch (err) {
      return false;
    }
    this.salt = salt;
    this.hash = hash;
    this.enabled = true;
    this.pending = false;
    return true;
  }

  /** 关闭应用锁并清除密码 */
  async disable(): Promise<boolean> {
    try {
      await SessionManager.getInstance().clearLockCredential();
    } catch (err) {
      return false;
    }
    this.salt = '';
    this.hash = '';
    this.enabled = false;
    this.pending = false;
    return true;
  }

  /** 只切开关，不清密码（用于临时关闭/重新开启） */
  async setEnabled(enabled: boolean): Promise<boolean> {
    try {
      await SessionManager.getInstance().setLockEnabled(enabled);
    } catch (err) {
      return false;
    }
    this.enabled = enabled;
    if (!enabled) {
      this.pending = false;
    }
    return true;
  }

  async setGraceMinutes(minutes: number): Promise<boolean> {
    try {
      await SessionManager.getInstance().setLockGraceMinutes(minutes);
    } catch (err) {
      return false;
    }
    this.graceMinutes = minutes;
    return true;
  }

  // ---------------- 生物识别（指纹 / 人脸） ----------------

  /**
   * 设备上是否有"已录入"的指纹或人脸可用。
   *
   * `userAuth.getAvailableStatus` 是同步接口：查询成功即表示可用；
   * 抛错（未录入 12500010 / 不支持 12500005 / 无权限 201 等）表示不可用。
   * 两种生物识别只要有一种可用就返回 true。
   */
  async isBiometricAvailable(): Promise<boolean> {
    for (const authType of AppLockManager.BIOMETRIC_TYPES) {
      try {
        userAuth.getAvailableStatus(authType, userAuth.AuthTrustLevel.ATL2);
        return true;
      } catch (err) {
        // 这一种没录入或不支持，继续看下一种
      }
    }
    return false;
  }

  /**
   * 拉起系统生物识别验证。
   *
   * 只返回 true / false：成功 true；取消、超时、锁死、未录入、
   * 权限不足以及任何异常一律 false，绝不把异常抛给锁屏页 ——
   * 页面必须能安静地退回到 PIN 输入，不能因为认证组件出错就卡死。
   */
  async authWithBiometric(): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      let settled: boolean = false;
      const finish = (ok: boolean): void => {
        if (settled) {
          return;
        }
        settled = true;
        resolve(ok);
      };
      try {
        const authParam: userAuth.AuthParam = {
          challenge: new Uint8Array([]),
          authType: AppLockManager.BIOMETRIC_TYPES,
          // 应用登录属中等安全场景，ATL2 是各家生物识别都支持的水平
          authTrustLevel: userAuth.AuthTrustLevel.ATL2
        };
        const widgetParam: userAuth.WidgetParam = {
          title: '验证身份以解锁心情手记'
        };
        const instance: userAuth.UserAuthInstance = userAuth.getUserAuthInstance(authParam, widgetParam);
        const callback: userAuth.IAuthCallback = {
          onResult: (result: userAuth.UserAuthResult): void => {
            finish(result.result === userAuth.UserAuthResultCode.SUCCESS);
          }
        };
        instance.on('result', callback);
        instance.start();
      } catch (err) {
        hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG,
          '生物识别不可用: %{public}s', JSON.stringify(err));
        finish(false);
      }
    });
  }
}
