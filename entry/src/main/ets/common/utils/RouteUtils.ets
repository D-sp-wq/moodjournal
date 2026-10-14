import { DateUtils } from './DateUtils';

/**
 * 跨页路由参数。
 *
 * 注意：ArkTS 不允许把对象字面量直接赋给 Object 类型的字段
 * （arkts-no-untyped-obj-literals），所以必须先声明接口再传。
 * date 声明为可选，便于表达"没带参数"的场景。
 */
export interface DateRouteParams {
  date?: string;
}

export const ROUTE_RECORD: string = 'pages/RecordPage';
export const ROUTE_LOG_DETAIL: string = 'pages/LogDetailPage';
export const ROUTE_DAY_PLAN: string = 'pages/DayPlanPage';

/**
 * 安全读取路由里的 date 参数。
 * 参数缺失、为空或非法日期时一律回退到今天，避免页面崩溃。
 */
export function readDateParam(raw: Object): string {
  const params: DateRouteParams = raw as DateRouteParams;
  if (params && params.date !== undefined && DateUtils.isValidDateStr(params.date)) {
    return params.date;
  }
  return DateUtils.today();
}

/** 构造一个带日期的路由参数对象 */
export function dateParams(date: string): DateRouteParams {
  const params: DateRouteParams = { date: date };
  return params;
}
