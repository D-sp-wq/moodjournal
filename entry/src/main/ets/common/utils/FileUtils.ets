import { fileIo } from '@kit.CoreFileKit';

/**
 * 文件写入工具：目录准备与拷贝到应用沙箱
 */
export class FileUtils {
  /** 确保目录存在（已存在时忽略异常） */
  static ensureDir(dir: string): void {
    try {
      fileIo.mkdirSync(dir);
    } catch (err) {
      // 目录已存在则忽略
    }
  }

  /**
   * 把 srcUri 拷贝到 dir/fileName，返回 'file://<绝对路径>'
   *
   * 关键修正：src 可能来自系统选图器，形如 `file://media/Photo/...` 的媒体库 URI。
   * fileIo.copyFile() 的 src 参数只接受「路径或文件描述符」（见 SDK 声明
   * `copyFile(src: string | number, ...)` 的注释：Path or FD of the file to copy），
   * 直接传媒体库 URI 会抛 13900020 Invalid argument，导致头像与相册功能全程静默失败。
   * 而 openSync() 的注释明确写着 “This API supports the use of a URI”，
   * 因此这里先 openSync 取到 fd，再按 fd 拷贝（异步拷贝，不阻塞 UI 线程）。
   */
  static async copyIntoDir(srcUri: string, dir: string, fileName: string): Promise<string> {
    FileUtils.ensureDir(dir);
    const destPath: string = `${dir}/${fileName}`;
    const srcFile = fileIo.openSync(srcUri, fileIo.OpenMode.READ_ONLY);
    try {
      const destFile = fileIo.openSync(
        destPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      try {
        await fileIo.copyFile(srcFile.fd, destFile.fd);
      } finally {
        fileIo.closeSync(destFile);
      }
    } finally {
      fileIo.closeSync(srcFile);
    }
    return `file://${destPath}`;
  }
}
