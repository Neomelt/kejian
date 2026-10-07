import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../domain/models.dart' as model;
import '../importing/backup.dart';
import '../importing/exporters.dart';
import '../importing/import_result.dart';
import '../services/course_capture_service.dart';

class ImportPage extends StatefulWidget {
  const ImportPage({super.key, required this.controller});
  final ScheduleController controller;
  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  bool busy = false;
  final CourseCaptureService capture = const CourseCaptureService();
  CourseCaptureStatus captureStatus = const CourseCaptureStatus();
  String? captureNotice;

  @override
  void initState() {
    super.initState();
    capture.listen(_onCapture);
    _refreshCaptureStatus();
  }

  Future<void> _refreshCaptureStatus() async {
    final status = await capture.status();
    if (mounted) setState(() => captureStatus = status);
  }

  Future<void> _openCaptureSettings() async {
    await capture.openAccessibilitySettings();
    if (mounted) _notice('请在系统设置中启用课间的辅助功能服务');
  }

  Future<void> _openOverlaySettings() async {
    await capture.openOverlaySettings();
    if (mounted) _notice('请允许课间显示在其他应用上层');
  }

  Future<void> _openWeCom() async {
    await capture.openTargetApp();
    if (mounted) _notice('请在企业微信打开“个人课表”，再点击悬浮按钮读取');
  }

  Future<void> _captureNow() async {
    final ok = await capture.capture();
    if (!ok && mounted) {
      _notice('请先开启辅助功能，并打开企业微信个人课表');
    }
  }

  Future<void> _onCapture(CourseCaptureResult result) async {
    if (!mounted) return;
    final recognized = result.courses.length;
    setState(() {
      captureNotice = recognized == 0
          ? '读取完成，但没有识别到课程。请确认企业微信停留在“个人课表”。'
          : '读取完成：识别 $recognized 门课程';
    });
    final term = widget.controller.activeTerm;
    if (term == null) {
      _notice('请先创建学期，再导入企业微信课表');
      return;
    }
    final courses = <model.Course>[];
    final diagnostics = [...result.diagnostics];
    for (final item in result.courses) {
      if (item.weekday == null ||
          item.startSlot == null ||
          item.endSlot == null ||
          item.weeks.isEmpty) {
        diagnostics.add('无法定位课程“${item.title}”的星期、节次或周次');
        continue;
      }
      if (item.endSlot! < item.startSlot! ||
          item.endSlot! > term.slots.length) {
        diagnostics.add('课程“${item.title}”的节次超出当前学期设置');
        continue;
      }
      courses.add(model.Course(
        id: 'wecom_${item.id}',
        termId: term.id,
        title: item.title,
        teacher: item.teacher,
        room: item.room,
        weekday: item.weekday!,
        startSlot: item.startSlot!,
        endSlot: item.endSlot!,
        weeks:
            item.weeks.where((week) => week <= term.weekCount).toSet().toList()
              ..sort(),
        color: _captureColor(item.title),
      ));
    }
    final resultForPreview = ImportResult(
      courses: courses,
      diagnostics: [
        ImportDiagnostic(
            message: '来源：${result.pageTitle}，已在本机读取当前页面', isError: false),
        ...diagnostics.map((message) => ImportDiagnostic(message: message)),
      ],
      skippedRows: result.courses.length - courses.length,
      sourceLabel: '企业微信 · ${result.pageTitle}',
    );
    await _showImportPreview(resultForPreview);
  }

