import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../domain/models.dart' as model;
import '../services/reminder_service.dart';
import '../services/app_update_service.dart';
import 'app_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});
  final ScheduleController controller;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _updater = AppUpdateService();
  bool _checkingUpdate = false;
  bool _installingUpdate = false;
  String? _updateMessage;

  Future<void> _checkForUpdate() async {
    if (_checkingUpdate || _installingUpdate) return;
    setState(() {
      _checkingUpdate = true;
      _updateMessage = null;
    });
    try {
      final result = await _updater.checkForUpdate();
      if (!mounted) return;
      if (!result.available) {
        setState(() => _updateMessage = '当前已是最新版本');
        return;
      }
      final manifest = result.manifest;
      final install = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('发现新版本 ${manifest.versionName}'),
          content: Text(
            manifest.notes.isEmpty
                ? '将下载并校验 APK，随后打开系统安装确认页。'
                : manifest.notes,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('稍后')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('下载并安装')),
          ],
        ),
      );
      if (install != true || !mounted) return;
      setState(() => _installingUpdate = true);
      final path = await _updater.download(manifest);
      await _updater.install(path);
      if (mounted) setState(() => _updateMessage = '已打开系统安装确认页');
    } on AppUpdateException catch (error) {
      if (mounted) setState(() => _updateMessage = error.message);
    } finally {
      if (mounted) {
        setState(() {
          _checkingUpdate = false;
          _installingUpdate = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.controller.data.settings;
    return ListView(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 32),
        children: [
          Text('设置',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1)),
          const SizedBox(height: 22),
          _Section(title: '学期', children: [
            for (final term in widget.controller.data.terms)
              ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(Icons.school_outlined,
                          color: Theme.of(context).colorScheme.primary)),
                  title: Text(term.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle:
                      Text('${term.weekCount} 周 · ${term.slots.length} 个节次'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (term.id == widget.controller.activeTerm?.id)
                      const Chip(label: Text('当前')),
                    IconButton(
                        tooltip: '编辑',
                        onPressed: () => showTermEditor(
                            context, widget.controller,
                            initial: term),
                        icon: const Icon(Icons.edit_outlined)),
                    IconButton(
                        tooltip: '删除学期',
                        onPressed: () async {
                          final ok = await _confirm(
                              context, '删除这个学期？', '学期内的课程和调课记录也会删除。');
                          if (ok && context.mounted) {
                            await widget.controller.deleteTerm(term.id);
                          }
                        },
                        icon: const Icon(Icons.delete_outline))
                  ]),
                  onTap: () => widget.controller.selectTerm(term.id)),
            ListTile(
                leading: const Icon(Icons.add),
                title: const Text('新建学期'),
                onTap: () => showTermEditor(context, widget.controller)),
          ]),
          const SizedBox(height: 14),
          _Section(
            title: '外观',
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: const Text('主题'),
                subtitle: Text(themeLabel(settings.darkMode)),
                trailing: DropdownButton<model.ThemeMode>(
                  value: settings.darkMode,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                        value: model.ThemeMode.system, child: Text('跟随系统')),
                    DropdownMenuItem(
                        value: model.ThemeMode.light, child: Text('浅色')),
                    DropdownMenuItem(
                        value: model.ThemeMode.dark, child: Text('深色')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      widget.controller.updateSettings(themeMode: value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            title: '提醒',
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                secondary: const Icon(Icons.notifications_none_outlined),
                title: const Text('上课提醒'),
                subtitle: Text(_reminderSubtitle(settings.remindersEnabled,
                    widget.controller.notificationStatus)),
                value: settings.remindersEnabled,
                onChanged: (value) async {
                  if (value) {
                    await widget.controller.requestReminderPermission();
                  }
                  await widget.controller
                      .updateSettings(remindersEnabled: value);
                },
              ),
              if (settings.remindersEnabled)
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 72, right: 16),
                  title: const Text('提前时间'),
                  trailing: DropdownButton<int>(
                    value: settings.reminderMinutes,
                    underline: const SizedBox.shrink(),
                    items: const [5, 10, 15, 30]
                        .map((value) => DropdownMenuItem(
                            value: value, child: Text('$value 分钟')))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        widget.controller
                            .updateSettings(reminderMinutes: value);
                      }
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(title: '数据', children: [
            ListTile(
                leading: const Icon(Icons.history_outlined),
                title: const Text('历史快照'),
                subtitle: const Text('在导入和替换前保留数据'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showSnapshots(context, widget.controller)),
            ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('清空当前学期课程'),
                onTap: widget.controller.activeTerm == null
                    ? null
                    : () => _clearCourses(context)),
          ]),
          const SizedBox(height: 14),
          _Section(title: '关于', children: [
            const ListTile(
                leading: Icon(Icons.auto_awesome_outlined),
                title: Text('课间'),
                subtitle: Text('本地优先 · 无广告 · 0.1.0')),
            ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('教务系统适配'),
                subtitle: const Text('当前通过导出文件导入，自动跳转将在后续版本接入'))
          ]),
          const SizedBox(height: 14),
          _Section(title: '更新', children: [
            ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: const Text('检查更新'),
              subtitle: Text(
                _updateMessage ??
                    (_updater.configured
                        ? '从配置的 HTTPS 更新源获取 APK'
                        : '当前构建未配置更新源'),
              ),
              trailing: _checkingUpdate || _installingUpdate
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _updater.configured ? _checkForUpdate : null,
            ),
          ]),
        ]);
  }

  String _reminderSubtitle(bool enabled, ReminderStatus status) {
    if (!enabled) return '已关闭';
    if (!status.supported) return status.message ?? '等待系统提醒权限';
    if (!status.authorized) return '需要允许通知权限';
    return status.pendingCount == 0
        ? '已开启，当前没有待提醒课程'
        : '已开启，已安排 ${status.pendingCount} 条提醒';
  }

  Future<void> _clearCourses(BuildContext context) async {
    final ok = await _confirm(context, '清空当前学期课程？', '会先创建快照，之后仍可从历史快照恢复。');
    if (ok) {
      final term = widget.controller.activeTerm;
      if (term != null) {
        await widget.controller.createSnapshot();
        final keep = widget.controller.data.courses
            .where((course) => course.termId != term.id)
            .toList();
        await widget.controller.restoreData(model.ScheduleData(
            terms: widget.controller.data.terms,
            activeTermId: widget.controller.data.activeTermId,
            courses: keep,
            overrides: widget.controller.data.overrides
                .where(
                    (item) => keep.any((course) => course.id == item.courseId))
                .toList(),
            settings: widget.controller.data.settings));
      }
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700))),
        Card(child: Column(children: children))
      ]);
}

