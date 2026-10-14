import { common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import FormExtensionAbility from '@ohos.app.form.FormExtensionAbility';
import formBindingData from '@ohos.app.form.formBindingData';
import formProvider from '@ohos.app.form.formProvider';
import { Constants } from '../common/constants/Constants';
import { DateUtils } from '../common/utils/DateUtils';
import { SessionManager } from '../services/storage/SessionManager';
import { Mood, getMoodOption, moodLabel } from '../models/DailyLog';

/**
 * 服务卡片扩展能力：展示今天是否已记录与今日心情。
 * 卡片在独立进程运行，只读取偏好存储，不访问数据库。
 */
export default class DateLogFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '卡片创建');
    return formBindingData.createFormBindingData({});
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '卡片转为常驻: %{public}s', formId);
  }

  onUpdateForm(formId: string): void {
    this.refreshAllForms(formId);
  }

  onRemoveForm(formId: string): void {
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '卡片移除: %{public}s', formId);
  }

  private async refreshAllForms(formId: string): Promise<void> {
    try {
      await SessionManager.getInstance().init(this.context as common.Context);
      const today: string = DateUtils.today();
      const lastLoggedDate: string = await SessionManager.getInstance().getLastLoggedDate();
      const logged: boolean = lastLoggedDate === today;

      let labelText: string = '';
      let moodStart: string = '';
      let moodEnd: string = '';
      if (logged) {
        const session = SessionManager.getInstance();
        const mood: number = await session.getTodayMood();
        const custom: string = await session.getTodayCustomMood();
        const option = getMoodOption(mood as Mood);
        labelText = moodLabel(mood as Mood, custom);
        moodStart = option.colorStart;
        moodEnd = option.colorEnd;
      }

      const bindingData: formBindingData.FormBindingData = formBindingData.createFormBindingData({
        'date': `${Number(today.slice(5, 7))}月${Number(today.slice(8, 10))}日`,
        'status': logged ? '今日已记录' : '还没记录今天',
        'moodLabel': labelText,
        'moodStart': moodStart,
        'moodEnd': moodEnd
      });
      await formProvider.updateForm(formId, bindingData);
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '刷新卡片失败: %{public}s', JSON.stringify(err));
    }
  }
}