  static int _captureColor(String title) {
    var hash = 2166136261;
    for (final unit in title.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    const palette = [
      0xFF147D78,
      0xFF4968A8,
      0xFFB56B36,
      0xFF8B5E83,
      0xFF4F7D63,
      0xFF7A6A42
    ];
    return palette[hash % palette.length];
  }

  Future<void> pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'ics', 'ical', 'json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    setState(() => busy = true);
    try {
      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null) throw const FormatException('无法读取所选文件，请重试。');
      if (file.name.toLowerCase().endsWith('.json')) {
        final text = utf8.decode(bytes);
        final preview = widget.controller.previewRestoreJson(text);
        if (mounted && await _showRestorePreview(preview) == true) {
          await widget.controller.restoreJson(text);
          _notice('备份已恢复');
        }
      } else {
        final result = await widget.controller.importSchedule(file);
        if (mounted) await _showImportPreview(result);
      }
    } catch (error) {
      if (mounted) _notice('导入失败：$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _showImportPreview(ImportResult result) async {
    final replace = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ImportPreview(result: result),
    );
    if (replace == null || result.courses.isEmpty || !mounted) return;
    await widget.controller
        .commitImportedCourses(result.courses, replace: replace);
    _notice(replace ? '已替换当前学期课程' : '已合并 ${result.courses.length} 门课程');
  }

  Future<bool?> _showRestorePreview(model.ScheduleData preview) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('恢复备份？'),
          content: Text(
              '备份包含 ${preview.terms.length} 个学期、${preview.courses.length} 门课程和 ${preview.overrides.length} 条调课记录。当前数据会先生成快照。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('恢复')),
          ],
        ),
      );

  Future<void> exportBackup() async {
    final path = await FilePicker.platform.saveFile(
        fileName: 'kejian-backup.json',
        bytes: encodeScheduleBackupBytes(widget.controller.data));
    if (mounted && path != null) _notice('备份已保存');
  }

  Future<void> exportCourses(String format) async {
    final term = widget.controller.activeTerm;
    if (term == null) return _notice('请先创建学期');
    final bytes = format == 'ics'
        ? exportCoursesIcsBytes(term, widget.controller.data.courses,
            overrides: widget.controller.data.overrides)
        : exportCoursesCsvBytes(term, widget.controller.data.courses);
    final path = await FilePicker.platform.saveFile(
        fileName: '课间-${term.name}.${format == 'ics' ? 'ics' : 'csv'}',
        bytes: bytes);
    if (mounted && path != null) _notice('已导出 ${format.toUpperCase()}');
  }

  void _notice(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 30),
      children: [
        Text('导入与导出',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1)),
        const SizedBox(height: 5),
        Text('数据只在这台设备上解析和保存。',
            style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 22),
        _ActionCard(
            icon: Icons.file_open_outlined,
            title: '导入课表',
            subtitle: 'CSV、XLSX、ICS 或课间 JSON 备份',
            onTap: busy ? null : pickFile,
            loading: busy),
        const SizedBox(height: 12),
        _ActionCard(
            icon: Icons.save_alt_outlined,
            title: '导出本机备份',
            subtitle: '包含学期、课程、调课和设置',
            onTap: exportBackup),
        const SizedBox(height: 12),
        _CaptureCard(
          status: captureStatus,
          captureNotice: captureNotice,
          onRefresh: _refreshCaptureStatus,
          onOpenAccessibility: _openCaptureSettings,
          onOpenOverlay: _openOverlaySettings,
          onOpenWeCom: _openWeCom,
          onCapture: _captureNow,
        ),
        const SizedBox(height: 22),
        Text('分享课表',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 9),
        Card(
            child: Column(children: [
          ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('导出日历（ICS）'),
              subtitle: const Text('适合添加到系统日历'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => exportCourses('ics')),
          ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('导出表格（CSV）'),
              subtitle: const Text('适合在表格软件中编辑'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => exportCourses('csv')),
        ])),
        const SizedBox(height: 22),
        Text('教务系统',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 9),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.school_outlined, color: scheme.primary),
                      const SizedBox(width: 13),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            const Text('先在教务系统导出文件',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 5),
                            Text('不同学校的正方页面和验证码差异很大。当前版本通过导出的文件导入，账号密码不会经过课间。',
                                style: TextStyle(
                                    height: 1.45,
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant))
                          ]))
                    ]))),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap,
      this.loading = false});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool loading;
  @override
  Widget build(BuildContext context) => Card(
      child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14)),
                    child: loading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(icon,
                            color: Theme.of(context).colorScheme.primary)),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall)
                    ])),
                const Icon(Icons.chevron_right_rounded)
              ]))));
}

