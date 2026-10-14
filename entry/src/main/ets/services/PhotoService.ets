import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../common/constants/Constants';
import { DateUtils } from '../common/utils/DateUtils';
import { IdUtils } from '../common/utils/IdUtils';
import { PathUtils } from '../common/utils/PathUtils';
import { FileUtils } from '../common/utils/FileUtils';
import { Photo } from '../models/Photo';
import { RepositoryFactory } from './data/RepositoryFactory';

/**
 * 图片服务：相册页选图、头像选图、每日记录照片选图。
 *
 * 三条路径都把用户**主动选中**的图片拷进应用私有目录，之后再从相册删原图也不影响应用内显示。
 * 应用不申请相册读取权限——用的是系统选图组件。
 */
export class PhotoService {
  private static readonly MAX_PICK: number = 9;
  /** 拷贝后最长边超过这个值就等比压缩 */
  private static readonly MAX_EDGE: number = 1600;
  /** 重编码 JPEG 的质量 */
  private static readonly JPEG_QUALITY: number = 85;

  /** 从系统相册多选图片并保存到相册页，返回成功保存的数量 */
  static async pickAndSave(context: common.Context): Promise<number> {
    const uris: string[] = await PhotoService.pickPhotoUris(PhotoService.MAX_PICK);
    if (uris.length === 0) {
      return 0;
    }

    const dir: string = PhotoService.photosDir(context);
    const repo = RepositoryFactory.getRepository();
    let saved: number = 0;
    for (const srcUri of uris) {
      try {
        const id: string = IdUtils.generate('photo');
        const uri: string = await FileUtils.copyIntoDir(srcUri, dir, `${id}${PathUtils.extOf(srcUri)}`);
        const photo: Photo = {
          id: id,
          uri: uri,
          caption: '',
          date: DateUtils.today(),
          createdAt: Date.now()
        };
        await repo.addPhoto(photo);
        saved += 1;
      } catch (err) {
        hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '保存图片失败: %{public}s', JSON.stringify(err));
      }
    }

    if (saved === 0) {
      // 用户已选中图片但一张都没保存成功：必须抛出，否则调用方会当成"用户取消"而毫无提示
      throw new Error('所选图片均保存失败');
    }
    return saved;
  }

  /**
   * 从相册选一张作为头像，返回 file:// 路径。
   * 用户取消返回空串（调用方据此不做任何改变）。
   */
  static async pickAvatar(context: common.Context): Promise<string> {
    const uris: string[] = await PhotoService.pickPhotoUris(1);
    if (uris.length === 0) {
      return '';
    }
    const dir: string = `${context.filesDir}/avatar`;
    const name: string = `avatar_${Date.now()}${PathUtils.extOf(uris[0])}`;
    const copied: string = await FileUtils.copyIntoDir(uris[0], dir, name);
    const path: string = await PhotoService.shrinkToJpeg(PathUtils.stripFilePrefix(copied));
    return `file://${path}`;
  }

  /**
   * 为每日记录选照片（最多 remaining 张），返回拷进沙箱后的 file:// 路径列表。
   * 用户取消返回空数组；选中了但一张都没成功则抛错。
   */
  static async pickLogPhotos(context: common.Context, remaining: number): Promise<string[]> {
    const picked: string[] = await PhotoService.pickPhotoUris(remaining);
    if (picked.length === 0) {
      return [];
    }
    const dir: string = `${context.filesDir}/logs`;
    const saved: string[] = [];
    for (const srcUri of picked) {
      try {
        const name: string = `${IdUtils.generate('logphoto')}${PathUtils.extOf(srcUri)}`;
        const copied: string = await FileUtils.copyIntoDir(srcUri, dir, name);
        const path: string = await PhotoService.shrinkToJpeg(PathUtils.stripFilePrefix(copied));
        saved.push(`file://${path}`);
      } catch (err) {
        hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '保存记录照片失败: %{public}s', JSON.stringify(err));
      }
    }
    if (saved.length === 0) {
      throw new Error('所选照片均保存失败');
    }
    return saved;
  }

  /** 删除相册图片：先删数据库记录，再尽力清理沙箱文件 */
  static async deletePhoto(photo: Photo): Promise<void> {
    await RepositoryFactory.getRepository().deletePhoto(photo.id);
    PhotoService.removeFile(photo.uri);
  }

  /** 删除沙箱里的一个文件（file:// 路径或裸路径），失败只记日志，绝不抛错 */
  static removeFile(uri: string): void {
    if (uri === '') {
      return;
    }
    try {
      fileIo.unlinkSync(PathUtils.stripFilePrefix(uri));
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '删除图片文件失败: %{public}s', JSON.stringify(err));
    }
  }

  /** 打开系统选图组件，返回用户主动选中的原始 URI 列表；取消时为空数组 */
  private static async pickPhotoUris(maxNumber: number): Promise<string[]> {
    const photoPicker = new photoAccessHelper.PhotoViewPicker();
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = maxNumber > 0 ? maxNumber : 1;
    const result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(options);
    const uris: string[] = result.photoUris;
    if (!uris || uris.length === 0) {
      return [];
    }
    return uris;
  }

  /**
   * 尽力压缩：最长边超过 MAX_EDGE 就等比缩小，并统一重编码为 JPEG。
   * 成功时返回新的 .jpg 路径（并删掉压缩前的原文件）；任何一步失败都原样返回入参，绝不影响保存。
   */
  private static async shrinkToJpeg(srcPath: string): Promise<string> {
    try {
      const source = image.createImageSource(srcPath);
      try {
        const info: image.ImageInfo = await source.getImageInfo();
        const width: number = info.size.width;
        const height: number = info.size.height;
        const longest: number = width > height ? width : height;

        const pixelMap = await source.createPixelMap();
        try {
          if (longest > PhotoService.MAX_EDGE) {
            const ratio: number = PhotoService.MAX_EDGE / longest;
            await pixelMap.scale(ratio, ratio);
          }
          const packer = image.createImagePacker();
          try {
            const option: image.PackingOption = {
              format: 'image/jpeg',
              quality: PhotoService.JPEG_QUALITY
            };
            const bytes: ArrayBuffer = await packer.packing(pixelMap, option);
            const jpgPath: string = `${srcPath}.jpg`;
            const file = fileIo.openSync(
              jpgPath,
              fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
            );
            try {
              fileIo.writeSync(file.fd, bytes);
            } finally {
              fileIo.closeSync(file);
            }
            // 新文件已写好，再删压缩前的原图
            try {
              fileIo.unlinkSync(srcPath);
            } catch (err) {
              hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '删除压缩前原图失败: %{public}s',
                JSON.stringify(err));
            }
            return jpgPath;
          } finally {
            packer.release();
          }
        } finally {
          pixelMap.release();
        }
      } finally {
        source.release();
      }
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '压缩照片失败，保留原图: %{public}s', JSON.stringify(err));
      return srcPath;
    }
  }

  private static photosDir(context: common.Context): string {
    return `${context.filesDir}/photos`;
  }
}
