# 清录 · OpenHarmony 桌面录屏

独立的原生 ArkTS / Stage 应用，包名 `com.personal.desktoprecorder`，不依赖当前工作区的项目。当前设备版面向用户提供的 API 24 / 2in1 电脑。

## 第一版功能

- 调用系统 `AVScreenCaptureRecorder` 采集整个桌面，H.264 + AAC / MP4。
- 原屏像素、长边最高 2560 / 1920 三档，保留原比例、不放大低分辨率屏幕，编码尺寸对齐到偶数。
- 标准 / 高码率，8–20 / 8–30 Mbps，根据输出像素数计算，使用目标设备实际通过初始化的范围。
- 独立的视频码率选择：自动匹配、2/4/8/12/20/30 Mbps 预设，或自定义 1–30 Mbps（最多两位小数）；手动码率不改变所选分辨率。
- 码率滑杆与数值输入同步，提供每分钟体积参考；低码率通常减少文件体积，也会损失细节。实际编码体积随画面内容变化，参考值不代表固定文件大小。
- 系统声音由录屏服务管理，可选麦克风讲解，按需申请麦克风权限。
- 计时、停止并保存、录制列表、应用内预览、系统文件选择器导出。
- 系统授权取消、系统控制条停止、中断、媒体错误、重复点击的生命周期处理。
- 保存前读取视频元数据，确认有视频宽高和正时长；未完整封装文件以 `.part.mp4` 保留，不误报成功。
- 不接入网络，不上传录制内容。

## 环境与构建

当前设备版 0.1.2，最低 API 24，对应 `6.1.1(24)`；本机使用 DevEco 内置 SDK 26.0.0.105、Hvigor 6.26.8、内置 Node 和 JBR 编译。业务录屏接口本身从 API 12 起可用，当前包的安装要求以 API 24 为准。模块仅声明 `2in1`，构建脚本检查此项，防止 IDE 同步将应用改为移动端兼容模式。

```sh
bash scripts/test.sh
bash scripts/build.sh
```

脚本默认 DevEco 在 `/Applications/DevEco-Studio.app/Contents`，可设置 `RECORDER_DEVECO` 修改。
设备版使用 DevEco 内置 SDK。首次在其它电脑打开时，在 DevEco Studio 配置 SDK；`local.properties` 不进入源码包。

构建输出：`entry/build/default/outputs/default/entry-default-unsigned.hap`。未签名 HAP 不能直接按普通签名应用安装。

Git 仓库只跟踪不含签名信息的 `build-profile.template.json5`。构建脚本在配置缺失时复制为本机 `build-profile.json5`；自动签名生成的配置、密钥、设备资料和录制样本均被 Git 忽略。

## 选择更小的视频体积

在“录制设置 → 视频码率”中选择预设或“自定义”。例如，4 Mbps 的音视频体积参考约 31.4 MB/分钟，2 Mbps 约 16.4 MB/分钟。也可拖动滑杆，或直接输入 2.5、12.34 等数值。录制期间设置锁定，下次开始时应用新值。选择“自动匹配”恢复原有画质策略。

上述为编码目标的体积参考，已计入当前音轨码率，未计入容器开销；画面静止时，实际视频可能明显小于参考值。原屏文字清晰度优先时，可以保留分辨率并先试 8 或 12 Mbps；对体积优先时，再降低码率或分辨率。

当前真机拒绝标准 OpenHarmony 测试签名（`9568257: fail to verify pkcs7 file`）。请在 DevEco Studio 中打开此目录，进入“文件 → 项目结构 → 签名配置”，勾选“自动生成签名文件”和“使用 HarmonyOS 签名”，登录华为开发者账号，连接目标设备后为此包名生成调试 Profile。设备版本字符串虽为 OpenHarmony，不能据此推断它信任上游测试证书。

仅当目标为信任 OpenHarmony 标准测试证书的其它开发系统时，可以运行下面的备用脚本；它不是当前设备的安装方案：

