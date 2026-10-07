# 导入文件示例

`course.csv` 是可直接导入的 UTF-8 CSV 示例。首行是列名，课程名称、星期、节次为必填列；教师、教室、周次和颜色可选。周次支持 `1-16周`、`单周`、`双周` 和 `1,3,5`。

XLSX 使用相同的首行列名。旧版二进制 `.xls` 不在支持范围内，请在教务系统中另存为 `.xlsx` 或 `.csv`。

ICS 导入支持明确的本地浮动 `DTSTART`/`DTEND` 和每周 `RRULE`（`FREQ=WEEKLY;INTERVAL=1`，可带 `BYDAY`、`COUNT` 或 `UNTIL`）。带 `TZID`/UTC 的时间、跨日事件、无法映射到学期节次的时间以及其他 RRULE 会产生诊断并跳过，不会静默猜测。
