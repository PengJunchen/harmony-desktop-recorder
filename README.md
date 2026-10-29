# 清录 · 鸿蒙电脑桌面录屏

清录是面向鸿蒙电脑的原生 ArkTS / Stage 应用，支持录制整个桌面，并将视频保存在本机。

- 应用包名：`com.personal.desktoprecorder`
- 当前版本：`0.1.2`
- 目标设备：`2in1` 电脑，API 24 / `6.1.1(24)` 及以上
- 输出格式：MP4，H.264 视频与 AAC 音频

## 下载与安装

前往 [GitHub Releases](https://github.com/PengJunchen/harmony-desktop-recorder/releases) 下载预览版。发布附件包含 **release 模式的未签名 HAP**、同版本源码、SHA-256 校验值及离线安装指南。仓库目前为私有，需要有仓库访问权限。

请按 [安装指南](docs/INSTALL.md) 先校验、再使用自己的有效调试签名安装；推荐使用源码与 DevEco 自动签名。未签名 HAP 不能直接双击安装，个人设备 signed HAP 不作为通用下载包。发布约定与维护者命令见 [打包细则](docs/RELEASING.md)。此方式参考 ClashBox 的 unsigned HAP 分发，实际签名和安装以华为官方流程为准。

## 功能

- 整屏录制；可选原分辨率、长边最高 2560 或 1920，保持原比例，不放大原画面。
- 视频码率可选自动匹配、2 / 4 / 8 / 12 / 20 / 30 Mbps 预设，或自定义 1–30 Mbps，最多两位小数。
- 自定义码率通过滑杆或数值输入调整，独立于分辨率，并显示每分钟体积参考。
- 支持系统声音和可选麦克风讲解、计时、停止保存、录制列表、视频预览及导出。
- 视频先保存在应用私有目录，停止后可导出到系统文件选择器指定的位置。
- 不接入网络，不上传录制内容。

码率越低，文件通常越小，也可能损失运动画面与文字细节。例如，4 Mbps 的体积参考约 31.4 MB/分钟，2 Mbps 约 16.4 MB/分钟，已计入当前音轨码率，未计入容器开销。实际体积随画面内容变化，静止画面可能明显小于参考值。录制期间设置锁定，新设置从下一次录制开始生效。

## 开发环境

本项目当前采用：

| 项目 | 配置 |
| --- | --- |
| DevEco Studio | macOS 安装，包含 Node、JBR、Hvigor 与 SDK |
| 编译 SDK | 26.0.0 |
| 兼容 / 目标 SDK | `6.1.1(24)` |
| Hvigor | 6.26.8 |
| Python | Python 3 |
| 模块设备类型 | 仅 `2in1` |

默认 DevEco 路径为 `/Applications/DevEco-Studio.app/Contents`。安装在其它位置时，设置 `RECORDER_DEVECO`。构建脚本使用 DevEco 内置 Node 与 JBR，无需另外安装终端 Java。

不要把模块设备类型改成 `tablet/default`。构建脚本会检查 `2in1` 声明，避免应用进入移动端兼容模式。

## 克隆与本地构建

```sh
git clone https://github.com/PengJunchen/harmony-desktop-recorder.git
cd harmony-desktop-recorder
bash scripts/build.sh
```

首次构建会把 `build-profile.template.json5` 复制为本机 `build-profile.json5`。模板不含签名配置。直接构建会得到未签名 HAP：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

未签名 HAP 不能直接作为普通应用安装到目标电脑。完成下文的本机 debug 签名配置后，再次执行同一构建命令，会额外生成：

```text
entry/build/default/outputs/default/entry-default-signed.hap
```

本机配置 `build-profile.json5` 已被 Git 忽略；仓库只跟踪无签名信息的模板。

## 生成本机可用的 debug 签名

### 1. 理解需要生成的材料

可以在本机生成密钥对和 CSR，但华为设备认可的 debug 签名还需要开发者平台签发的调试证书与设备绑定 Profile。任意本地自签名证书、上游 OpenHarmony 公开测试证书，不能替代目标设备认可的调试证书。

| 材料 | 用途 |
| --- | --- |
| `.p12` 密钥库 | 保存应用签名所需私钥；密码、别名必须与之匹配 |
| `.csr` | 申请调试证书使用的证书请求文件 |
| `.cer` 调试证书 | 开发者平台签发的公钥证书链 |
| `.p7b` 调试 Profile | 绑定包名、调试证书、设备标识与有效期 |

### 2. 连接目标电脑

在目标电脑上开启开发者模式与调试，并在设备上允许连接。使用 DevEco 的设备管理连接 USB 或设备提供的无线调试地址。

```sh
export RECORDER_DEVECO="/Applications/DevEco-Studio.app/Contents"
export PATH="$RECORDER_DEVECO/sdk/default/openharmony/toolchains:$PATH"
hdc list targets
```

从输出复制目标标识：

```sh
export RECORDER_TARGET="<hdc list targets 中的目标标识>"
hdc -t "$RECORDER_TARGET" shell param get const.ohos.apiversion
```

SSH 服务端口与 HDC 调试端口是不同的连接方式。无线调试端口应以设备当前给出的地址为准，不能将 SSH 端口当作 HDC 端口。

### 3. 使用 DevEco 自动生成

1. 在 DevEco Studio 中打开项目目录，等待工程同步完成。
2. 进入 **文件 → 项目结构 → 项目 → 签名配置**，选择 `default`。
3. 勾选 **自动生成签名文件** 和 **使用 HarmonyOS 签名**。
4. 登录已具备开发者资格的华为账号，选择正确的开发者身份 / Team。
5. 保持目标设备已连接。DevEco 会生成本地密钥 / CSR，申请调试证书，并生成绑定本项目包名与目标设备的 debug Profile。
6. 生成成功后，点击 **应用** 或 **确定**，将配置写入本机工程。
7. 检查本机 `build-profile.json5`：`app.signingConfigs` 中应有 `default` 配置，`app.products` 中的 `default` 产品也应包含 `"signingConfig": "default"`。只生成材料而未绑定产品，会继续产出未签名包。
8. 运行 `bash scripts/build.sh`，得到 signed HAP。

DevEco 通常将材料保存在用户目录的 `~/.ohos/config/`，实际路径以签名配置页为准。由 IDE 管理签名密码，不要把真实密码、私钥或完整本机签名配置复制进 README、提交或聊天。

更换设备、修改包名或 Profile 到期后，需要重新生成或更新 Profile，随后重建 signed HAP。

### 4. 需要手动申请时

如果无法使用自动签名，且你拥有该包名的应用管理权限，可以在 DevEco 中生成本地密钥库与 CSR，再在华为开发者中心依次完成以下步骤。普通下载用户优先使用自动签名，不应尝试以维护者身份创建或发布同包名应用：

1. 创建包名为 `com.personal.desktoprecorder` 的应用。
2. 使用 CSR 申请并下载调试证书。
3. 注册需要调试的设备。
4. 创建 **debug Profile**，选择此应用、调试证书和目标设备，并下载 `.p7b`。
5. 回到 DevEco 签名配置页，填写对应密钥库、别名、密码、证书链与 Profile，绑定 `default` 产品后保存并构建。

`.p12`、证书和 Profile 必须来自同一套配置。不要编辑平台签发的 Profile 内容，编辑后其签名会失效。

参考：[官方应用签名指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-signing)、[申请调试 Profile](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/agc-help-debug-profile-0000002248181278)。

## 本地校验 debug 签名

构建后使用项目提供的校验脚本：

```sh
python3 scripts/verify-debug-signature.py \
  --hap entry/build/default/outputs/default/entry-default-signed.hap
```

同时核对连接设备是否属于该 Profile：

```sh
python3 scripts/verify-debug-signature.py \
  --hap entry/build/default/outputs/default/entry-default-signed.hap \
  --target "$RECORDER_TARGET"
```

脚本调用 SDK 官方 `hap-sign-tool` 校验 HAP 和 Profile，检查完整性、包名、debug 类型及有效期；传入 `--target` 时还会核对设备绑定。过程文件放在临时目录中并自动清理，不在项目中生成校验报告，也不输出设备标识或密码。

本地密码学校验成功不代表目标系统一定信任这套证书。是否可安装，以设备的安装返回值为准。

## 安装、启动与使用

```sh
python3 scripts/install-device.py \
  --target "$RECORDER_TARGET" \
  --hap entry/build/default/outputs/default/entry-default-signed.hap
```

也可以使用 HDC：

```sh
hdc -t "$RECORDER_TARGET" install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc -t "$RECORDER_TARGET" shell aa start -a EntryAbility -b com.personal.desktoprecorder
```

打开清录后，选择分辨率和视频码率，点击 **开始录制**，在系统授权弹窗中选择整个屏幕。点击 **停止并保存** 后，可在录制列表播放或导出。重要视频应先导出；卸载应用或清除应用数据会删除应用私有目录中的录制。

常见问题：

| 现象 | 检查方式 |
| --- | --- |
| 安装提示 `9568257 / fail to verify pkcs7 file` | 检查是否使用目标设备认可的 HarmonyOS 调试签名，而非任意自签名 / 上游测试证书 |
| 已生成证书但没有 signed HAP | 保存签名配置，并检查 `default` 产品已绑定同名 signingConfig |
| 修改包名或换设备后安装失败 | 更新匹配包名与目标设备的 debug Profile |
| 开始时提示参数无效 | 检查模块是否仍为 `2in1`，码率是否在 1–30 Mbps 内 |
| 麦克风不可用 | 检查麦克风授权，或关闭麦克风讲解 |

## Git 日常使用

`main` 保存可构建源码，功能或修复使用 `codex/` 前缀分支，通过 Pull Request 合入。

```sh
git switch main
git pull --ff-only origin main
git switch -c codex/your-change

# 修改完成后
python3 scripts/check-repository.py
bash scripts/test.sh
bash scripts/build.sh
git add <本次修改的源码路径>
git diff --cached
git commit -m "feat: describe the change"
git push -u origin codex/your-change
gh pr create --base main --fill
```

仓库忽略本机签名配置、证书私钥、设备资料、录制样本、HAP、构建缓存和生成的测试报告。`scripts/check-repository.py` 检查已跟踪文件，避免将这些本机材料提交。

打包已提交源码：

```sh
python3 scripts/package-source.py
```

生成的 ZIP 位于 `artifacts/`，来自当前 Git 提交。未提交修改不会被静默打包；修改源码后应先提交再打包。

## 自动检查与构建

GitHub Actions 包含三个工作流：

- **Source checks**：分支推送、Pull Request 或手动触发时，检查仓库文件并运行自动化测试。使用独立安装的 TypeScript 4.9.5，无需在 Linux runner 安装 DevEco。不生成或上传测试报告文件。
- **Build unsigned HAP**：手动触发，使用带 `self-hosted / macOS / deveco` 标签且已安装 DevEco SDK 的专用 runner，隔离构建 release 模式未签名 HAP，并上传完整发布附件。
- **Publish preview release**：在现有版本标签上手动运行，隔离构建后创建 GitHub prerelease。只在发布步骤授予 `contents: write`。这两个构建工作流需要先配置上述 runner；它们不包含或上传个人调试签名材料。细节见 [打包细则](docs/RELEASING.md)。

本机可运行 `bash scripts/test.sh`。自动化测试模拟系统依赖，不能替代真实电脑上的系统授权、录屏与播放检查。

## 功能边界

- 通过系统授权录制；隐私窗口、受保护画面与系统禁止采集的音频仍受操作系统限制。
- 使用系统编码器，帧率由系统管理，不承诺固定 60 fps 或纯 CPU 编码。
- 支持系统声音采集与麦克风开关，没有独立的系统声音静音开关。
- 暂不提供暂停、剪辑、多屏拼接或全局快捷键。
- 正常最小化不会主动停止录制；强制终止或关机可能留下 `.part.mp4`，不能保证一定可修复。
- 故障诊断只记录调用阶段、配置与错误，不记录画面、声音，不上传。

## 接口资料

- [OpenHarmony AVScreenCaptureRecorder](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-media-kit/arkts-apis-media-AVScreenCaptureRecorder.md)
- [OpenHarmony 录屏配置](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-media-kit/arkts-apis-media-i.md)
