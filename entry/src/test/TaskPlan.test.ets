import { describe, it, expect } from '@ohos/hypium';
import { TaskPlan, TaskProgress, computeTaskProgress, clampPlannedDays } from '../main/ets/models/TaskPlan';

function plan(startDate: string, plannedDays: number): TaskPlan {
  return {
    id: 't1',
    title: '写完季度报告',
    startDate: startDate,
    plannedDays: plannedDays,
    completed: false,
    completedAt: 0,
    createdAt: 0
  };
}

export default function taskPlanTest() {
  describe('TaskPlan', () => {
    it('not_started', 0, () => {
      // 今天 10-08，任务 10-20 才开始，计划 5 天 → 10-24 完成
      const p: TaskProgress = computeTaskProgress(plan('2026-10-20', 5), '2026-10-08');
      expect(p.notStarted).assertTrue();
      expect(p.elapsedDays).assertEqual(0);
      expect(p.percent).assertEqual(0);
      expect(p.remainingDays).assertEqual(16);
      expect(p.targetDate).assertEqual('2026-10-24');
      expect(p.overdue).assertFalse();
    });

    it('in_progress', 0, () => {
      // 10-08 起 10 天 → 10-17 止；今天 10-11 是第 4 天
      const p: TaskProgress = computeTaskProgress(plan('2026-10-08', 10), '2026-10-11');
      expect(p.elapsedDays).assertEqual(4);
      expect(p.remainingDays).assertEqual(6);
      expect(p.percent).assertEqual(40);
      expect(p.overdue).assertFalse();
      expect(p.notStarted).assertFalse();
      expect(p.targetDate).assertEqual('2026-10-17');
    });

    it('due_today', 0, () => {
      const p: TaskProgress = computeTaskProgress(plan('2026-10-08', 10), '2026-10-17');
      expect(p.remainingDays).assertEqual(0);
      expect(p.elapsedDays).assertEqual(10);
      expect(p.percent).assertEqual(100);
      expect(p.overdue).assertFalse();
    });

    it('overdue', 0, () => {
      const p: TaskProgress = computeTaskProgress(plan('2026-10-08', 10), '2026-10-20');
      expect(p.remainingDays).assertEqual(-3);
      expect(p.overdue).assertTrue();
      expect(p.percent).assertEqual(100);
      // 已过天数不会超过计划天数
      expect(p.elapsedDays).assertEqual(10);
    });

    it('single_day_task', 0, () => {
      const onDay: TaskProgress = computeTaskProgress(plan('2026-10-08', 1), '2026-10-08');
      expect(onDay.targetDate).assertEqual('2026-10-08');
      expect(onDay.elapsedDays).assertEqual(1);
      expect(onDay.percent).assertEqual(100);
      expect(onDay.overdue).assertFalse();

      const nextDay: TaskProgress = computeTaskProgress(plan('2026-10-08', 1), '2026-10-09');
      expect(nextDay.overdue).assertTrue();
      expect(nextDay.remainingDays).assertEqual(-1);
    });

    it('clamp_illegal_days', 0, () => {
      expect(clampPlannedDays(0)).assertEqual(1);
      expect(clampPlannedDays(-3)).assertEqual(1);
      expect(clampPlannedDays(400)).assertEqual(365);
      expect(clampPlannedDays(7.8)).assertEqual(7);
      expect(clampPlannedDays(Number.NaN)).assertEqual(1);
      // 非法天数参与计算时按 1 天处理，不会出现除零
      const p: TaskProgress = computeTaskProgress(plan('2026-10-08', 0), '2026-10-08');
      expect(p.percent).assertEqual(100);
      expect(p.targetDate).assertEqual('2026-10-08');
    });

    it('completed_flag_not_in_pure_math', 0, () => {
      const done: TaskPlan = plan('2026-10-01', 5);
      done.completed = true;
      const p: TaskProgress = computeTaskProgress(done, '2026-10-20');
      // 纯函数只看日期；"已完成"由界面呈现
      expect(p.overdue).assertTrue();
    });
  });
}
