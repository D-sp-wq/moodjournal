import { describe, it, expect } from '@ohos/hypium';
import {
  ANNIVERSARY_ADVANCE_OPTIONS,
  DEFAULT_ANNIVERSARY_ADVANCE_DAYS,
  ReminderKind,
  buildWantAgentParams,
  anniversaryReminderText,
  kindFromParam,
  normalizeAdvanceDays,
  pageForReminder,
  reminderDateFor,
  routeParamValue,
  shouldScheduleAt,
  ROUTE_PARAM_KEY
} from '../main/ets/models/ReminderRoute';

/**
 * 提醒路由与「重要日子提前提醒」的纯函数用例。
 * 全部与系统时间无关：需要"当前时间"的地方都由参数传入。
 */
export default function reminderRouteTest() {
  describe('ReminderRoute', () => {
    // ---------- 通知点击的落地页 ----------

    it('page_for_daily_record', 0, () => {
      expect(pageForReminder(ReminderKind.DAILY_RECORD)).assertEqual('pages/RecordPage');
    });

    it('page_for_today_plan', 0, () => {
      expect(pageForReminder(ReminderKind.TODAY_PLAN)).assertEqual('pages/HomePage');
    });

    it('page_for_habit', 0, () => {
      expect(pageForReminder(ReminderKind.HABIT)).assertEqual('pages/HabitPage');
    });

    it('page_for_anniversary', 0, () => {
      expect(pageForReminder(ReminderKind.ANNIVERSARY)).assertEqual('pages/AnniversaryPage');
    });

    it('route_param_round_trip', 0, () => {
      // 四种提醒的参数值都是稳定字符串，改一个字都会让已排期的通知找不到页面
      expect(routeParamValue(ReminderKind.DAILY_RECORD)).assertEqual('record');
      expect(routeParamValue(ReminderKind.TODAY_PLAN)).assertEqual('plan');
      expect(routeParamValue(ReminderKind.HABIT)).assertEqual('habit');
      expect(routeParamValue(ReminderKind.ANNIVERSARY)).assertEqual('anniversary');

      // 往返：kind → 参数 → kind 必须还原
      expect(kindFromParam(routeParamValue(ReminderKind.DAILY_RECORD))).assertEqual(ReminderKind.DAILY_RECORD);
      expect(kindFromParam(routeParamValue(ReminderKind.TODAY_PLAN))).assertEqual(ReminderKind.TODAY_PLAN);
      expect(kindFromParam(routeParamValue(ReminderKind.HABIT))).assertEqual(ReminderKind.HABIT);
      expect(kindFromParam(routeParamValue(ReminderKind.ANNIVERSARY))).assertEqual(ReminderKind.ANNIVERSARY);
    });

    it('kind_from_unknown_returns_null', 0, () => {
      // 未知取值（空串、拼错、大小写不对、误把路由当参数）一律 null
      expect(kindFromParam('') === null).assertTrue();
      expect(kindFromParam('unknown') === null).assertTrue();
      expect(kindFromParam('Record') === null).assertTrue();
      expect(kindFromParam('pages/RecordPage') === null).assertTrue();
    });

    it('want_agent_params_carry_target', 0, () => {
      const params: Record<string, string> = buildWantAgentParams(ReminderKind.HABIT);
      expect(ROUTE_PARAM_KEY).assertEqual('target');
      expect(params[ROUTE_PARAM_KEY]).assertEqual('habit');
      // 三种其它提醒也各自带上正确的值
      expect(buildWantAgentParams(ReminderKind.DAILY_RECORD)[ROUTE_PARAM_KEY]).assertEqual('record');
      expect(buildWantAgentParams(ReminderKind.TODAY_PLAN)[ROUTE_PARAM_KEY]).assertEqual('plan');
      expect(buildWantAgentParams(ReminderKind.ANNIVERSARY)[ROUTE_PARAM_KEY]).assertEqual('anniversary');
    });

    // ---------- 提前提醒的日期 ----------

    it('reminder_date_advance_zero_is_same_day', 0, () => {
      expect(reminderDateFor('2026-05-20', 0)).assertEqual('2026-05-20');
    });

    it('reminder_date_advance_one_day', 0, () => {
      expect(reminderDateFor('2026-05-20', 1)).assertEqual('2026-05-19');
    });

    it('reminder_date_advance_three_days', 0, () => {
      expect(reminderDateFor('2026-05-20', 3)).assertEqual('2026-05-17');
    });

    it('reminder_date_cross_month', 0, () => {
      // 3 月 1 日提前 1 天 → 2 月 28 日（平年）
      expect(reminderDateFor('2026-03-01', 1)).assertEqual('2026-02-28');
      // 闰年 3 月 1 日提前 1 天 → 2 月 29 日
      expect(reminderDateFor('2024-03-01', 1)).assertEqual('2024-02-29');
      // 提前 3 天跨月
      expect(reminderDateFor('2026-03-02', 3)).assertEqual('2026-02-27');
    });

    it('reminder_date_cross_year', 0, () => {
      // 元旦提前 1 天 → 上一年最后一天
      expect(reminderDateFor('2026-01-01', 1)).assertEqual('2025-12-31');
      // 提前 3 天跨年
      expect(reminderDateFor('2026-01-01', 3)).assertEqual('2025-12-29');
    });

    // ---------- 提前提醒的文案 ----------

    it('reminder_text_today', 0, () => {
      expect(anniversaryReminderText('第一次旅行', 0)).assertEqual('今天是「第一次旅行」');
    });

    it('reminder_text_tomorrow', 0, () => {
      expect(anniversaryReminderText('第一次旅行', 1)).assertEqual('明天是「第一次旅行」');
    });

    it('reminder_text_custom_days', 0, () => {
      expect(anniversaryReminderText('第一次旅行', 3)).assertEqual('还有 3 天是「第一次旅行」');
      expect(anniversaryReminderText('生日', 7)).assertEqual('还有 7 天是「生日」');
      // 负数按"就是今天"兜底，不出现「还有 -1 天」
      expect(anniversaryReminderText('生日', -1)).assertEqual('今天是「生日」');
    });

    // ---------- 提醒时刻是否已过 ----------

    it('should_schedule_future_true', 0, () => {
      // 当前 5-19 08:00，提醒在 5-20 09:00 → 还没到，排
      expect(shouldScheduleAt('2026-05-20', 9, 0, new Date(2026, 4, 19, 8, 0, 0))).assertTrue();
      // 同一天更早的时刻也算未来
      expect(shouldScheduleAt('2026-05-20', 9, 0, new Date(2026, 4, 20, 8, 59, 59))).assertTrue();
    });

    it('should_schedule_past_false', 0, () => {
      // 已经过了 09:00 → 不补弹
      expect(shouldScheduleAt('2026-05-20', 9, 0, new Date(2026, 4, 20, 10, 0, 0))).assertFalse();
      // 正好到点也视为已过（避免立刻弹一条）
      expect(shouldScheduleAt('2026-05-20', 9, 0, new Date(2026, 4, 20, 9, 0, 0))).assertFalse();
      // 提醒日是昨天 → 已过
      expect(shouldScheduleAt('2026-05-19', 9, 0, new Date(2026, 4, 20, 8, 0, 0))).assertFalse();
    });

    it('should_schedule_invalid_date_false', 0, () => {
      expect(shouldScheduleAt('', 9, 0, new Date(2026, 4, 19, 8, 0, 0))).assertFalse();
      expect(shouldScheduleAt('2026-13-45', 9, 0, new Date(2026, 4, 19, 8, 0, 0))).assertFalse();
    });

    // ---------- 提前天数的归一 ----------

    it('normalize_advance_days', 0, () => {
      expect(ANNIVERSARY_ADVANCE_OPTIONS.length).assertEqual(3);
      expect(DEFAULT_ANNIVERSARY_ADVANCE_DAYS).assertEqual(1);
      // 合法值原样保留
      expect(normalizeAdvanceDays(0)).assertEqual(0);
      expect(normalizeAdvanceDays(1)).assertEqual(1);
      expect(normalizeAdvanceDays(3)).assertEqual(3);
      // 越界 / 非法值一律归到默认 1 天
      expect(normalizeAdvanceDays(2)).assertEqual(1);
      expect(normalizeAdvanceDays(30)).assertEqual(1);
      expect(normalizeAdvanceDays(-1)).assertEqual(1);
    });
  });
}
