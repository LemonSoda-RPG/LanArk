# LanArk for HarmonyOS

LanArk 是一个面向 HarmonyOS NEXT 的原生 ArkTS/ArkUI LANraragi 阅读器。它支持手机和平板，提供档案库、封面缓存、搜索、标签、阅读进度同步以及单页/双页/瀑布阅读模式。

## 当前版本信息

- 应用名称：`LanArk`
- HarmonyOS 应用包名：`com.lanark.reader`
- 模块：`entry`
- 支持设备：`phone`、`tablet`
- 屏幕方向：跟随设备自动旋转，并遵守系统旋转锁定开关
- 编译目标：HarmonyOS `6.1.1(24)`
- 应用模型：Stage model
- UI 技术：ArkTS + ArkUI

包名使用 `com.lanark.reader`。如果你从旧包名版本升级，系统会把它视为一个新的应用，旧应用中的设置、API Key 和缓存不会自动迁移。

## 功能概览

- LANraragi 多服务器配置、API Key 安全保存和连接测试
- 档案库首页、封面缓存、网格/列表布局和自适应列数
- 标题、标签搜索以及多种排序方式
- 阅读进度同步，返回档案库后立即刷新当前文档进度
- 单页阅读、双页阅读、瀑布阅读
- 左右翻页、点击翻页、滚动阅读、阅读方向设置
- 单页和瀑布模式的双指缩放、拖动和页面宽度调整
- 阅读页预加载和本地图片缓存
- 当前文档标签查看、按标签搜索和删除确认
- 档案离线下载：逐页保存到应用沙箱，支持无网络阅读
- 已下载档案页和下载管理页，实时显示下载页数与失败状态
- 手机、平板、深色模式、横屏和系统底部安全区域适配
- 设置页统一管理服务器、布局、阅读方向、预加载页数和缓存

## 环境要求

### 推荐开发环境

| 项目 | 要求 |
| --- | --- |
| IDE | DevEco Studio 6.1.1 Release 或兼容的更新版本 |
| HarmonyOS SDK | 6.1.1 Release，API 24 |
| Node.js、Hvigor、ohpm | 使用 DevEco Studio/Command Line Tools 自带版本 |
| 设备 | HarmonyOS NEXT 手机或平板，开启 USB 调试 |
| 服务器 | 可从设备访问的 LANraragi 服务 |

项目的 `compileSdkVersion`/`targetSdkVersion` 使用 `6.1.1(24)`。如果本机只有其他版本 SDK，请在 DevEco Studio 的 SDK 管理器中安装对应 API；不要直接把 `build-profile.json5` 改成不匹配的版本。

### 不需要单独安装的依赖

项目没有运行时 npm、第三方 UI 框架或图片库依赖。ArkUI、网络、文件、图片、Asset Store 等能力都来自 HarmonyOS 系统 Kits。`oh-package.json5` 中的两个开发依赖只用于测试：

- `@ohos/hypium@1.0.25`：HarmonyOS 测试框架。
- `@ohos/hamock@1.0.0`：测试 Mock 工具。

正常运行应用不需要安装这两个测试包以外的第三方运行时库。`oh-package-lock.json5` 用于锁定 ohpm 依赖版本，请与 `oh-package.json5` 一起保留。

### 使用到的系统 Kits

| Kit | 用途 |
| --- | --- |
| `@kit.AbilityKit` | 获取应用上下文、文件目录和 Ability 生命周期 |
| `@kit.ArkUI` | 页面、组件、导航、手势和窗口 UI |
| `@kit.ArkData` | Preferences 本地配置存储 |
| `@kit.ArkTS` | ArkTS 运行时工具 |
| `@kit.AssetStoreKit` | 安全保存和读取 API Key |
| `@kit.BasicServicesKit` | 网络请求辅助和系统基础能力 |
| `@kit.NetworkKit` | LANraragi HTTP API 请求 |
| `@kit.CoreFileKit` | 本地封面、阅读图片和缓存文件 |
| `@kit.ImageKit` | 图片解码、尺寸读取和 PixelMap 处理 |
| `@kit.PerformanceAnalysisKit` | 日志和异常分析 |