class _CaptureCard extends StatelessWidget {
  const _CaptureCard({
    required this.status,
    required this.captureNotice,
    required this.onRefresh,
    required this.onOpenAccessibility,
    required this.onOpenOverlay,
    required this.onOpenWeCom,
    required this.onCapture,
  });

  final CourseCaptureStatus status;
  final String? captureNotice;
  final VoidCallback onRefresh;
  final VoidCallback onOpenAccessibility;
  final VoidCallback onOpenOverlay;
  final VoidCallback onOpenWeCom;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accessText = status.accessibilityEnabled ? '辅助功能已开启' : '需要开启辅助功能';
    final overlayText = status.overlayEnabled ? '悬浮窗已开启' : '需要允许悬浮窗';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.layers_outlined, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('从企业微信读取',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text('打开个人课表后，点击课间悬浮按钮读取页面结构',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                    onPressed: onRefresh,
                    tooltip: '刷新状态',
                    icon: const Icon(Icons.refresh)),
              ],
            ),
            const SizedBox(height: 10),
            Text('$accessText · $overlayText',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            if (captureNotice != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 19, color: scheme.onSecondaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        captureNotice!,
                        style: TextStyle(color: scheme.onSecondaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!status.accessibilityEnabled)
                  OutlinedButton(
                      onPressed: onOpenAccessibility,
                      child: const Text('开启辅助功能')),
                if (!status.overlayEnabled)
                  OutlinedButton(
                      onPressed: onOpenOverlay, child: const Text('开启悬浮窗')),
                OutlinedButton(
                    onPressed: onOpenWeCom, child: const Text('打开企业微信')),
                FilledButton.tonal(
                    onPressed: status.ready ? onCapture : null,
                    child: const Text('读取当前课表')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ImportPreview extends StatelessWidget {
  const ImportPreview({super.key, required this.result});
  final ImportResult result;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCapture = result.sourceLabel.startsWith('企业微信 ·');
    final errors = result.diagnostics.where((item) => item.isError).toList();
    final notices = result.diagnostics.where((item) => !item.isError).toList();
    Widget diagnosticBox(List<ImportDiagnostic> items, {required bool error}) =>
        Container(
          constraints: const BoxConstraints(maxHeight: 150),
          decoration: BoxDecoration(
            color: (error ? scheme.errorContainer : scheme.secondaryContainer)
                .withValues(alpha: .5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListView(
            padding: const EdgeInsets.all(12),
            shrinkWrap: true,
            children: [
              for (final item in items)
                Text(
                  '${error ? '错误' : '提示'}${item.line == null ? '' : ' · 第 ${item.line} 行'}：${item.message}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        );
    return SafeArea(
        child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isCapture ? '读取完成' : '导入预览',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 7),
                  Text(
                      '${result.sourceLabel}  ·  识别 ${result.courses.length} 门课程，跳过 ${result.skippedRows} 行'),
                  if (errors.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: diagnosticBox(errors, error: true)),
                  if (notices.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: diagnosticBox(notices, error: false)),
                  const SizedBox(height: 17),
                  Text('导入方式', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 5),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: result.courses.isEmpty
                              ? null
                              : () => Navigator.pop(context, false),
                          child: const Text('合并到当前课表'))),
                  SizedBox(
                      width: double.infinity,
                      child: TextButton(
                          onPressed: result.courses.isEmpty
                              ? null
                              : () => Navigator.pop(context, true),
                          child: const Text('替换当前学期（先生成快照）'))),
                ])));
  }
}