```sh
python3 scripts/sign-openharmony-test.py
```

输出 `artifacts/Qinglu-0.1.0-openharmony-test-signed.hap`，并调用官方工具验证签名。脚本仅使用 SDK 自带公开测试身份，不修改 SDK 模板、密钥或系统配置。此测试签名有效期 30 天，不代表华为 HarmonyOS、企业设备或其它发行版会信任它。正式安装应使用目标发行版认可的应用证书和匹配包名的 provision/profile。

## 安装与试录

目标机器须开启并授权 HDC 调试。用本机 SDK 下的 `hdc`，多设备时务必指定目标：

```sh
hdc list targets
hdc -t <目标> shell param get const.ohos.fullname
hdc -t <目标> shell param get const.ohos.apiversion
hdc -t <目标> install entry/build/default/outputs/default/entry-default-signed.hap
hdc -t <目标> shell aa start -a EntryAbility -b com.personal.desktoprecorder
```

1. 打开清录，先选 1080p 和高码率。
2. 点击开始，在系统弹窗确认录屏，选择整个屏幕。API 22+ 通过 `SCREEN_ONLY` 只展示屏幕；API 12–21 走主屏录制。
3. 在桌面和其它应用之间切换，滚动文字页面、移动窗口并播放动态画面；有声音需求时播放允许录制的音频。
4. 最小化清录，连续录制至少 5 分钟；返回停止，或使用系统控制条停止。
5. 播放并导出 MP4；检查文件可播放、时长、实际像素尺寸、画面比例、音画同步和滚动流畅度。
6. 复测麦克风允许/拒绝、系统授权取消、重复录制、系统停止和磁盘不足场景。

## 当前边界

- 已进行本地编译和模拟系统依赖的自动化测试。真实设备安装、系统授权、整桌面内容、实际编码帧率、声音和长时间后台录制须在目标设备验收。
- 已实读目标系统为 `OpenHarmony-6.1.1.135 / API 24`，设备类型 `2in1`；系统具备接口不等于所有发行版都具备实际录屏能力。应用启动录制时检查系统能力与版本。
- 使用系统编码器，帧率由系统管理，本版不提供 60 fps 或纯 CPU 编码承诺。
- 主屏尺寸用于编码设置；第一版验收以主屏为准。其它显示器与主屏比例不同时，选择其它屏幕的适配需实测。
- 受保护内容、隐私窗口与系统禁止采集的音频受操作系统限制；本应用不解除这些限制。
- 支持停止后保留、预览和导出；本版没有暂停、剪辑、多屏拼接或全局快捷键。
- 正常最小化不会主动停止录制；强制终止应用或关机会留下待检查的原始文件，无法保证 MP4 一定可修复。
- 故障诊断保存在应用私有目录的 `recorder-diagnostics.jsonl`，只记录调用阶段、配置尺寸、码率与错误，不记录画面和声音。通过 `aa start ... --pb qingluValidateConfig true` 可仅检查初始化而不开始录屏；`qingluConfigVariant` 是开发诊断参数，不属于界面录制流程。
- 录制先存在应用私有目录。卸载或清除应用数据会移除这些文件，请先导出重要视频。
- 系统音频采集受应用与系统音频策略控制；本版没有独立的系统声音静音开关。

## 实现依据

- [OpenHarmony AVScreenCaptureRecorder 官方 API](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-media-kit/arkts-apis-media-AVScreenCaptureRecorder.md)
- [OpenHarmony 录屏配置官方 API](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-media-kit/arkts-apis-media-i.md)
- 本机 SDK 中的 `@ohos.multimedia.media.d.ts`、文件选择器与文件系统类型声明。

`tests/recorder.test.cjs` 在 Node 中转译实际业务源码，以模拟媒体与文件系统验证错误处理和事件顺序；这些测试不能替代真实屏幕录制测试。
