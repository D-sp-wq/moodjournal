import { Constants } from '../common/constants/Constants';
import { Photo } from '../models/Photo';
import { SessionManager } from '../services/storage/SessionManager';
import { RepositoryFactory } from '../services/data/RepositoryFactory';
import { PhotoService } from '../services/PhotoService';
import { EmptyState } from '../components/EmptyState';
import { Icon, IconKind } from '../components/Icons';

/**
 * 相册页：网格浏览 + 全屏查看 + 添加/删除
 */
@Entry
@Component
struct AlbumPage {
  @State private photos: Photo[] = [];
  @State private isLoading: boolean = false;
  @State private viewerIndex: number = -1;

  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      this.photos = await RepositoryFactory.getRepository().getPhotos();
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '加载失败', duration: 2000 });
    }
  }

  private async handleAdd(): Promise<void> {
    this.isLoading = true;
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) {
        this.getUIContext().getPromptAction().showToast({ message: '无法获取上下文', duration: 2000 });
        return;
      }
      const count: number = await PhotoService.pickAndSave(context);
      if (count > 0) {
        this.getUIContext().getPromptAction().showToast({ message: `已添加 ${count} 张图片`, duration: 1500 });
        await this.load();
      }
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '选择图片失败', duration: 2000 });
    } finally {
      this.isLoading = false;
    }
  }

  private openViewer(index: number): void {
    this.viewerIndex = index;
  }

  private closeViewer(): void {
    this.viewerIndex = -1;
  }

  private prevPhoto(): void {
    if (this.viewerIndex > 0) {
      this.viewerIndex -= 1;
    }
  }

  private nextPhoto(): void {
    if (this.viewerIndex < this.photos.length - 1) {
      this.viewerIndex += 1;
    }
  }

  private handleDelete(photo: Photo): void {
    this.getUIContext().showAlertDialog({
      title: '删除照片',
      message: '确定删除这张照片吗？',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Constants.COLOR_PRIMARY,
        action: () => {
          this.doDelete(photo);
        }
      }
    });
  }

  private async doDelete(photo: Photo): Promise<void> {
    await PhotoService.deletePhoto(photo);
    await this.load();
    if (this.photos.length === 0) {
      this.viewerIndex = -1;
    } else if (this.viewerIndex >= this.photos.length) {
      this.viewerIndex = this.photos.length - 1;
    }
    this.getUIContext().getPromptAction().showToast({ message: '已删除', duration: 1500 });
  }

  @Builder
  private buildHeader() {
    Stack() {
      Text('记录里的照片')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Constants.COLOR_TEXT_PRIMARY)
      Row() {
        Stack() {
          Icon({ kind: IconKind.BACK, iconSize: 30, color: Constants.COLOR_TEXT_PRIMARY, strokeW: 2.4 })
        }
        .padding(12)
        .margin({ left: -6 })
        .onClick(() => {
          this.getUIContext().getRouter().back();
        })
        Blank()
        Text('添加')
          .fontSize(17)
          .fontColor(Constants.COLOR_PRIMARY)
          .enabled(!this.isLoading)
          .onClick(() => {
            this.handleAdd();
          })
      }
      .width('100%')
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  private buildGrid() {
    Column() {
      this.buildHeader()
      if (this.photos.length === 0) {
        EmptyState({
          kind: IconKind.PHOTO,
          title: '还没有照片',
          subtitle: '点击右上角，添加你们的第一张照片'
        })
      } else {
        Grid() {
          ForEach(this.photos, (photo: Photo, index: number) => {
            GridItem() {
              Image(photo.uri)
                .objectFit(ImageFit.Cover)
                .width('100%')
                .aspectRatio(1)
                .borderRadius(6)
                .onClick(() => {
                  this.openViewer(index);
                })
            }
          }, (photo: Photo) => photo.id)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(4)
        .rowsGap(4)
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Constants.COLOR_BACKGROUND)
  }

  @Builder
  private buildViewer() {
    Column() {
      Stack() {
        Image(this.photos[this.viewerIndex].uri)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
        Stack() {
          Icon({ kind: IconKind.CLOSE, iconSize: 30, color: Constants.COLOR_ON_BRAND })
        }
        .padding(12)
        .position({ right: 16, top: 16 })
        .onClick(() => {
          this.closeViewer();
        })
      }
      .width('100%')
      .layoutWeight(1)

      Column() {
        if (this.photos[this.viewerIndex].caption !== '') {
          Text(this.photos[this.viewerIndex].caption)
            .fontSize(16)
            .fontColor(Constants.COLOR_ON_BRAND)
            .margin({ bottom: 10 })
        }
        Row() {
          Stack() {
            Icon({ kind: IconKind.BACK, iconSize: 24, color: Constants.COLOR_ON_BRAND })
          }
            .onClick(() => {
              this.prevPhoto();
            })
          Text(`${this.viewerIndex + 1} / ${this.photos.length}`)
            .fontSize(16)
            .fontColor(Constants.COLOR_ON_BRAND)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Stack() {
            Icon({ kind: IconKind.CHEVRON, iconSize: 24, color: Constants.COLOR_ON_BRAND })
          }
            .onClick(() => {
              this.nextPhoto();
            })
          Stack() {
            Icon({ kind: IconKind.TRASH, iconSize: 24, color: Constants.COLOR_ON_BRAND })
          }
          .margin({ left: 20 })
          .onClick(() => {
            this.handleDelete(this.photos[this.viewerIndex]);
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }

  build() {
    if (this.viewerIndex >= 0) {
      this.buildViewer()
    } else {
      this.buildGrid()
    }
  }
}
