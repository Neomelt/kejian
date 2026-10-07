# 课间

一个本地优先、无广告的移动端课程表。项目暂时聚焦于课表本身：周视图、课程编辑、单双周、调课覆盖、导入导出、备份和本地提醒。教务系统自动跳转与具体学校适配器留在后续版本。

## 开发

需要 Flutter stable（Dart 3.13+）。

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Android 构建：

```bash
flutter build apk --release
```

Android 站外更新和 GitHub Actions 同步 Gitee Release 的配置见
[`docs/OTA_GITEE.md`](docs/OTA_GITEE.md)。更新清单地址通过
`KEJIAN_UPDATE_MANIFEST_URL` 注入，APK 下载使用 HTTPS、SHA-256 校验，并由系统安装器要求用户确认。

iOS 构建需要 macOS runner 和 Apple 签名环境。CI 会生成未签名的 `KeJian.ipa` 归档，之后可按用户自己的签名方式处理。

## 当前边界

导入器优先支持 CSV、XLSX、ICS 和本应用 JSON 备份。教务系统登录、验证码、会话保持和学校专用页面解析未在当前版本假设为通用能力。
