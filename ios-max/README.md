# SuperApp iOS MAX 适配

> ⚠️ **全部未验证**：本目录下的越狱插件、权限配置与安装步骤，均未在真机上
> 编译、安装或测试过。写它们的人（Muse）没有 iOS 设备与 Theos 环境，
> 内容来自公开资料整理。请在备用机上逐项验证，确认无误再在主力机上使用。

SuperApp 的 Super MAX 在 Android 上靠 root；在 iOS 上没有 root 概念，
对应两条路：

| 路径 | 适用系统 | 能力上限 | 需要 |
| --- | --- | --- | --- |
| **TrollStore 安装** | iOS 14.0–17.0（TrollStore 1/2 支持的版本） | 沙盒外文件读写（mobile 用户权限），无 root | TrollStore + 自定义 entitlements |
| **越狱 + 本插件** | 已越狱设备（Rootful / Rootless） | 系统级：偏好读写、文件读写（可达 root）、respring | 越狱环境 + Theos 编译的插件 |

两条路可以叠加：越狱设备上用 TrollStore 装 SuperApp，再装插件，能力最全。

## 目录

| 文件 | 说明 |
| --- | --- |
| `Tweak.xm` | 越狱插件骨架（Theos/Logos）：Darwin 通知 + 共享 JSON 文件 IPC，提供偏好读写、文件读写、respring |
| `SuperAppMax.plist` | 插件注入目标：只注入 SpringBoard |
| `Makefile` | Theos 编译配置（Rootful 默认；Rootless 见下） |
| `control` | Debian 包信息（Rootful 默认） |
| `SuperApp-TrollStore.entitlements` | TrollStore 安装用的扩展权限，逐项注明用途与风险 |
| `README.md` | 本文件 |

## 路径一：TrollStore 安装 SuperApp

### 前置条件

- 设备系统在 TrollStore 支持范围内（TrollStore 2：iOS 15.0–17.0；
  TrollStore 1：iOS 14.0–15.4.1；具体以 TrollStore 官方说明为准，
  arm64e 机型需要对应的 CoreTrust 漏洞未被修复）。
- 已安装 TrollStore（按其官方安装器流程走，与本项目无关）。
- SuperApp 的未签名 IPA：CI 的 iOS 任务产物（`superapp-ios-ipa`），
  或本地 `flutter build ipa --no-codesign` 的产物。

### 安装步骤

1. 把 IPA 传到手机（隔空投送、文件 App、网盘均可）。
2. 在 TrollStore 里打开 IPA，点安装。
   TrollStore 会用 CoreTrust 漏洞给 App 签名，装好即可直接打开，
   不需要开发者证书、不需要每 7 天重签。
3. **应用自定义权限（关键一步，决定 MAX 能不能用）：**
   - 方式 A（推荐，如果你的 TrollStore 版本支持）：安装时选择
     “使用自定义 entitlements”，选中本目录的
     `SuperApp-TrollStore.entitlements`。
   - 方式 B：先解压 IPA，用 `ldid` 给主程序重新签名：
     `ldid -S SuperApp-TrollStore.entitlements SuperApp`，
     再重新打包安装（需要 Mac 或已越狱设备上的 ldid，均未验证）。
   - 如果跳过这一步，App 仍可安装打开，但只是个普通沙盒应用，
     Super MAX 开关会显示“未越狱”，打不开。
4. 打开 SuperApp → 设置 → Super MAX：
   - 顶部会显示 **iOS MAX 环境：TrollStore（未越狱）**，
     下方列出可用能力与限制。
   - 打开开关即可（不需要 root 检测）。
5. 验证：WebOS 文件管理器应能看到应用容器外的目录；
   设置页应显示环境为 TrollStore。

### 权限取舍

`SuperApp-TrollStore.entitlements` 里每项都有注释说明用途与风险。
原则：**按需取用，不要全开**。各取所需的最小集合是：

- 最小可用（文件读写）：`platform-application`、
  `com.apple.private.security.no-sandbox`、
  `com.apple.private.security.container-required`。
- 再加 IPC/插件联动：`get-task-allow`、
  `com.apple.private.skip-library-validation`。
- 进程管理、完全磁盘访问、应用安装：`task_for_pid-allow`、
  `com.apple.private.tcc.allow`、`com.apple.private.mobileinstall.allowedSPI`
  —— 都是高危项，用不到就别开。

## 路径二：越狱 + 安装 SuperAppMax 插件

### 前置条件

- 设备已越狱（Rootful：palera1n rootful、checkra1n 等；
  Rootless：Dopamine、palera1n rootless、XinaA15 等）。
- 编译环境：一台 Mac 或 Linux，装好 Theos（见 theos.dev 官方文档）
  与对应 iOS 版本的 SDK。
- SuperApp 已安装（App Store、侧载、TrollStore 均可；
  TrollStore 安装 + 插件能力最全）。

### 编译

```sh
export THEOS=/path/to/theos
make package            # Rootful，生成 .deb
# Rootless 越狱改用：
make package THEOS_PACKAGE_SCHEME=rootless
```

Rootless 打包时还需注意：

- `control` 里的 `Architecture` 应为 `iphoneos-arm64`（Rootful 是
  `iphoneos-arm`），`Depends` 里的 `mobilesubstrate` 在 Rootless
  环境下对应的是 ElleKit/libhooker，具体依赖以你所用越狱的文档为准。
- 插件安装路径 Rootless 下是 `/var/jb/Library/MobileSubstrate/DynamicLibraries/`，
  Theos 的 rootless scheme 会自动处理。

### 安装

