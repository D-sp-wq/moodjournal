/**
 * 服务卡片 UI：展示今天是否已记录与今日心情（用一个渐变色点表达，不使用 emoji）
 * 颜色使用资源引用与传入的 hex，卡片跟随系统深浅色（colorMode: auto）
 *
 * 整张卡片可点击：走 postCardAction 的 router 事件跳 EntryAbility，
 * params 里带 `target: 'record'`（与 models/ReminderRoute 的 ROUTE_PARAM_KEY 约定一致），
 * 由应用内同一套 pendingRoute 机制在解锁后落到记录页。
 */

/** 卡片 router 事件的参数（key 与 models/ReminderRoute.ROUTE_PARAM_KEY 一致） */
interface CardRouterParams {
  target: string;
}

/** postCardAction 的第二个参数：router 事件 */
interface CardRouterAction {
  action: string;
  abilityName: string;
  params: CardRouterParams;
}

/** 固定值：router 事件 / 目标记录页 */
const CARD_ACTION_ROUTER: string = 'router';
const CARD_TARGET_RECORD: string = 'record';

@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('date') date: string = '';
  @LocalStorageProp('status') status: string = '加载中…';
  @LocalStorageProp('moodLabel') moodLabel: string = '';
  @LocalStorageProp('moodStart') moodStart: string = '#FFC978';
  @LocalStorageProp('moodEnd') moodEnd: string = '#F0A13C';

  build() {
    Column() {
      Text(this.date)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
      Row() {
        if (this.moodLabel !== '') {
          Row()
            .width(14)
            .height(14)
            .borderRadius(7)
            .linearGradient({
              angle: 135,
              colors: [[this.moodStart, 0.0], [this.moodEnd, 1.0]]
            })
            .margin({ right: 6 })
        }
        Text(this.status)
          .fontSize(13)
          .fontColor(this.status === '今日已记录' ? $r('app.color.brand_primary') : $r('app.color.text_tertiary'))
      }
      .margin({ top: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.page_background'))
    // 卡片被点击：拉起 EntryAbility，并带上「去记录页」的目标参数
    .onClick(() => {
      const action: CardRouterAction = {
        action: CARD_ACTION_ROUTER,
        abilityName: 'EntryAbility',
        params: { target: CARD_TARGET_RECORD }
      };
      postCardAction(this, action);
    })
  }
}
