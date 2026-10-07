import 'package:flutter/services.dart';

class ReminderPlan {
  final int id;
  final String title;
  final String body;
  final DateTime timestamp;

  const ReminderPlan({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
  });

  Map<String, Object> toChannelJson() => {
        'id': id,
        'title': title,
        'body': body,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };
}

enum ReminderPermission { unknown, notDetermined, granted, denied }

class ReminderStatus {
  final bool supported;
  final ReminderPermission permission;
  final int pendingCount;
  final DateTime? nextAt;
  final String? message;

  const ReminderStatus({
    required this.supported,
    required this.permission,
    this.pendingCount = 0,
    this.nextAt,
    this.message,
  });

  bool get authorized => permission == ReminderPermission.granted;
  int get pending => pendingCount;

  static const unavailable = ReminderStatus(
    supported: false,
    permission: ReminderPermission.unknown,
  );
}

/// Native local notification bridge. Permission is requested only when the
/// user explicitly invokes [requestPermission].
class ReminderService {
  static const channelName = 'dev.kejian/reminders';
  static const MethodChannel channel = MethodChannel(channelName);

  const ReminderService({MethodChannel? methodChannel})
      : _channel = methodChannel ?? channel;

  final MethodChannel _channel;

  Future<ReminderStatus> status() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('status');
      final map = raw is Map
          ? Map<Object?, Object?>.from(raw)
          : const <Object?, Object?>{};
      final supported = map['supported'] == true;
      final authorized = map['authorized'] == true;
      final pending = map['pending'];
      final pendingCount = pending is int ? pending : 0;
      return ReminderStatus(
        supported: supported,
        permission: supported
            ? (authorized
                ? ReminderPermission.granted
                : ReminderPermission.denied)
            : ReminderPermission.unknown,
        pendingCount: pendingCount,
        message: supported ? null : '当前平台不支持本地提醒',
      );
    } on PlatformException catch (error) {
      return ReminderStatus(
        supported: false,
        permission: ReminderPermission.unknown,
        message: error.message ?? error.code,
      );
    } catch (error) {
      return ReminderStatus(
        supported: false,
        permission: ReminderPermission.unknown,
        message: '$error',
      );
    }
  }

  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('permission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Native side replaces the pending plan atomically.
  Future<int> schedule(List<ReminderPlan> reminders) async {
    try {
      final value = await _channel.invokeMethod<Object?>('schedule', {
        'reminders': reminders
            .map((item) => item.toChannelJson())
            .toList(growable: false),
      });
      return value is int ? value : reminders.length;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  Future<bool> cancel() async {
    try {
      return await _channel.invokeMethod<bool>('cancel') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