## 获取源码

解压源码后，使用 DevEco Studio 打开包含以下文件的项目根目录：

```text
AppScope/
entry/
hvigor/
build-profile.json5
oh-package.json5
oh-package-lock.json5
hvigorfile.ts
```

不要只打开 `entry` 子目录，否则 DevEco Studio 无法正确识别应用级配置。

## 首次导入和依赖同步

1. 启动 DevEco Studio。
2. 选择 **Open**，打开项目根目录。
3. 等待项目索引完成，并在提示出现时执行 **Sync/Install Dependencies**。
4. 在 SDK 管理器中确认已安装 HarmonyOS 6.1.1(API 24) SDK。
5. 如果 DevEco Studio 提示缺少 SDK、Hvigor 或 ohpm，按照提示使用 IDE 自带版本安装，不要把个人电脑路径写进源码。

也可以在命令行执行依赖同步。需要先把 DevEco Command Line Tools 的 `ohpm` 加入 PATH：

```powershell
ohpm install
```

本仓库不提交 `oh_modules`；该目录是依赖安装产物，已加入 `.gitignore`。

## 编译 Debug HAP

### 使用 DevEco Studio（推荐）

1. 打开项目后，在设备选择器中选择 `default` 产品和 `entry` 模块。
2. 选择 **Build > Build Hap(s)/APP(s) > Build Hap(s)**。
3. 构建完成后，在 `entry/build/` 下查看生成物。

### 使用命令行

如果本机的 DevEco Command Line Tools 提供 `hvigorw.bat` 包装脚本，在项目根目录执行：

```powershell
.\hvigorw.bat --mode module -p product=default assembleHap --no-daemon
```

Linux/macOS 使用：

```bash
./hvigorw --mode module -p product=default assembleHap --no-daemon
```

本上传包不包含由 IDE 生成的 `hvigorw` 包装脚本；如果命令不存在，请直接使用 DevEco Studio 构建，或从本机 Command Line Tools 配置对应的 Hvigor 命令。命令行工具的版本必须与项目使用的 DevEco/HarmonyOS SDK 兼容。

常见输出位置如下，具体文件名以构建模式和 DevEco Studio 版本为准：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
entry/build/default/outputs/default/entry-default-signed.hap
```

`entry/build` 是生成目录，不要提交到 GitHub。

## 配置签名并构建 Release HAP

为了脱敏，本仓库的 `build-profile.json5` 不包含任何个人签名配置。首次构建 Release 版本时必须使用自己的证书和 Profile：

1. 在 DevEco Studio 打开 **File > Project Structure > Signing**。
2. 选择自动签名，或配置自己的 `.p12`、`.cer` 和 `.p7b` 文件。
3. 选择要构建的 `default` 产品和 `release` 模式。
4. 执行 **Build Hap(s)**。

签名文件、密码、`local.properties` 和生成的 HAP 都不要提交到公共仓库。它们已经被 `.gitignore` 排除。不要把自己的证书文件复制回项目后再上传。

## 真机运行和安装

### 使用 DevEco Studio

1. 在手机或平板中开启开发者选项和 USB 调试。
2. 使用数据线连接电脑并接受设备授权。
3. 在 DevEco Studio 的设备列表中选择设备。
4. 点击 **Run**，IDE 会构建、签名并安装应用。

### 使用 HDC

确认 Command Line Tools 的 `hdc` 已加入 PATH：

```powershell
hdc list targets
hdc install -r .\entry\build\default\outputs\default\entry-default-signed.hap
```

如果设备没有出现在 `hdc list targets` 中，请检查 USB 调试授权、数据线、驱动和设备开发者模式。

## 连接 LANraragi

应用首次启动后进入设置页填写：

- 服务器地址，例如 `http://192.168.1.10:3000`
- LANraragi API Key

