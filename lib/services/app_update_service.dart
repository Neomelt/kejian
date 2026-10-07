import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

/// An update manifest published by the project owner.
///
/// The manifest is deliberately external to the app. Configure its HTTPS URL
/// at build time with `--dart-define=KEJIAN_UPDATE_MANIFEST_URL=...`.
class AppUpdateManifest {
  const AppUpdateManifest({
    required this.appId,
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.sha256,
    this.notes = '',
    this.sizeBytes,
  });

  final String appId;
  final int versionCode;
  final String versionName;
  final Uri apkUrl;
  final String sha256;
  final String notes;
  final int? sizeBytes;

  factory AppUpdateManifest.fromJson(Object? raw) {
    if (raw is! Map) throw const FormatException('更新清单必须是 JSON 对象');
    String stringValue(String key) {
      final value = raw[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('更新清单缺少 $key');
      }
      return value.trim();
    }

    final appId = stringValue('appId');
    final versionName = stringValue('versionName');
    final apkUrl = Uri.tryParse(stringValue('apkUrl'));
    if (apkUrl == null || apkUrl.scheme != 'https' || apkUrl.host.isEmpty) {
      throw const FormatException('apkUrl 必须使用 HTTPS');
    }
    final versionCode = raw['versionCode'];
    if (versionCode is! num || versionCode < 1 || versionCode != versionCode.round()) {
      throw const FormatException('versionCode 无效');
    }
    final hash = stringValue('sha256').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('sha256 必须是 64 位十六进制摘要');
    }
    final size = raw['sizeBytes'];
    if (size != null && (size is! num || size < 1 || size != size.round())) {
      throw const FormatException('sizeBytes 无效');
    }
    return AppUpdateManifest(
      appId: appId,
      versionCode: versionCode.toInt(),
      versionName: versionName,
      apkUrl: apkUrl,
      sha256: hash,
      notes: raw['notes'] is String ? (raw['notes'] as String).trim() : '',
      sizeBytes: size is num ? size.toInt() : null,
    );
  }
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({required this.manifest, required this.currentVersionCode});
  final AppUpdateManifest manifest;
  final int currentVersionCode;
  bool get available => manifest.versionCode > currentVersionCode;
}

class AppUpdateService {
  const AppUpdateService({MethodChannel? channel, HttpClient Function()? clientFactory})
      : _channel = channel ?? const MethodChannel(channelName),
        _clientFactory = clientFactory ?? HttpClient.new;

  static const channelName = 'dev.kejian/app_update';
  static const configuredManifestUrl = String.fromEnvironment(
    'KEJIAN_UPDATE_MANIFEST_URL',
    defaultValue: '',
  );
  static const appId = 'dev.kejian.kejian';

  final MethodChannel _channel;
  final HttpClient Function() _clientFactory;

  bool get configured => configuredManifestUrl.trim().isNotEmpty;

  Future<int> currentVersionCode() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('appInfo');
      if (raw is Map && raw['versionCode'] is num) {
        return (raw['versionCode'] as num).toInt();
      }
    } on MissingPluginException {
      // iOS and older builds expose no installer channel yet.
    } on PlatformException {
      // Treat a missing native version as an unsupported update path.
    }
    return 0;
  }

  Future<AppUpdateCheckResult> checkForUpdate({String? endpoint}) async {
    final source = (endpoint ?? configuredManifestUrl).trim();
    if (source.isEmpty) {
      throw const AppUpdateException('当前版本没有配置更新地址');
    }
    final uri = Uri.tryParse(source);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const AppUpdateException('更新地址必须使用 HTTPS');
    }
    final client = _clientFactory();
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = true;
      request.maxRedirects = 3;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw AppUpdateException('更新清单请求失败（HTTP ${response.statusCode}）');
      }
      final body = await utf8.decoder.bind(response).join();
      final manifest = AppUpdateManifest.fromJson(jsonDecode(body));
      if (manifest.appId != appId) {
        throw const AppUpdateException('更新清单不属于当前应用');
      }
      return AppUpdateCheckResult(
        manifest: manifest,
        currentVersionCode: await currentVersionCode(),
      );
    } on AppUpdateException {
      rethrow;
    } on FormatException catch (error) {
      throw AppUpdateException('更新清单格式错误：${error.message}');
    } on SocketException catch (error) {
      throw AppUpdateException('无法连接更新服务器：${error.message}');
    } on HttpException catch (error) {
      throw AppUpdateException('更新清单请求失败：${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads the APK into the app-private cache and verifies its SHA-256.
  /// The native side still asks Android for explicit installer confirmation.
  Future<String> download(AppUpdateManifest manifest, {void Function(int, int?)? onProgress}) async {
    if (manifest.apkUrl.scheme != 'https' || manifest.apkUrl.host.isEmpty) {
      throw const AppUpdateException('APK 地址必须使用 HTTPS');
    }
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/kejian-${manifest.versionName}-${manifest.versionCode}.apk');
    if (await file.exists()) await file.delete();
    final client = _clientFactory();
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = const Duration(seconds: 30);
    IOSink? output;
    var verified = false;
    try {
      final request = await client.getUrl(manifest.apkUrl);
      request.followRedirects = true;
      request.maxRedirects = 3;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw AppUpdateException('APK 下载失败（HTTP ${response.statusCode}）');
      }
      final expectedLength = response.contentLength > 0 ? response.contentLength : manifest.sizeBytes;
      final sink = _DigestSink();
      final digestInput = sha256.startChunkedConversion(sink);
      output = file.openWrite();
      var received = 0;
      await for (final chunk in response) {
        digestInput.add(chunk);
        output.add(chunk);
        received += chunk.length;
        onProgress?.call(received, expectedLength);
      }
      digestInput.close();
      await output.flush();
      await output.close();
      output = null;
      if (expectedLength != null && received != expectedLength) {
        throw const AppUpdateException('APK 下载不完整');
      }
      if (sink.value.toString().toLowerCase() != manifest.sha256) {
        throw const AppUpdateException('APK 校验失败，已删除下载文件');
      }
      verified = true;
      return file.path;
    } on AppUpdateException {
      rethrow;
    } on SocketException catch (error) {
      throw AppUpdateException('APK 下载失败：${error.message}');
    } finally {
      await output?.close();
      client.close(force: true);
      if (!verified && await file.exists()) await file.delete();
    }
  }

  Future<void> install(String path) async {
    try {
      await _channel.invokeMethod<void>('installApk', {'path': path});
    } on MissingPluginException {
      throw const AppUpdateException('当前平台不支持 APK 更新');
    } on PlatformException catch (error) {
      throw AppUpdateException(error.message ?? error.code);
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
