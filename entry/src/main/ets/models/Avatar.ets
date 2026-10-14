/**
 * 头像模型：6 张内置头像（男 3 / 女 3）。
 *
 * 除内置头像外，用户也可以从系统相册里主动选一张作为头像（存在 SessionManager 的
 * avatarUri 偏好里，非空时优先显示）。内置头像作为「还没挑过照片」时的默认，
 * 素材由应用作者自备，经裁切与圆形蒙版处理后作为内置资源。
 */
export interface AvatarOption {
  id: string;
  label: string;
  /** 'male' | 'female' */
  gender: string;
  res: Resource;
}

export const AVATAR_OPTIONS: AvatarOption[] = [
  { id: 'm1', label: '男生 1', gender: 'male', res: $r('app.media.avatar_m1') },
  { id: 'm2', label: '男生 2', gender: 'male', res: $r('app.media.avatar_m2') },
  { id: 'm3', label: '男生 3', gender: 'male', res: $r('app.media.avatar_m3') },
  { id: 'f1', label: '女生 1', gender: 'female', res: $r('app.media.avatar_f1') },
  { id: 'f2', label: '女生 2', gender: 'female', res: $r('app.media.avatar_f2') },
  { id: 'f3', label: '女生 3', gender: 'female', res: $r('app.media.avatar_f3') }
];

export const DEFAULT_AVATAR_ID: string = 'm1';

/**
 * 按 id 取头像。
 * 找不到时**按性别回退**（f 开头回退到第一张女生、其余回退到第一张男生），
 * 避免旧记录里已不存在的 id 让使用者突然变成异性头像；始终不抛异常。
 */
export function findAvatar(id: string): AvatarOption {
  for (let i: number = 0; i < AVATAR_OPTIONS.length; i++) {
    if (AVATAR_OPTIONS[i].id === id) {
      return AVATAR_OPTIONS[i];
    }
  }
  const wantFemale: boolean = id.startsWith('f');
  for (let i: number = 0; i < AVATAR_OPTIONS.length; i++) {
    if (AVATAR_OPTIONS[i].gender === (wantFemale ? 'female' : 'male')) {
      return AVATAR_OPTIONS[i];
    }
  }
  return AVATAR_OPTIONS[0];
}
