import 'package:flutter/services.dart';

/// Flutter bridge for the optional Android enterprise-WeChat reader.
///
/// The Android side only emits [CourseCaptureResult] after the user taps the
/// visible overlay button (or invokes [capture]). It does not log in, inspect
/// cookies, or make network requests.
class CourseCaptureService {
  static const channelName = 'dev.kejian/course_capture';
  static const MethodChannel channel = MethodChannel(channelName);

  const CourseCaptureService({MethodChannel? methodChannel})
      : _channel = methodChannel ?? channel;

  final MethodChannel _channel;

  Future<CourseCaptureStatus> status() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('status');
      final map = _map(raw);
      return CourseCaptureStatus(
        accessibilityEnabled: map['accessibilityEnabled'] == true,
        overlayEnabled: map['overlayEnabled'] == true,
        targetPackage: map['targetPackage']?.toString(),
      );
    } on MissingPluginException {
      return const CourseCaptureStatus.unsupported();
    } on PlatformException catch (error) {
      return CourseCaptureStatus(
        message: error.message ?? error.code,
      );
    }
  }

  Future<bool> openAccessibilitySettings() =>
      _boolCall('openAccessibilitySettings');

  Future<bool> openOverlaySettings() => _boolCall('openOverlaySettings');

  Future<bool> openTargetApp() => _boolCall('openTargetApp');

  /// Opens the Jiangsu University adapter WebView. Login stays inside the
  /// system WebView and the page is parsed locally before returning here.
  Future<bool> openUjsAdapter() => _boolCall('openUjsAdapter');

  /// Requests one capture from the currently active accessibility window.
  Future<bool> capture() => _boolCall('capture');

  /// Installs a handler for native `captureResult` events. Calling it again
  /// replaces the previous handler.
  void listen(
    void Function(CourseCaptureResult result) onResult,
  ) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'captureResult') {
        onResult(CourseCaptureResult.fromDynamic(call.arguments));
      }
    });
    // A capture can happen while the Flutter activity is stopped or before
    // this handler is attached. Native retains the latest result until this
    // handshake explicitly consumes it.
    _channel.invokeMethod<Object?>('ready').then<void>(
      (value) {
        if (value != null) onResult(CourseCaptureResult.fromDynamic(value));
      },
      onError: (_) {},
    );
  }

  Future<bool> _boolCall(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Map<Object?, Object?> _map(Object? value) => value is Map
      ? Map<Object?, Object?>.from(value)
      : const <Object?, Object?>{};
}

class CourseCaptureStatus {
  final bool accessibilityEnabled;
  final bool overlayEnabled;
  final String? targetPackage;
  final String? message;

  const CourseCaptureStatus({
    this.accessibilityEnabled = false,
    this.overlayEnabled = false,
    this.targetPackage,
    this.message,
  });

  const CourseCaptureStatus.unsupported()
      : accessibilityEnabled = false,
        overlayEnabled = false,
        targetPackage = null,
        message = '当前平台不支持企业微信页面读取';

  bool get ready => accessibilityEnabled;
}

class CourseCaptureResult {
  final String sourcePackage;
  final String pageTitle;
  final String rawText;
  final List<CourseCaptureCell> cells;
  final List<CourseCaptureCandidate> courses;
  final List<String> diagnostics;
  final int? activeWeek;
  final DateTime capturedAt;

  const CourseCaptureResult({
    required this.sourcePackage,
    required this.pageTitle,
    required this.rawText,
    required this.cells,
    required this.courses,
    required this.diagnostics,
    required this.activeWeek,
    required this.capturedAt,
  });

  factory CourseCaptureResult.fromDynamic(Object? value) {
    final map = value is Map
        ? Map<Object?, Object?>.from(value)
        : const <Object?, Object?>{};
    final rawCells = map['cells'];
    final rawCourses = map['courses'];
    final rawDiagnostics = map['diagnostics'];
    final captured = map['capturedAt'];
    return CourseCaptureResult(
      sourcePackage: map['sourcePackage']?.toString() ?? '',
      pageTitle: map['pageTitle']?.toString() ?? '',
      rawText: map['rawText']?.toString() ?? '',
      cells: rawCells is List
          ? rawCells.map(CourseCaptureCell.fromDynamic).toList(growable: false)
          : const [],
      courses: rawCourses is List
          ? rawCourses
              .map(CourseCaptureCandidate.fromDynamic)
              .toList(growable: false)
          : const [],
      diagnostics: rawDiagnostics is List
          ? rawDiagnostics.map((item) => '$item').toList(growable: false)
          : const [],
      activeWeek: _intOrNull(map['activeWeek']),
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        _intOrNull(captured) ?? 0,
      ),
    );
  }
}

class CourseCaptureCell {
  final String id;
  final String text;
  final List<String> children;

  const CourseCaptureCell({
    required this.id,
    required this.text,
    this.children = const [],
  });

  factory CourseCaptureCell.fromDynamic(Object? value) {
    final map = value is Map
        ? Map<Object?, Object?>.from(value)
        : const <Object?, Object?>{};
    return CourseCaptureCell(
      id: map['id']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      children: map['children'] is List
          ? (map['children'] as List)
              .map((item) => '$item')
              .toList(growable: false)
          : const [],
    );
  }
}

class CourseCaptureCandidate {
  final String id;
  final String sourceNodeId;
  final String rawText;
  final String title;
  final String teacher;
  final String room;
  final int? weekday;
  final int? startSlot;
  final int? endSlot;
  final List<int> weeks;
  final String parity;
  final String? duplicateGroupKey;
  final bool? inActiveWeek;

  const CourseCaptureCandidate({
    required this.id,
    required this.sourceNodeId,
    required this.rawText,
    required this.title,
    required this.teacher,
    required this.room,
    required this.weekday,
    required this.startSlot,
    required this.endSlot,
    required this.weeks,
    required this.parity,
    required this.duplicateGroupKey,
    required this.inActiveWeek,
  });

  factory CourseCaptureCandidate.fromDynamic(Object? value) {
    final map = value is Map
        ? Map<Object?, Object?>.from(value)
        : const <Object?, Object?>{};
    final rawWeeks = map['weeks'];
    return CourseCaptureCandidate(
      id: map['id']?.toString() ?? '',
      sourceNodeId: map['sourceNodeId']?.toString() ?? '',
      rawText: map['rawText']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      teacher: map['teacher']?.toString() ?? '',
      room: map['room']?.toString() ?? '',
      weekday: _intOrNull(map['weekday']),
      startSlot: _intOrNull(map['startSlot']),
      endSlot: _intOrNull(map['endSlot']),
      weeks: rawWeeks is List
          ? rawWeeks.map(_intOrNull).whereType<int>().toList(growable: false)
          : const [],
      parity: map['parity']?.toString() ?? 'all',
      duplicateGroupKey: map['duplicateGroupKey']?.toString(),
      inActiveWeek:
          map['inActiveWeek'] is bool ? map['inActiveWeek'] as bool : null,
    );
  }
}

int? _intOrNull(Object? value) => value is int ? value : int.tryParse('$value');
