/**
 * 服务卡片 UI：展示今天是否已记录与今日心情（用一个渐变色点表达，不使用 emoji）
 * 颜色使用资源引用与传入的 hex，卡片跟随系统深浅色（colorMode: auto）
 */
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
  }
}
