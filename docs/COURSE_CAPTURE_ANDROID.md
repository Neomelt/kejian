# Android 企业微信课表读取

Android 端提供一个用户主动触发的读取通道，目标页面是企业微信
(`com.tencent.wework`) 内的“个人课表”。应用不拦截网络请求，也不读取密码、Cookie
或验证码。

## 用户流程

1. 在课间的导入页点击“启用辅助功能”，在系统设置中启用“课间 - 读取企业微信个人课表”。
2. 按提示授予“显示在其他应用上层”权限。悬浮窗只显示“读取课表”按钮。
3. 登录企业微信并打开个人课表，确认当前页包含课程和周次信息。
4. 点击悬浮窗按钮（或返回课间点击“读取”）。读取结果通过 `dev.kejian/course_capture`
   channel 回到 Flutter，先预览再由用户确认导入。

## Flutter channel contract

Native → Dart event:

```text
channel: dev.kejian/course_capture
method: captureResult
arguments: {
  sourcePackage: String,
  pageTitle: String,
  rawText: String,
  cells: [{id: String, text: String, children: [String]}],
  courses: [{id, sourceNodeId, rawText, title, teacher, room, credits,
             weekday, startSlot, endSlot, weeks, parity,
             duplicateGroupKey, inActiveWeek}],
  diagnostics: [String],
  activeWeek: int?
}
```

Dart → Native methods:

| Method | Result |
| --- | --- |
| `status` | `{accessibilityEnabled, overlayEnabled, targetPackage}` |
| `openAccessibilitySettings` | Opens Android accessibility settings |
| `openOverlaySettings` | Opens this app's overlay permission page |
| `capture` | Triggers one capture from the active accessibility window |
| `openTargetApp` | Launches enterprise WeChat if installed |
| `ready` | Marks the Flutter listener ready and returns the latest pending capture |

The parser keeps courses that share the same weekday and slot in the same
`duplicateGroupKey`; the Flutter preview can show one compact card with a count and
expand it to the individual courses. `inActiveWeek == false` is the signal for a
greyed-out non-current-week course. A null value means the page did not expose a
reliable current week.

The native bridge retains the latest capture in memory until the Dart side calls
`ready` and consumes it. This avoids losing a result while the Flutter activity is
being recreated; no capture is persisted to disk.

An earlier import may have saved a raw course title while leaving room, teacher, credits,
or the week range empty or incorrect. Updating the app does not rewrite those saved rows;
read the personal timetable again and choose “替换当前学期” after checking the field preview.

## Current limits

The service is deliberately allow-listed to `com.tencent.wework` and only captures after a
visible button tap. The parser accepts both the observed private-use marker layout and the
compact no-space layout such as `…9-16周本部…老师…2.0选修`; it reports other shapes as
diagnostics. PDF/share import remains the fallback for schools whose page does not expose
accessible text.