Future<bool> _confirm(
        BuildContext context, String title, String message) async =>
    (await showDialog<bool>(
        context: context,
        builder: (context) =>
            AlertDialog(title: Text(title), content: Text(message), actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('确定'))
            ]))) ??
    false;

Future<void> showTermEditor(BuildContext context, ScheduleController controller,
    {model.Term? initial}) async {
  final result = await showModalBottomSheet<model.Term>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          TermEditor(initial: initial, controller: controller));
  if (result != null) await controller.saveTerm(result);
}

class TermEditor extends StatefulWidget {
  const TermEditor({super.key, this.initial, required this.controller});
  final model.Term? initial;
  final ScheduleController controller;
  @override
  State<TermEditor> createState() => _TermEditorState();
}

class _TermEditorState extends State<TermEditor> {
  late final TextEditingController name;
  late final TextEditingController count;
  late DateTime monday;
  late List<model.TimeSlot> slots;
  String? error;
  @override
  void initState() {
    super.initState();
    final term = widget.initial;
    name = TextEditingController(text: term?.name ?? '2026 春季学期');
    count = TextEditingController(text: '${term?.weekCount ?? 18}');
    monday = term?.startMonday ?? _nextMonday(DateTime.now());
    slots = List.of(term?.slots ?? model.Term.defaultSlots());
  }

  @override
  void dispose() {
    name.dispose();
    count.dispose();
    super.dispose();
  }

  Future<void> pickMonday() async {
    final value = await showDatePicker(
        context: context,
        initialDate: monday,
        firstDate: DateTime(2020),
        lastDate: DateTime(2035),
        helpText: '选择开学周',
        cancelText: '取消',
        confirmText: '确定');
    if (value == null) return;
    final snapped = _mondayOf(value);
    setState(() {
      monday = snapped;
      error =
          value.weekday == DateTime.monday ? null : '已自动调整为周一：${_date(monday)}';
    });
  }

