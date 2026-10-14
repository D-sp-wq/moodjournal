# 心情手记 · 上架提交手册

> 目标：把当前工程变成可上传 AGC 的**已签名 App Pack（.app）**并完成上架。
> 工程侧改造已完成（文案、隐私政策、图标、头像、权限、包名、分类口径），本手册覆盖**账号操作 → 构建 → 提交 → 审核**全流程。

---

## 0. 当前状态

### 已完成（无需再做）

| 项 | 值 |
|---|---|
| 应用名 | **心情手记** |
| 包名 | `com.datelog.couple`（保持不变，包名不参与审核、用户不可见） |
| 版本 | `1.5.1` / versionCode `1000008` |
| 签名材料 | `%USERPROFILE%\.ohos\config\`：`datelog.p12`、`datelog-release.cer`、`datelog-release.p7b`（口令 `<签名口令：见本机私密文件 tools\signing.local.txt>`，别名 `datelog`） |
| 构建配置 | `build-profile.json5` 的签名口令已由 DevEco 加密写入，可直接命令行出签名包 |
| 内置头像 | 6 张（男 3 / 女 3），不读取相册 |
| 隐私政策 | v2.3，正文已改口径；**零网络权限、零采集** |
| 图标 | `docs/store/app-icon-square-1024.png`（**直角方图**，AGC 要的就是这个） |

### 待完成（本次上架必须做的 4 件事）

| # | 事项 | 说明 |
|---|---|---|
| 1 | **覆盖上传隐私政策到 OBS** | v2.3 改了「12 张头像 → 6 张」与「心情支持自定义」，URL 不变：`https://datelog-privacy.obs.cn-north-4.myhuaweicloud.com/index.html` |
| 2 | **重拍 5 张截图** | 必须是 9:16 或 16:9；AGC 默认选中「横向截图」，**必须切到「竖向截图」** |
| 3 | **AGC 改两项** | 应用名 →「心情手记」；分类与主标签 →「**工具**」 |
| 4 | **真机回归 4 点** | 见第 4.3 节 |

---

## 1. 前置：实名认证

1. 打开 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html) 登录华为开发者账号。
2. 完成**实名认证**（个人：身份证）。未实名**无法**创建应用与申请发布证书。
3. 已有实名账号 + 已有本应用项目的，直接跳到第 2 节。

---

## 2. AGC 项目与应用

1. AGC 控制台 → **我的项目** → 进入本应用所在项目。
2. 若尚未创建应用：**添加应用** → 平台 **HarmonyOS** → 包名 `com.datelog.couple`（必须与 `AppScope/app.json5` 的 `bundleName` **完全一致**）。
3. **本次必改两项**（上次被拒的直接原因）：
   - **应用名称**：`DateLog` → **`心情手记`**
   - **应用分类**：`生活服务` → **`工具`**，**主标签也设为「工具」**
     > 上次驳回原文：「分类/主标签与实际功能不符，应提交至【工具】分类并设置【工具】为主标签」。
     > 依据是审核指南 3.5 —— 本应用是单机记录工具，不是社交/生活服务类。

---

## 3. 签名（材料已有，无需重做）

当前签名可直接使用，**不需要**重新申请证书或 Profile。

- 位置：`%USERPROFILE%\.ohos\config\`
- 口令：`<签名口令：见本机私密文件 tools\signing.local.txt>`，别名：`datelog`
- 发布证书有效期到 **2029-10-08**

> ⚠️ **`.p12` 与口令绝不能丢** —— 丢了就无法再签同一个应用，只能换包名重新上架。
> 桌面 `DateLog-签名文件\` 有一份备份，建议再存一份到网盘/U 盘。

### 若将来必须重新配置签名

**只能走 DevEco Studio**：`File → Project Structure → Signing Configs`，取消自动签名后手动指定 p12 / p7b / cer。

> **实测坑**：手填明文口令会构建失败，报
> `00303116 ... The length of the storePassword or keyPassword field ... is less than 32`。
> hvigor 只接受 **DevEco 加密后**的口令串（AES-GCM，密文必然 ≥32 字节），
> 而 `decipher-util` 只提供 `decryptPwd()`、没有加密方法 —— 加密逻辑只在 IDE 内部。

---

## 4. 构建与自检

### 4.1 命令行出签名包

```powershell
$env:PATH = "<DevEco 安装目录>\tools\node;<DevEco 安装目录>\tools\ohpm\bin;<DevEco 安装目录>\tools\hvigor\bin;$env:PATH"
$env:DEVECO_SDK_HOME = "<DevEco 安装目录>\sdk"
hvigorw assembleApp --mode project -p product=default -p buildMode=release --no-daemon
```

产物：`build\outputs\default\DevecoStudioProject-default-signed.app`

> **注意**：hvigor 把日志写到 stderr，PowerShell 里即使 `BUILD SUCCESSFUL` 也可能显示 `exit code: 1`。
> **看输出文字，不要看退出码。**

### 4.2 上传前自检

```powershell
# 官方验签：必须拿到 "Verify success"
java -jar "<DevEco 安装目录>\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar" `
  verify-app -inFile <签名包路径> -inForm zip -outCertChain c.cer -outProfile p.p7b
```

