# 课间的首版边界

课间是一个本地优先的移动端课程表。当前首版把课程数据、周次规则、调课覆盖、导入导出、提醒和备份作为完整闭环；教务系统登录、验证码、会话保持和学校专用页面解析通过后续 `SourceAdapter` 接入。

## 数据流

```text
文件 / 后续教务适配器
        ↓
raw bytes → parser → diagnostics + preview → merge / replace confirmation
        ↓
Term + Course + LessonOverride + AppSettings
        ↓
本地存储 → occurrence resolver → weekly UI / reminders / exports
```

课程系列和单次课程覆盖分开存储。编辑一门课程不会意外改写某一次调课；取消、换教室、换节次和补课都通过 `LessonOverride` 表达。导入默认合并并保留原有课程，替换操作必须先生成快照并让用户确认删除数量。

## 导入边界

CSV、XLSX、ICS 和课间 JSON 备份在本机解析。解析器只接受能够精确表达的周次、时间和重复规则，对旧版 XLS、跨日课程、时区 ICS 和不支持的 RRULE 给出诊断，不猜测数据。自动教务导入不会假设所有学校共有同一套页面或接口。

## 移动端发布

项目只维护 Android 和 iOS。Android CI 产出 release APK；macOS CI 先构建 iOS，再把 `Runner.app` 归档为未签名 IPA。安装签名、Apple provisioning profile 和正式 Android keystore 不写入仓库。