  void save() {
    final weekCount = int.tryParse(count.text.trim());
    if (name.text.trim().isEmpty) return setState(() => error = '请填写学期名称');
    if (weekCount == null || weekCount < 1 || weekCount > 52) {
      return setState(() => error = '周数应为 1–52');
    }
    try {
      Navigator.pop(
          context,
          model.Term(
              id: widget.initial?.id ??
                  'term-${DateTime.now().microsecondsSinceEpoch}',
              name: name.text.trim(),
              startMonday: monday,
              weekCount: weekCount,
              slots: slots));
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final usedSlots = widget.controller.data.courses
        .where((course) => course.termId == widget.initial?.id)
        .expand((course) =>
            [for (var i = course.startSlot; i <= course.endSlot; i++) i])
        .toSet();
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.initial == null ? '新建学期' : '编辑学期',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: '学期名称',
                    prefixIcon: Icon(Icons.school_outlined))),
            const SizedBox(height: 12),
            TextField(
                controller: count,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: '周数', suffixText: '周')),
            const SizedBox(height: 12),
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.date_range_outlined),
                title: const Text('开学周一'),
                subtitle: Text(_date(monday)),
                trailing: const Icon(Icons.chevron_right),
                onTap: pickMonday),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                    child: Text('节次时间',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700))),
                TextButton.icon(
                  onPressed: () => setState(() {
                    final start =
                        (slots.last.endMinutes + 10).clamp(0, 1430).toInt();
                    final end =
                        (slots.last.endMinutes + 55).clamp(1, 1440).toInt();
                    slots.add(model.TimeSlot(
                        index: slots.length + 1,
                        startMinutes: start,
                        endMinutes: end));
                  }),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final slot in slots)
              _SlotEditorRow(
                slot: slot,
                onChanged: (newSlot) =>
                    setState(() => slots[slots.indexOf(slot)] = newSlot),
                onDelete: slots.length <= 1 || usedSlots.contains(slot.index)
                    ? null
                    : () => setState(() {
                          slots.remove(slot);
                          slots = [
                            for (var i = 0; i < slots.length; i++)
                              model.TimeSlot(
                                  index: i + 1,
                                  startMinutes: slots[i].startMinutes,
                                  endMinutes: slots[i].endMinutes)
                          ];
                        }),
              ),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 18),
            SizedBox(
                width: double.infinity,
                child:
                    FilledButton(onPressed: save, child: const Text('保存学期'))),
          ],
        ),
      ),
    );
  }
}

class _SlotEditorRow extends StatelessWidget {
  const _SlotEditorRow(
      {required this.slot, required this.onChanged, required this.onDelete});
  final model.TimeSlot slot;
  final ValueChanged<model.TimeSlot> onChanged;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
              width: 28,
              child: Text('${slot.index}',
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(
              child: _TimeField(
                  minutes: slot.startMinutes,
                  onChanged: (value) {
                    if (value < slot.endMinutes) {
                      onChanged(model.TimeSlot(
                          index: slot.index,
                          startMinutes: value,
                          endMinutes: slot.endMinutes));
                    }
                  })),
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 7), child: Text('–')),
          Expanded(
              child: _TimeField(
                  minutes: slot.endMinutes,
                  onChanged: (value) {
                    if (value > slot.startMinutes) {
                      onChanged(model.TimeSlot(
                          index: slot.index,
                          startMinutes: slot.startMinutes,
                          endMinutes: value));
                    }
                  })),
          IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: '删除节次'),
        ],
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.minutes, required this.onChanged});
  final int minutes;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final value = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
            helpText: '选择时间',
            cancelText: '取消',
            confirmText: '确定');
        if (value != null) onChanged(value.hour * 60 + value.minute);
      },
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: .55),
              borderRadius: BorderRadius.circular(12)),
          child: Text(formatTime(minutes), textAlign: TextAlign.center)));
}

Future<void> showSnapshots(
    BuildContext context, ScheduleController controller) async {
  final snapshots = await controller.listSnapshots();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('历史快照',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    if (snapshots.isEmpty)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('还没有快照'))),
                    for (final snapshot in snapshots)
                      ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(_snapshotDate(snapshot.createdAt)),
                          subtitle: Text('快照 #${snapshot.id}'),
                          trailing: TextButton(
                              onPressed: () async {
                                final ok = await _confirm(
                                    context, '恢复这个快照？', '当前数据会先再生成一个快照。');
                                if (ok && context.mounted) {
                                  await controller.restoreSnapshot(snapshot.id);
                                  Navigator.pop(context);
                                }
                              },
                              child: const Text('恢复')))
                  ]))));
}

String _snapshotDate(DateTime date) =>
    '${date.toLocal().year}-${date.toLocal().month.toString().padLeft(2, '0')}-${date.toLocal().day.toString().padLeft(2, '0')} ${date.toLocal().hour.toString().padLeft(2, '0')}:${date.toLocal().minute.toString().padLeft(2, '0')}';
String _date(DateTime date) => '${date.year}年${date.month}月${date.day}日';
DateTime _mondayOf(DateTime date) => model
    .dateOnly(date)
    .subtract(Duration(days: date.weekday - DateTime.monday));
DateTime _nextMonday(DateTime date) {
  final monday = _mondayOf(date);
  return date.weekday == DateTime.monday
      ? monday
      : monday.add(const Duration(days: 7));
}
