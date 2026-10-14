/**
 * 重要日子数据模型
 */
export class AnniversaryType {
  static readonly ANNIVERSARY: string = 'anniversary';
  static readonly BIRTHDAY: string = 'birthday';
  static readonly FESTIVAL: string = 'festival';
}

export interface Anniversary {
  id: string;
  title: string;
  type: string;
  date: string;
  reminderEnabled: boolean;
  createdAt: number;
}

/** 重要日子类型的中文标签 */
export function getAnniversaryTypeLabel(type: string): string {
  if (type === AnniversaryType.ANNIVERSARY) {
    return '重要日子';
  }
  if (type === AnniversaryType.BIRTHDAY) {
    return '生日';
  }
  if (type === AnniversaryType.FESTIVAL) {
    return '节日';
  }
  return '重要日子';
}
