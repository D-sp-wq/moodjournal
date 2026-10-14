# DateLog · AGC Cloud DB 云端接入指南

当前工程已内置**本地数据层**（`LocalRepository`，基于 `@ohos.data.relationalStore`），开箱即可在单台设备/模拟器上跑通全部 MVP 功能。

本地数据层只能在一台设备上工作。要实现**双人实时同步**（另一半也能看到你的打卡），需要接入 AGC Cloud DB。本指南给出完整步骤，并提供一个与现有 `Repository` 接口一致的 `CloudRepository` 实现模板。

> ⚠️ AGC 的 `agconnect-services.json`、对象类型、匿名认证必须在 AGC 控制台手动配置，无法用代码代替。接入时请以 [AGC Cloud DB HarmonyOS 文档](https://developer.huawei.com/consumer/cn/doc/AppGallery-connect-Guides/agc-clouddb-introduction) 与 DevEco Studio 生成的代码为准。

---

## 1. 前置条件

- 华为开发者账号，创建 AGC 项目。
- 项目包名必须与 `AppScope/app.json5` 中的 `com.datelog.couple` 一致（若要换包名，需同步修改 AGC 项目与 `agconnect-services.json`）。

## 2. AGC 控制台配置步骤

1. **创建项目**：AGC 控制台 → 创建项目 → 填入包名 `com.datelog.couple`。
2. **开通 Auth**：在「认证服务」中启用 **匿名认证**（用于生成稳定 userId）。
3. **开通 Cloud DB**：在「云数据库」中创建**存储区**（如 `datelog`），并按第 3 节创建 7 个对象类型。
4. **开通云函数**：在「云函数」中部署第 6 节的 `bindCouple` 函数（Node.js）。
5. **下载配置文件**：项目设置 → 下载 `agconnect-services.json`，放入 `entry/src/main/resources/rawfile/`。

## 3. Cloud DB 对象类型字段定义

在 AGC 控制台「云数据库 → 对象类型」中按如下字段创建（主键标 ⭐）：

### User
| 字段 | 类型 | 主键 | 说明 |
|---|---|---|---|
| id | String | ⭐ | 用户 ID（匿名认证 uid） |
| nickname | String | | 昵称 |
| avatar | String | | 头像 |
| gender | String | | 性别 |
| birthday | String | | 生日 yyyy-MM-dd |
| createdAt | Long | | 创建时间戳 |

### Couple
| 字段 | 类型 | 主键 | 说明 |
|---|---|---|---|
| id | String | ⭐ | 情侣关系 ID |
| userAId | String | | 一方用户 ID |
| userBId | String | | 另一方用户 ID |
| startDate | String | | 在一起日期 |
| status | String | | pending / active |
| createdAt | Long | | 创建时间戳 |

### Invite
| 字段 | 类型 | 主键 | 说明 |
|---|---|---|---|
| id | String | ⭐ | 邀请记录 ID |
| code | String | | 6 位邀请码 |
| creatorId | String | | 发起方用户 ID |
| coupleId | String | | 关联情侣关系 |
| expiresAt | Long | | 过期时间戳 |
| status | String | | pending / used / expired |

### CheckIn
| 字段 | 类型 | 主键 | 说明 |
|---|---|---|---|
| id | String | ⭐ | 打卡记录 ID |
| coupleId | String | | 情侣关系 ID |
| userId | String | | 打卡用户 ID |
| date | String | | 日期 yyyy-MM-dd |
| mood | Integer | | 心情枚举值 0-5 |
| note | String | | 备注 |
| createdAt | Long | | 创建时间戳 |

### Anniversary
| 字段 | 类型 | 主键 | 说明 |
|---|---|---|---|
| id | String | ⭐ | 纪念日 ID |
| coupleId | String | | 情侣关系 ID |
| title | String | | 名称 |
| type | String | | anniversary / birthday / festival |
| date | String | | 日期 yyyy-MM-dd |
| reminderEnabled | Boolean | | 是否提醒 |
| createdAt | Long | | 创建时间戳 |

### Photo
| 字段 | 类型 | 主键 | 说明 |
|---|---|---|---|
| id | String | ⭐ | 照片记录 ID |
| coupleId | String | | 情侣关系 ID |
| userId | String | | 上传用户 ID |
| uri | String | | 云存储文件地址（图片本体存 Cloud Storage） |
| caption | String | | 备注 |
| date | String | | 日期 yyyy-MM-dd |
| createdAt | Long | | 创建时间戳 |

> 相册图片：文件本体存 **AGC Cloud Storage**（非 Cloud DB），`Photo.uri` 只存云端文件地址；本地模式则拷贝到应用沙箱 `filesDir/photos/`。

### Achievement（成就解锁记录）
| 字段 | 类型 | 主键 | 说明 |
|---|---|---|---|
| id | String | ⭐ | 记录 ID |
| coupleId | String | | 情侣关系 ID |
| achievementId | String | | 成就 ID（如 `streak_7`、`together_365`） |
| unlockedAt | Long | | 首次解锁时间戳 |

> 成就定义与进度由端侧 `models/Achievement.ets` 依据打卡/纪念日/相册数据实时推导，**云端只需存首次解锁记录**；已解锁记录一旦存在即保持解锁（历史不回退）。

**权限规则**：MVP 阶段将对象类型权限设为「登录用户可读写」即可。

## 4. 添加 SDK 依赖与初始化

在 `entry/oh-package.json5` 的 `dependencies` 中增加（版本以 AGC 文档为准）：

```json5
{
  "dependencies": {
    "@hw-agconnect/cloud": "^1.0.0",
    "@hw-agconnect/auth": "^1.0.0",
    "@hw-agconnect/cloud-database": "^1.0.0",
    "@hw-agconnect/cloud-function": "^1.0.0"
  }
}
```

> ⚠️ **接入云端前必须补回联网权限**：为通过上架审核，本地版已在 `entry/src/main/module.json5` 的 `requestPermissions` 中**移除** `ohos.permission.INTERNET`（应用当时无任何联网功能）。启用 AGC 云数据库 / 云函数 / 云存储之前，请先把它加回：
>
> ```json5
> "requestPermissions": [
>   { "name": "ohos.permission.PUBLISH_AGENT_REMINDER" },
>   { "name": "ohos.permission.INTERNET" }
> ]
> ```
>
> 否则所有云端调用都会因缺少网络权限而失败。加回后「联网」已由云同步功能支撑，权限与功能匹配，审核可解释。

在 `EntryAbility.onCreate` 中初始化 AGC 与匿名登录：

```typescript
import { cloud } from '@hw-agconnect/cloud';
import { auth } from '@hw-agconnect/auth';

export default class EntryAbility extends UIAbility {
  onCreate(): void {
    cloud.initialize(this.context);
    // 匿名登录，获取稳定 userId（对应 CloudRepository 的 getUser/createUser）
    auth.signInAnonymously().catch((err) => {
      hilog.error(0x0000, 'DateLog', '匿名登录失败: %{public}s', JSON.stringify(err));
    });
  }
}
```

## 5. CloudRepository 实现模板

DevEco Studio 的「端云一体化」插件会根据 AGC 对象类型**生成模型类**（如 `user`、`couple`、`check_in`、`anniversary`）。将下面模板放入 `entry/src/main/ets/services/data/CloudRepository.ets`，替换其中的模型类名即可与现有 `Repository` 接口完全对齐。

```typescript
import { database, CloudDBZoneConfig, CloudDBZoneQuery } from '@hw-agconnect/cloud-database';
import { User } from '../../models/User';
import { Couple, CoupleStatus } from '../../models/Couple';
import { CheckIn } from '../../models/CheckIn';
import { Anniversary } from '../../models/Anniversary';
import { Photo } from '../../models/Photo';
import { AchievementUnlock } from '../../models/Achievement';
import { BindResult, Repository } from './Repository';
import { IdUtils } from '../../common/utils/IdUtils';

// 由端云一体化插件生成的模型类（示意，实际类名以生成为准）
// import { user } from '../model/user';
// import { couple } from '../model/couple';
// import { check_in } from '../model/check_in';
// import { anniversary } from '../model/anniversary';

export class CloudRepository implements Repository {
  private zone: CloudDBZoneConfig | undefined = undefined;

  private async getZone(): Promise<CloudDBZoneConfig> {
    if (!this.zone) {
      // 'datelog' 为 AGC 控制台创建的存储区名称
      this.zone = await database().openCloudDBZone(new CloudDBZoneConfig('datelog'));
    }
    return this.zone;
  }

  async getUser(userId: string): Promise<User | null> {
    // 用生成的模型类构造查询：
    // const query = CloudDBZoneQuery.where(user).equalTo('id', userId);
    // const result = await zone.executeQuery(query);
    // 映射回 models/User
    return null; // TODO: 用生成的模型类实现查询
  }

  async upsertUser(user: User): Promise<void> {
    // zone.executeUpsert(new user(...))
  }

  async createCoupleViaInvite(userId: string, startDate: string): Promise<BindResult> {
    // 建议调用云函数 bindCouple，保证一对一与邀请码唯一性
    // 云函数返回 { coupleId, inviteCode }
    const inviteCode: string = IdUtils.generateInviteCode();
    const couple: Couple = {
      id: IdUtils.generate('couple'),
      userAId: userId,
      userBId: '',
      startDate: startDate,
      status: CoupleStatus.PENDING,
      createdAt: Date.now()
    };
    // zone.executeUpsert(new couple(...))
    return { couple: couple, inviteCode: inviteCode };
  }

  async joinCoupleViaInvite(userId: string, code: string, startDate: string): Promise<Couple> {
    // 查询 Invite 表校验 code 有效性 → 填充 userBId → 更新 Couple 状态为 active
    const couple: Couple = {
      id: IdUtils.generate('couple'),
      userAId: userId,
      userBId: 'partner',
      startDate: startDate,
      status: CoupleStatus.ACTIVE,
      createdAt: Date.now()
    };
    return couple;
  }

  async getCouple(coupleId: string): Promise<Couple | null> {
    return null; // TODO
  }

  async getCheckIn(coupleId: string, userId: string, date: string): Promise<CheckIn | null> {
    return null; // TODO
  }

  async upsertCheckIn(checkIn: CheckIn): Promise<void> {
    // zone.executeUpsert(...)
  }

  async getCheckIns(coupleId: string): Promise<CheckIn[]> {
    return []; // TODO
  }

  async getAnniversaries(coupleId: string): Promise<Anniversary[]> {
    return []; // TODO
  }

  async upsertAnniversary(anniversary: Anniversary): Promise<void> {
    // zone.executeUpsert(...)
  }

  async deleteAnniversary(id: string): Promise<void> {
    // zone.executeDelete(...)
  }

  async getPhotos(coupleId: string): Promise<Photo[]> {
    return []; // TODO: 图片文件本体存 Cloud Storage，记录存 Cloud DB
  }

  async addPhoto(photo: Photo): Promise<void> {
    // zone.executeUpsert(...)
  }

  async deletePhoto(id: string): Promise<void> {
    // zone.executeDelete(...)
  }

  async getAchievementUnlocks(coupleId: string): Promise<AchievementUnlock[]> {
    return []; // TODO: 查询该情侣的成就解锁记录
  }

  async unlockAchievement(record: AchievementUnlock): Promise<void> {
    // zone.executeUpsert(...)
  }
}
```

## 6. 切换数据层

修改 `entry/src/main/ets/services/data/RepositoryFactory.ets`：

```typescript
import { CloudRepository } from './CloudRepository';

export class RepositoryFactory {
  static getRepository(): Repository {
    if (!RepositoryFactory.repository) {
      // 接入 AGC 后，将 LocalRepository 替换为 CloudRepository
      RepositoryFactory.repository = new CloudRepository();
    }
    return RepositoryFactory.repository;
  }
}
```

## 7. bindCouple 云函数（Node.js，可选但推荐）

用云函数保证绑定事务的原子性与邀请码唯一性：

```javascript
const cloudFunction = require('@hw-agconnect/cloud-function');

exports.bindCouple = async (event, context) => {
  const { userId, code } = event;
  // 1. 若 code 存在：校验未过期、未使用，填充 Couple.userBId，置为 active
  // 2. 若 code 为空：生成唯一 6 位邀请码，创建 Couple(status=pending) 与 Invite 记录
  // 返回 { coupleId, inviteCode }
  return { coupleId: 'xxx', inviteCode: '123456' };
};
```

## 8. 注意事项

- **数据同步**：Cloud DB 写入后另一方设备通过查询或监听获得最新数据；`HomePage.onPageShow` 已每次拉取，接入后自然同步。
- **双人身份区分**：打卡记录通过 `userId` 区分「我」与「TA」，时间轴已按此渲染。
- **匿名认证**：匿名 uid 在清除应用数据前稳定；正式上线建议切换手机号/账号登录。
- **隐私**：敏感数据请在 AGC 控制台配置访问权限，正式环境考虑密钥库加密（见规范文档第 11 节）。
- **时区**：日期统一本地 `yyyy-MM-dd`，跨时区场景建议统一 UTC+8。
- **相册图片**：照片文件本体存 AGC Cloud Storage（`uri` 存云端文件地址），元数据存 Cloud DB 的 `Photo` 对象类型；本地模式则存应用沙箱 `filesDir/photos/`。

---

接入完成后，`Index` → `BindPage` 的邀请码流程即可实现真正的跨设备绑定与同步。