验证并保存后，服务器会出现在“保存的服务器”列表中。需要切换局域网或服务器时，
在设置页选择对应条目，再点击“验证并保存”即可连接；“新增服务器”可以添加另一套地址和 API Key。

服务器地址必须是设备能够访问的地址。电脑上的 `localhost` 对手机和平板指向的是设备自身，不是电脑；请使用电脑的局域网 IP 或可解析的主机名。若使用 HTTPS，请确认设备能够验证服务器证书。

API Key 不写入源码，也不会写入 README。应用使用 HarmonyOS Asset Store 按服务器配置分别保存 API Key，服务器列表和当前选择保存在应用本地 Preferences 中。

## 数据、缓存和隐私

- 封面和阅读图片保存在应用沙箱缓存目录中。
- 用户主动下载的档案保存在应用沙箱的持久化离线目录中，不会被“清空图片缓存”删除。
- 已下载页面只显示完整下载的档案；中断下载会保留进度并可从下载管理页重试。
- 设置页可以清空封面缓存和阅读缓存。
- 文档阅读结束后可以删除当前文档的阅读缓存。
- 应用只向用户配置的 LANraragi 服务器读取索引、详情、标签、封面和页面图片，并同步阅读进度。
- 项目不会主动删除服务器上的文档、分类或标签。
- 本上传包不包含服务器地址、API Key、签名证书、个人路径、构建缓存或已签名 HAP。

## 项目目录

```text
AppScope/
  app.json5                         应用包名、版本和全局 Logo
  resources/                        应用名称与图标资源
entry/
  src/main/ets/data/                API、Preferences、Asset Store 和缓存
  src/main/ets/features/archive/    档案库和详情页
  src/main/ets/features/reader/     阅读器、缩放和预加载
  src/main/ets/features/settings/   服务器与阅读设置
  src/main/ets/pages/               应用入口页
  src/main/resources/               页面、颜色、图片和字符串资源
  src/main/module.json5             权限、设备类型和 Ability 配置
build-profile.json5                 产品、模块和 SDK 构建配置
oh-package.json5                    ohpm 项目和测试依赖
oh-package-lock.json5               锁定的依赖版本
code-linter.json5                   ArkTS 代码检查规则
THIRD_PARTY_NOTICES.md              第三方图标和许可证说明
```

## 常见问题

### 构建时提示找不到 SDK

打开 SDK 管理器安装 HarmonyOS 6.1.1(API 24)，然后重新同步项目。请确认 DevEco Studio 和 SDK 版本相互兼容。

### 构建时提示没有签名配置

这是正常的，因为公共源码包已删除个人签名信息。按照“配置签名并构建 Release HAP”章节创建自己的签名配置即可。

### 提示 API Key Asset 不存在

这是设备上旧版本的安全存储项失效或被清理导致的。进入设置页重新保存 API Key；如果仍然失败，可以卸载旧包名应用后重新安装新包名的 `com.lanark.reader`。

### 档案库无法连接

先在设备浏览器访问服务器地址，确认局域网连通；再检查 LANraragi 是否允许局域网访问、防火墙端口、API Key 和 URL 是否包含多余的路径或空格。

### 页面图片加载失败

检查服务器是否能返回原图和缩略图，确认设备剩余存储空间，并在设置页清理后重新下载缓存。

## 开源和贡献

提交代码前请确认没有加入以下文件：

- `local.properties`
- `.preview/`、`.hvigor/`、`.idea/`、`oh_modules/`、`build/`
- `.p12`、`.p7b`、`.cer`、`.jks`、`.keystore`、`.pfx`
- `.hap`、`.app`、日志或任何包含个人路径的文件

提交 Pull Request 前，请至少完成一次 ArkTS 检查和一次真机/模拟器构建。

## 许可证和第三方声明

应用使用的图标和第三方资源说明见 `THIRD_PARTY_NOTICES.md`。请在重新分发或修改图标资源时遵守对应许可证。
