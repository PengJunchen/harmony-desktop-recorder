# 清录安装指南

清录面向鸿蒙电脑 `2in1`，要求 API 24 / `6.1.1(24)` 及以上。当前是开发预览版本，尚未上架华为应用市场。手机、平板和兼容 Android 的旧版鸿蒙不在当前支持范围内。

## 1. 下载什么

从 [GitHub Releases](https://github.com/PengJunchen/harmony-desktop-recorder/releases) 直接下载同一版本的文件。仓库和发布附件现已公开，无需申请仓库访问权限。0.1.2 源码 ZIP / 离线指南中的旧私有权限说明已过时，以本在线指南为准。

| 文件 | 用途 |
| --- | --- |
| `Qinglu-<版本>-2in1-api24-unsigned.hap` | release 模式构建的未签名应用包，签名后才能安装 |
| `Qinglu-<版本>-source.zip` | 同一次提交的源码；推荐使用 DevEco 自动签名时下载 |
| `SHA256SUMS` | 下载文件的 SHA-256 校验值 |
| `release-manifest.json` | 对应源码提交、应用版本、设备范围与构建方式 |
| `INSTALL.md` | 本指南，支持离线阅读 |

`release` 是构建优化模式，`debug/release Profile` 是签名身份类型，两者不是同一个开关。此处未签名 release HAP 可以使用包含本人设备的有效调试 Profile 签名，用于本人设备测试；它不因此变成应用市场正式发行包。

本项目参考 [ClashBox 官方 Release](https://github.com/xiaobaigroup/ClashBox/releases/tag/1.7.4) 的 unsigned HAP 分发方式。ClashBox 的 [README](https://github.com/xiaobaigroup/ClashBox#readme) 提到 Auto-installer、DevEco Testing 等工具；这些工具对任意外部 HAP、`2in1` 及当前系统的支持需各自确认，清录以官方 DevEco / HDC 流程作为安装路径。

## 2. 校验下载

把上述文件放在同一文件夹中。macOS：

```sh
cd "<下载文件夹>"
shasum -a 256 -c SHA256SUMS
```

Linux 可以使用 `sha256sum -c SHA256SUMS`。Windows PowerShell 可以逐项运行：

```powershell
Get-FileHash .\Qinglu-0.1.2-2in1-api24-unsigned.hap -Algorithm SHA256
```

应与 `SHA256SUMS` 对应行完全一致。不一致时重新从该 Release 下载，不要继续签名。签名后 HAP 的哈希会变化；Release 中的哈希用于核对下载的原始未签名包。

## 3. 推荐：源码 + DevEco 自动签名

准备一台开发电脑、华为开发者账号和目标鸿蒙电脑。从 [华为开发工具页面](https://developer.huawei.com/consumer/cn/deveco-studio/) 安装 DevEco Studio 与 HarmonyOS SDK。本项目编译 SDK 为 `26.0.0`，兼容与目标 SDK 为 `6.1.1(24)`。

1. 解压同版本 `source.zip`，用 DevEco 打开其中的 `harmony-desktop-recorder` 文件夹，完成工程同步。若尚无根目录 `build-profile.json5`，先将 `build-profile.template.json5` 复制并重命名为 `build-profile.json5`。
2. 在目标电脑开启开发者模式及设备支持的 USB / 无线调试；连接开发电脑，解锁设备并允许调试。不要把 SSH 端口当成 HDC 端口。
3. 进入 **文件 → 项目结构 → 项目 → 签名配置**，选择 `default`，启用 **自动生成签名文件 / 使用 HarmonyOS 签名**，登录自己的华为开发者账号。
4. 选择正确的开发者身份和已连接设备，生成匹配 `com.personal.desktoprecorder` 的调试证书及 Profile。点击 **应用 / 确定**。菜单名称可能随 IDE 版本和语言变化，详见 [华为签名指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-signing)。
5. 保持模块 `deviceTypes` 为 `["2in1"]`，`default` 产品绑定 `signingConfig: "default"`。不要改成手机 / 平板模板。
6. 在 DevEco 选择连接的电脑，运行 `entry`；IDE 负责构建、签名和安装。或者在 macOS 终端按下面的方式构建与安装。

```sh
export RECORDER_DEVECO="/Applications/DevEco-Studio.app/Contents"
export PATH="$RECORDER_DEVECO/sdk/default/openharmony/toolchains:$PATH"
hdc list targets
export RECORDER_TARGET="<从上一步复制的目标标识>"
hdc -t "$RECORDER_TARGET" shell param get const.ohos.apiversion

# 必须在解压后的源码目录执行；默认 debug 构建也可用于本机调试
RECORDER_BUILD_MODE=release bash scripts/build.sh
python3 scripts/verify-debug-signature.py \
  --hap entry/build/default/outputs/default/entry-default-signed.hap \
  --target "$RECORDER_TARGET"
python3 scripts/install-device.py \
  --target "$RECORDER_TARGET" \
  --hap entry/build/default/outputs/default/entry-default-signed.hap
```

脚本目前适配 macOS 版 DevEco 目录；Windows 用户使用 IDE 的运行 / 构建功能，或使用对应 SDK 中的 HDC 命令。终端显示安装、启动成功后，仍需在目标电脑完成录屏授权。

## 4. 已有匹配签名材料：直接签名下载的 HAP

这条路径适合了解签名的开发者，无需重新编译源码。准备同一套 `.p12`、密钥别名、应用证书链 `.cer` 和平台签发的 debug `.p7b`；Profile 的包名必须为 `com.personal.desktoprecorder`，设备列表包含目标电脑，且在有效期内。材料的申请流程见 [项目 README](https://github.com/PengJunchen/harmony-desktop-recorder#生成本机可用的-debug-签名) 和 [华为调试 Profile 指南](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/agc-help-debug-profile-0000002248181278)。

在交互式终端使用 SDK 官方工具；以下是 macOS 示例，替换尖括号内容和版本号：

```sh
export RECORDER_DEVECO="/Applications/DevEco-Studio.app/Contents"
"$RECORDER_DEVECO/jbr/Contents/Home/bin/java" \
  -jar "$RECORDER_DEVECO/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar" \
  sign-app -mode localSign \
  -keyAlias "<密钥别名>" \
  -appCertFile "<应用证书链.cer的绝对路径>" \
  -profileFile "<调试Profile.p7b的绝对路径>" \
  -keystoreFile "<密钥库.p12的绝对路径>" \
  -inFile "Qinglu-0.1.2-2in1-api24-unsigned.hap" \
  -outFile "Qinglu-0.1.2-local-signed.hap" \
  -signAlg SHA256withECDSA -compatibleVersion 24 -signCode 1 -pwdInputMode 1
```

`-pwdInputMode 1` 由工具交互式询问密码，不要把真实密码直接写进命令或脚本。IDE 保存的加密密码字符串不能作为明文密码填入。若不知道自动签名密钥的密码，使用第 3 节让 IDE 管理，不需要尝试解密。以上参数以当前 SDK 的 `hap-sign-tool.jar -h` 为准。

在同版本源码目录使用 `verify-debug-signature.py --hap <本地signed包> --target <目标标识>` 校验，再运行 `install-device.py`。也可以使用 HDC：

```sh
hdc -t "$RECORDER_TARGET" install -r "Qinglu-0.1.2-local-signed.hap"
hdc -t "$RECORDER_TARGET" shell aa start -a EntryAbility -b com.personal.desktoprecorder
```

安装输出应包含 `install bundle successfully`，启动输出应包含 `start ability successfully`。HDC 退出码为 0 仍可能在文本中报告设备错误，应检查完整返回值。

不要分发本人的已签名调试 HAP，它内嵌的 Profile 含开发者和设备绑定信息。不要分享密钥、密码或完整 Profile；项目 Release 不提供这些材料。普通本地自签证书也不能替代目标华为设备信任的开发者签名。

## 5. 首次使用、升级与证书到期

1. 打开清录，选择分辨率与视频码率。可从长边 1920、4–8 Mbps 开始，根据文字清晰度和文件体积调整。
2. 点 **开始录制**，在系统授权弹窗选择整个屏幕；需要麦克风讲解时允许麦克风权限。
3. 点 **停止并保存**，在列表中预览并导出视频。开始 / 停止操作仍由用户控制，受系统隐私及受保护内容限制。

升级时保持包名及签名身份一致，使用新的有效 Profile，通过 `hdc install -r` 尝试覆盖安装。更换签名身份可能导致签名不一致，不能保证覆盖成功。不要为了升级直接卸载：应用私有目录中的视频会被删除，先导出重要录像。

Profile 的有效期以开发者平台及实际签发文件为准，本指南不承诺固定天数。到期或新增设备后，在 DevEco 更新 Profile、重新签名并安装；账号认证状态变化不会自动延长已经签发的旧文件。

## 常见问题

| 问题 | 处理 |
| --- | --- |
| 下载后双击 HAP 无法安装 / 提示没有签名 | unsigned 包必须先按第 3 或第 4 节完成签名 |
| HDC 看不到电脑 | 确认开发者模式、调试授权、线缆 / 当前无线地址及端口；用 `hdc list targets` 查看 |
| `9568257 / fail to verify pkcs7 file` | 检查目标设备认可的 HarmonyOS 签名、同套证书与 Profile |
| 设备不在 Profile 中 / Profile 过期 | 在自己的开发者账号下加入设备、更新 Profile 后重签 |
| IDE 生成了材料但没有 signed HAP | 点击应用并检查产品的 `signingConfig` 绑定 |
| 覆盖安装提示签名冲突 | 使用原有签名身份；先导出录像再考虑卸载 |
| 开始录制提示参数无效 | 确认使用当前版本、目标设备为 `2in1`、码率为 1–30 Mbps |

GitHub Release 是文件分发渠道。若将来面向普通用户正式发行，应按华为规则申请发布身份、准备应用市场材料并通过 AppGallery Connect 审核；当前预览包不代表已上架或可免签安装。
