# 打包与 GitHub Release

## 分发规则

清录参考 [ClashBox 1.7.4 官方 Release](https://github.com/xiaobaigroup/ClashBox/releases/tag/1.7.4) 提供未签名 HAP。清录只面向 `2in1` / API 24，并附带源码和完整安装指引；不承诺第三方签名安装器支持鸿蒙电脑。

| 场景 | 构建与签名 | 产物去向 |
| --- | --- | --- |
| GitHub 开发预览版 | 干净源码、release 模式、未签名 | GitHub Release，用户自行签名 |
| 本机真机调试 | debug 或 release 模式、本人设备有效的 debug Profile | 本机 HDC / DevEco 安装，signed HAP 不上传 |
| 应用市场正式发行 | 按当前华为发布流程使用发布身份、对应 Profile 与 APP 打包流程 | AppGallery Connect 审核分发，另行准备 |

`.hap` 是应用模块包，`.app` 是应用发布包。不能将 HAP 改扩展名当作 APP；GitHub 上创建 Release 也不等于取得华为发布签名。参见 [华为发布应用](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-publish-app) 和 [签名指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-signing)。

## 本地生成

修改版本时同步 `AppScope/app.json5` 的 `versionName` 与单调递增的 `versionCode`，更新版本说明、README 和安装示例。通过必要检查后先提交：

```sh
python3 scripts/check-repository.py
bash scripts/test.sh
git add <本次源码与文档路径>
git commit -m "release: prepare version X.Y.Z"
python3 scripts/package-release.py
```

脚本只接受干净的 Git 工作区；用 `git archive HEAD` 在临时目录重建源码，使用无签名模板，设置 `RECORDER_BUILD_MODE=release`，不读取当前工作区被忽略的签名配置。临时目录在结束时清理；不会修改本机证书，也不会生成测试报告。

打包会检查 HAP ZIP、版本和包名、`buildMode=release`、`debug=false`、仅 `2in1`、无外部模块依赖、无源码映射 / 签名材料，并调用 SDK 签名工具确认未签名。编译模式检查不能替代目标电脑上的录屏验证。

输出目录为 `artifacts/release-X.Y.Z/`，仅含：

```text
Qinglu-X.Y.Z-2in1-api24-unsigned.hap
Qinglu-X.Y.Z-source.zip
INSTALL.md
release-manifest.json
SHA256SUMS
```

Manifest 记录源码提交、版本、设备范围、编译 SDK 与附件摘要。`SHA256SUMS` 覆盖除自身之外的四个文件。目录已存在时脚本拒绝覆盖，避免误替换已经分享的产物；需要重新打包时保留或移走旧目录。编译工具可能嵌入构建时间等信息，不承诺不同机器的 HAP 逐字节一致。

## 发布

确认文件清单与 Manifest 对应当前提交，不要上传 `artifacts/` 中其它历史包、个人 signed HAP、证书或设备资料。`0.x` 版本作为预览版标记 prerelease。首次发布 `0.1.2`：

```sh
git tag -a v0.1.2 -m "Qinglu 0.1.2 preview"
git push origin main
git push origin v0.1.2

gh release create v0.1.2 --verify-tag --prerelease \
  --title "清录 0.1.2 · 鸿蒙电脑预览版" \
  --notes-file docs/releases/v0.1.2.md \
  artifacts/release-0.1.2/Qinglu-0.1.2-2in1-api24-unsigned.hap \
  artifacts/release-0.1.2/Qinglu-0.1.2-source.zip \
  artifacts/release-0.1.2/INSTALL.md \
  artifacts/release-0.1.2/release-manifest.json \
  artifacts/release-0.1.2/SHA256SUMS
```

创建后读取 Release 的 tag、附件名称 / 大小，重新下载附件核对 SHA-256。更新说明可以修改，已发布版本的源码标签与二进制不要静默替换；代码修复应提升版本发布。

## GitHub Actions

- `Source checks`：推送及 PR 的源码检查与自动化测试，不上传测试报告。
- `Build unsigned HAP`：手动在带 `self-hosted / macOS / deveco` 标签的 runner 上运行，调用同一本地打包脚本，上传完整的五项发布附件。
- `Publish preview release`：在已有版本标签上手动运行；同样先隔离构建，再由 GitHub 托管 runner 使用本仓库的临时 `GITHUB_TOKEN` 创建 prerelease。仅发布步骤具备 `contents: write`，无需上传个人签名或 PAT。

后两个工作流需要已安装相同 DevEco / SDK 的专用 macOS runner。当前未提供 runner 的自动注册或远端执行能力，未配置时不能声称云端构建可用。不要在不受信任的 PR 上运行带本机开发者环境的 runner。Release 权限与仓库可见性保持一致；私有仓库的附件仅对获授权用户可见。