- [ ] 产物是 `*-signed.app`（不是 `*-unsigned.app`）
- [ ] 官方验签 `Verify success`，退出码 0
- [ ] `bundleName` = `com.datelog.couple`
- [ ] `versionCode` / `versionName` 已确认（当前 `1000008` / `1.5.1`）
- [ ] 单元测试全绿：`hvigorw test --mode module -p product=default --no-daemon`（当前 47/47）
- [ ] 构建日志**没有** `Will skip sign 'app'`（出现说明签名没生效）

> ⚠️ **不要把签名包解压再打包** —— 签名块存在于 ZIP 中央目录之外，用 `Expand-Archive` 解压会丢签名，
> 之后验签会误报「signature not found」。**始终校验原始产物。**

### 4.3 真机回归（4 点，本次改动相关）

| # | 验证点 | 期望 |
|---|---|---|
| 1 | 首页顶部空白 | 上一轮修过（Scroll `.height('100%')` + `.align(Top)`），确认空白消失 |
| 2 | **跨零点封存** | 今天写完 → 系统日期调到明天 → 重开该记录 → **「编辑」消失** |
| 3 | **补记不污染今日状态** | 从日历点某天补记 → 保存后首页**仍应显示「今天未记录」** |
| 4 | 头像选择 | 「我的」→ 点头像 → **6 宫格（3×2）**能正常选中与切换 |

建议测试路径（也用于 AGC 审核备注）：
同意隐私政策 → 填写称呼 → 首页「记录今天」→ 选心情 + 写正文与明日计划 → 保存 →
首页「最近的记录」点开全文 → 时间轴点一条看详情 → 点「编辑」改完返回 → 日历点某天 →
「我的」切换日夜模式、更换头像、进入任务规划新建并完成一个任务 → 桌面添加服务卡片。

---

## 5. 商店资料

### 5.1 图标

- **必须上传直角方图**：`docs/store/app-icon-square-1024.png`
- ❌ 不要传 `docs/store/avatars-overview.png` 或任何已做圆角的预览图（AGC 会判不合格）

### 5.2 截图（3–5 张）

- **尺寸只能是 9:16 或 16:9**；模拟器原始截图（1256×2760 ≈ 9:19.8）**不合格**，需合成到 1080×1920。
- AGC 上传页默认选中「**横向截图**」，**必须手动切到「竖向截图」**，否则尺寸校验不过。
- 合成脚本：`tools/generate_store_screenshots.py`
  > 脚本里的文件名前缀目前是占位符 `<新截图1>` 等，**重拍后必须改成实际文件名前缀**，否则脚本直接报错（有意设计）。

### 5.3 隐私政策

- 上传 `docs/store/privacy-policy.html` 的**同名文件**到 OBS 桶 `datelog-privacy` 覆盖 `index.html`。
- 公网 URL（AGC 只接受公网可访问地址，不接受本地路径）：  
  `https://datelog-privacy.obs.cn-north-4.myhuaweicloud.com/index.html`
- 上传指南见 `docs/store/OBS_HOSTING_GUIDE.md`。
- 验证：浏览器无痕打开该 URL 应直接显示政策正文、**无需登录**。

### 5.4 文案

打开 `docs/store/LISTING.md`，逐段复制进 AGC 表单：
一句话简介、详细描述、权限说明、内容分级、审核备注、版本更新说明。

### 5.5 权限说明（AGC 权限页）

| 权限 | 处理 |
|---|---|
| **定位服务** | AGC 默认勾选 → **必须取消**（本应用不使用） |
| **华为账号** | AGC 默认勾选 → **必须取消**（本应用不使用） |
| **代理提醒** | ✅ 保留勾选（「重要日子提醒」确实使用） |
| 网络权限 | 本应用**未申请**，无需说明 |

