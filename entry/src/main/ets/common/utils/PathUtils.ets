/**
 * 路径与文件名工具（纯函数，不依赖系统 API，便于单元测试）
 */
export class PathUtils {
  /** 从 URI 中提取扩展名（含点），无扩展名时返回 .jpg */
  static extOf(uri: string): string {
    const slash: number = uri.lastIndexOf('/');
    const dot: number = uri.lastIndexOf('.');
    if (dot > slash) {
      return uri.substring(dot);
    }
    return '.jpg';
  }

  /** 去掉 file:// 前缀，得到沙箱绝对路径；无前缀时原样返回 */
  static stripFilePrefix(uri: string): string {
    if (uri.startsWith('file://')) {
      return uri.substring(7);
    }
    return uri;
  }
}