- 把生成的 `.deb` 传到手机，用 Sileo / Zebra 安装，或 `dpkg -i` 安装。
- 安装后自动 respring（Makefile 的 `after-install` 会执行）。
- 打开 SuperApp → 设置，iOS MAX 环境应显示为
  **已越狱（Rootful/Rootless）**，Super MAX 开关可用。

### 插件工作原理

见 `Tweak.xm` 顶部注释与下方“IPC 协议”。一句话：插件注入
SpringBoard，监听 Darwin 通知；App 把请求写成 JSON 文件发通知，
插件执行后把结果写回 JSON 文件再发通知。偏好用 CFPreferences，
文件用 NSFileManager，respring 用 `killall -9 backboardd`。

## 能力对照表

| 能力 | 未越狱（普通安装） | TrollStore | 越狱 + 插件 |
| --- | --- | --- | --- |
| 应用内功能（计算器、AiPlat、WebOS 内置应用等） | ✅ | ✅ | ✅ |
| 沙盒外文件读写（mobile 用户权限） | ❌ | ✅（需 no-sandbox 权限） | ✅ |
| 读取系统偏好设置文件 | ❌ | ✅（可读） | ✅ |
| 修改系统偏好设置（AI 调设置） | ❌ | ⚠️ 仅 mobile 可写的域 | ✅（经插件 IPC） |
| root 拥有的文件读写 | ❌ | ❌ | ✅（插件以 root 上下文执行时；Rootless 下需 root 守护进程配合，TODO） |
| 注入其他 App / Hook SpringBoard | ❌ | ❌ | ✅（插件本身） |
| respring / 管理系统守护进程 | ❌ | ❌ | ✅（插件；Rootless 下 respring 方式待验证） |
| 安装/卸载其他应用 | ❌ | ⚠️ 需 mobileinstall SPI，未验证 | ⚠️ 需插件配合，未验证 |
| Super MAX 开关 | ❌ 不可用 | ✅ 可用 | ✅ 可用 |

✅ 可用 / ⚠️ 受限或待验证 / ❌ 不可用

## IPC 协议（App ↔ 插件）

共享目录：`/var/mobile/Library/SuperApp/`
（App 与插件都需能访问：TrollStore 下靠 no-sandbox 权限，
越狱下靠插件注入后的系统上下文。）

请求文件：`request-<id>.json`，内容：

```json
{"id": "uuid", "action": "readPref", "params": {"domain": "com.apple.springboard", "key": "SBEnableSomeSetting"}}
```

写完后 App 发 Darwin 通知 `com.superapp.max.request`。
插件处理完写 `response-<id>.json`：

```json
{"id": "uuid", "ok": true, "result": {"value": true}}
```

再发通知 `com.superapp.max.response`，App 读回结果并删除响应文件。

支持的 action（见 `Tweak.xm`）：`ping`、`systemInfo`、`readPref`、
`writePref`、`readFile`、`writeFile`、`listDir`、`respring`。

> Dart 侧的 IPC 客户端（发请求、等响应）尚未实现，当前 Flutter 侧
> 只有环境检测（`lib/supermax/ios_max.dart`）与设置页展示。
> IPC 客户端是后续工作。

URL Scheme（辅助通道，已在 `ios/Runner/Info.plist` 声明）：

- `superapp://`：打开 SuperApp。
- `superapp-max://<action>?<params>`：从插件侧唤起 SuperApp 并触发
  MAX 动作。Dart 侧的 deep-link 处理尚未实现（后续工作）。

## 安全注意事项

- **no-sandbox 与 TCC 绕过是最高危权限**：App 能读 mobile 用户
  能读的全部数据。请只在信任 SuperApp 代码的前提下使用，
  且不要把 API Key 以外的敏感信息长期放在 App 可读的位置。
- **插件无白名单**：骨架的 `writeFile`/`writePref` 未限制路径与域名，
  正式版必须加白名单（只允许系统设置相关的域与路径），否则
  任何能写请求文件的进程都能借插件之手改系统。
- **respring 有风险**：插件崩溃或 respring 失败可能导致 SpringBoard
  反复重启（respring loop），进安全模式卸载插件即可恢复，
  但请先在备用机上验证。
- **不要在主力机上直接试**：先备用机，再主力机；改系统设置前
  备份相关偏好文件。
- **TrollStore 与越狱本身的风险**：设备失去保修、部分银行类应用
  拒绝运行、系统更新可能失效，均与本项目无关，请自行评估。

## 已知未验证清单

- [ ] 插件在 Theos 下能否编译通过（无 Theos 环境）。
- [ ] 插件装到越狱设备上能否加载、IPC 是否通。
- [ ] TrollStore 自定义 entitlements 的两种应用方式是否有效。
- [ ] `com.apple.private.mobileinstall.allowedSPI` 的 SPI 名称是否正确。
- [ ] Rootless 下 respring 与 root 写操作的具体做法。
- [ ] 各 iOS 版本（15/16/17）下 TrollStore 检测路径是否有效。
- [ ] Dart 侧 IPC 客户端与 deep-link 处理（尚未实现）。

## 后续工作

1. Dart 侧 IPC 客户端（`lib/supermax/ios_max_ipc.dart`）：发请求、
   等响应、超时处理；Super MAX 开启后，WebOS 文件读写与 AiPlat
   手机操作走 IPC 而不是直接文件访问。
2. Dart 侧 deep-link 处理（`superapp://` 与 `superapp-max://`）。
3. 插件写操作白名单 + root 守护进程（Rootful/Rootless 的 root 写路径）。
4. 在真机上逐项验证“已知未验证清单”，把结果写回本文件。