---

## 6. 提交审核

1. AGC → 你的应用 → **版本管理 → 新建版本**。
2. 上传第 4 节得到的 **`*-signed.app`**。
3. 填写：版本号 `1.5.1`、更新说明（见 `LISTING.md`）、隐私政策 URL、应用分类「工具」、截图、内容分级、权限说明。
4. 提交**上架审核**。
5. 通过后选择**手动发布**或**审核通过后自动发布**。

审核时长参考：预审 30–40 分钟 → 人工审核数小时至 1–3 个工作日。

---

## 7. 上次被拒的 3 条问题 · 对应整改

| 上次驳回 | 根因 | 本次整改 |
|---|---|---|
| ① 应用信息：分类/主标签与实际功能不符，应提交至【工具】 | AGC 里选的是「生活服务」 | 分类与主标签都改「**工具**」（第 2 节） |
| ② 应用功能：「仅有简单记录打卡功能…使用场景有限」（审核指南 3.5） | 功能面偏薄 | 已扩展为完整记录工具：心情（含**自定义心情**）+ 手写正文 + **明日计划回显** + **记录详情与回看** + **历史封存** + 任务规划（≤6 个）+ 日历/时间轴/统计 + 图片记录 + 重要日子 + 桌面卡片 + 日夜模式 + 6 张内置头像 |
| ③ 真机（nova 14 Pro / HarmonyOS 6.1.0）「修改头像无反应」「添加照片无反应」 | `fileIo.copyFile(src, dest)` 传媒体库 URI 会抛 13900020 | 已改为 `openSync(uri)` → `openSync(dest)` → `copyFile(fd, fd)`；并移除 3 处静默失败路径（改为明确 toast）。**本轮头像已彻底改为内置头像，不再读取相册**，该问题从根上消失 |

---

## 附录 A · 常见驳回原因与对策

| 驳回原因 | 对策 |
|---|---|
| 上传了未签名包 | 确认产物是 `*-signed.app` |
| 包名与 AGC 项目不一致 | 必须是 `com.datelog.couple` |
| 缺隐私政策 / URL 打不开 | OBS 覆盖上传后，用无痕窗口确认可直接打开 |
| 未提供首启隐私同意 | 已内置（首启展示政策 + 同意/退出） |
| 权限说明缺失或不实 | AGC 权限页取消「定位」「华为账号」，保留「代理提醒」 |
| 分类/主标签不符 | 都设「工具」 |
| 截图尺寸不合格 | 只能 9:16 或 16:9，且要切「竖向截图」 |
| 图标不合格 | 传**直角方图**，不要传已圆角的预览图 |
| 截图与实机不符 / 全空状态 | 先造数据再截图 |
| versionCode 未递增 | 每次提交必须比上一版大 |
| **软件包合法性「不通过(993)」** | **构建时误用了 DevEco 的「自动生成签名」** —— `build-profile.json5` 里的 `keyAlias` 会变成 `debugKey`，包是用调试证书签的，AGC 判不合格（版本号那列还会显示 `--`）。到 **Project Structure → 签名配置** 取消「自动生成签名」，指回 `datelog.p12` / `datelog-release.p7b` / `datelog-release.cer`，别名填 `datelog`；**然后 clean 后重新打包**。本项目另备了一条**不依赖 DevEco 的自控签名路线**（见附录 C），DevEco 反复覆盖配置时用它更省事。自检命令：`<python> tools/check_signing.py` |
| 口令写成明文导致构建失败 | hvigor 要求 `storePassword` / `keyPassword` 是 **DevEco 加密串**（明文会报 "length ... less than 32"）。**不要手写明文**，用「附录 C」的脚本走 `hap-sign-tool`（它接受明文） |

## 附录 B · 版本迭代流程

**日常开发 / 真机测试**：直接用 DevEco 的 Run（走它自己的「自动生成签名」，不用手改配置）。

**要出发布包提交 AGC 时**，两条路线任选：

- **路线一（DevEco 签名）**：Project Structure → 签名配置里取消「自动生成签名」，指回 `datelog.p12` / `datelog-release.p7b` / `datelog-release.cer`，别名填 `datelog`；**clean 后**重新打包。
- **路线二（自控签名，不受 DevEco 影响，见附录 C）**：把 `build-profile.json5` 里 product 的 `"signingConfig"` 引用去掉，再跑 `pwsh -File tools/sign_release.ps1`。

