import { describe, it, expect } from '@ohos/hypium';
import { DateRouteParams, dateParams, readDateParam } from '../main/ets/common/utils/RouteUtils';
import { DateUtils } from '../main/ets/common/utils/DateUtils';

export default function routeUtilsTest() {
  describe('RouteUtils', () => {
    it('reads_valid_date_param', 0, () => {
      expect(readDateParam(dateParams('2026-10-08'))).assertEqual('2026-10-08');
      expect(readDateParam(dateParams('2024-02-29'))).assertEqual('2024-02-29');
    });

    it('falls_back_when_invalid_or_missing', 0, () => {
      const today: string = DateUtils.today();
      // 非法日期、越界月份、格式不对、空串，以及完全没带参数，都应回退到今天
      expect(readDateParam(dateParams('abc'))).assertEqual(today);
      expect(readDateParam(dateParams('2026-13-45'))).assertEqual(today);
      expect(readDateParam(dateParams('2026-10-8'))).assertEqual(today);
      expect(readDateParam(dateParams(''))).assertEqual(today);
      const empty: DateRouteParams = {};
      expect(readDateParam(empty)).assertEqual(today);
    });

    it('dateParams_builds_expected_object', 0, () => {
      const params: DateRouteParams = dateParams('2026-01-02');
      expect(params.date).assertEqual('2026-01-02');
    });
  });
}
