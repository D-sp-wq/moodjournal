import { Repository } from './Repository';
import { LocalRepository } from './LocalRepository';

/**
 * 数据层工厂：全局唯一 Repository 实例。
 * 接入 AGC Cloud DB 后，将下面 new LocalRepository() 替换为 new CloudRepository()。
 */
export class RepositoryFactory {
  private static repository: Repository | undefined = undefined;

  static getRepository(): Repository {
    if (!RepositoryFactory.repository) {
      RepositoryFactory.repository = new LocalRepository();
    }
    return RepositoryFactory.repository;
  }
}