最后都跑一次 `python tools/check_signing.py` 确认「✓ 可以上架」，做真机回归，再 AGC 新建版本 → 上传 → 填更新说明 → 提交。

## 附录 C · 自控签名流程（为什么不用 DevEco 的自动签名）

**问题**：DevEco Studio 一旦打开本项目，可能把 `build-profile.json5` 的签名配置改回「自动生成签名」，`keyAlias` 变成 `debugKey`，签出来的包 AGC 判 **993** 不合格；而它写在配置里的口令是 IDE 专有加密串，**明文会被 hvigor 拒掉**（"The length of the storePassword or keyPassword field ... is less than 32"），且加密串一旦被覆盖就无法还原。

**做法**：绕开 hvigor 的签名环节，自己签。

1. `build-profile.json5` 的 **product 不写 `signingConfig`**（`signingConfigs` 段保留也无妨，hvigor 不会用它）。
2. `hvigorw assembleApp ...` 产出 `build/outputs/default/DevecoStudioProject-default-unsigned.app`（内含未签名的 `entry-default.hap`）。
3. `hap-sign-tool sign-app` 用 **明文口令** 签 hap → 装回 .app → 再签 .app。参数：`-keyAlias datelog -keyPwd <签名口令：见本机私密文件 tools\signing.local.txt> -keystoreFile datelog.p12 -keystorePwd <签名口令：见本机私密文件 tools\signing.local.txt> -appCertFile datelog-release.cer -profileFile datelog-release.p7b -signAlg SHA256withECDSA -compatibleVersion 24 -signCode 1`。
4. 用 `verify-app -inForm zip` 验签。

以上全部封装在 **`tools/sign_release.ps1`** 里。**运行方式很重要**（脚本是 .ps1，系统默认执行策略会拦住它）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\sign_release.ps1
```

脚本里已经踩过并修掉的两个坑，改脚本时别踩回去：

1. **密码变量不能叫 `$pwd`** —— `$PWD` 是 PowerShell 的自动变量（当前目录，只读），赋值静默失效，会把「当前目录」当成密码传给签名工具，报 `keystore password was incorrect`。脚本里用的是 `$keyPass`。
2. **不能用 `$ErrorActionPreference = 'Stop'`** —— hvigor 会把日志写到 stderr，Windows PowerShell 5.1 把原生命令的 stderr 当终止错误，脚本会在第一步构建时就中断。脚本里保持 `Continue`，用 `$LASTEXITCODE` 与日志内容判断成败。

**注意**：不要解包再重打包一个**已签名**的 .app（签名块在 ZIP 中央目录之外，重打包会破坏它）；本流程重打包的是**未签名**的包，之后才签，所以安全。
5. 发布证书与 `.p12` 长期复用，**无需**重新申请

## 附录 C · 可选加固（非必需）

- **代码混淆**：当前 `entry/build-profile.json5` 的 release 里 `obfuscation.enable = false`。上架**不强制**混淆；若要开，先改成 `true`，再真机完整回归（`-enable-filename-obfuscation` 可能影响 `router` 页面路径与卡片 `LocalStorage` 键）。
- **降低系统版本门槛**：当前 `compatibleSdkVersion` 为 `6.1.1(24)`。想覆盖更老设备需装对应 SDK、下调该值并全量回归，属独立评估项。
- **头像与包体**：6 张头像每张约 50 KB（柔和渐变插画）。若想瘦身，可量化成 256 色 PNG（约能降到 100 KB 总量），但要重新目视确认无渐变色带。

## 附录 D · 环境与踩坑备忘

| 项 | 值 / 说明 |
|---|---|
| DevEco Studio | `<DevEco 安装目录>` |
| SDK | `<DevEco 安装目录>\sdk`（`DEVECO_SDK_HOME`） |
| 工程根 | `E:\DevecoStudioProject` |
| Python（脚本用） | `%USERPROFILE%\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe` |
| 真实桌面 | `%USERPROFILE%\OneDrive\Desktop`（**不是** `%USERPROFILE%\Desktop`，后者是残留） |
| hvigor 退出码 | 日志走 stderr，成功也可能报 `exit code: 1` —— 看文字 |
| AGC 下载按钮 | 要**左键点「下载」**，右键「另存为网页」会存成 HTML 而不是证书 |
| 桌面 `DateLog-*` 命名 | 历史遗留命名，内容已更新为「心情手记」 |
