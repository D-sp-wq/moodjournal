/**
 * 统一结果封装，用于数据层返回成功/失败状态，避免抛出过多异常
 */
export class Result<T> {
  readonly success: boolean;
  readonly message: string;
  readonly data: T | null;

  constructor(success: boolean, message: string, data: T | null = null) {
    this.success = success;
    this.message = message;
    this.data = data;
  }

  static ok<T>(data: T): Result<T> {
    return new Result<T>(true, '', data);
  }

  static fail<T>(message: string): Result<T> {
    return new Result<T>(false, message, null);
  }
}
