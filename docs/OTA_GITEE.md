# Android 更新通道

课间的 Android 更新流程是：应用从构建时注入的 HTTPS 地址读取 `update.json`，比较 `versionCode`，下载清单中的 APK，校验 SHA-256，然后交给 Android 系统安装器。安装器会要求用户确认一次；应用不会静默安装，也不会读取或保存 Gitee Token。

应用侧更新地址通过下面的 dart define 注入：

```text
KEJIAN_UPDATE_MANIFEST_URL=https://gitee.com/<owner>/<repo>/raw/<branch>/update.json
```

当前仓库的 [release-gitee.yml](../.github/workflows/release-gitee.yml) 会在 `v*` tag 上：

1. 运行分析和测试；
2. 使用 GitHub Secrets 中的固定 Android 发布签名构建 APK；
3. 创建 Gitee Release 并上传 APK；
4. 生成包含 APK 地址、版本号、文件大小和 SHA-256 的 `update.json`；
5. 上传 Release 清单，并更新 Gitee 仓库根目录的 `update.json`，让应用使用稳定地址读取最新版本。

GitHub 仓库需要配置以下 Repository variables：

- `GITEE_OWNER`：Gitee 用户或组织地址，可选；当前默认为 `Xlqmu`；
- `GITEE_REPO`：Gitee 仓库路径，可选；当前默认为 `kejian-mirror`。
- `GITEE_BRANCH`：Gitee 镜像分支，可选，默认 `master`。

需要配置以下 Repository secrets：

- `GITEE_TOKEN`：可以创建 Release 和上传附件的 Gitee Token；
- `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`：同一把 Android 发布签名。

第一次从开发签名切换到发布签名时，Android 会把它视为不同应用，通常需要先卸载开发版；卸载前应从应用内导出 JSON 备份。此后所有 CI 版本必须继续使用同一把发布签名，否则 Android 不会允许覆盖升级。

更新源必须使用用户可以直连的 HTTPS 主机。Gitee 适合作为国内直连源；GitHub 只负责源码和 CI，不作为手机 APK 下载源。应用的 HTTP 客户端明确使用直连模式，不读取系统代理配置；网络是否可达仍取决于 Gitee 服务和用户所在网络。
