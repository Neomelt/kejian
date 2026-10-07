import 'package:flutter_test/flutter_test.dart';

import 'package:kejian/services/app_update_service.dart';

void main() {
  test('validates an HTTPS manifest and normalizes the digest', () {
    final manifest = AppUpdateManifest.fromJson({
      'appId': 'dev.kejian.kejian',
      'versionCode': 2,
      'versionName': '0.1.1',
      'apkUrl': 'https://gitee.com/example/kejian/releases/download/v0.1.1/app-release.apk',
      'sha256': 'A' * 64,
      'notes': '修复导入提示',
    });

    expect(manifest.versionCode, 2);
    expect(manifest.sha256, 'a' * 64);
    expect(manifest.apkUrl.scheme, 'https');
  });

  test('rejects non HTTPS APK URLs and malformed digests', () {
    expect(
      () => AppUpdateManifest.fromJson({
        'appId': 'dev.kejian.kejian',
        'versionCode': 2,
        'versionName': '0.1.1',
        'apkUrl': 'http://example.com/app.apk',
        'sha256': 'a' * 64,
      }),
      throwsFormatException,
    );
    expect(
      () => AppUpdateManifest.fromJson({
        'appId': 'dev.kejian.kejian',
        'versionCode': 2,
        'versionName': '0.1.1',
        'apkUrl': 'https://example.com/app.apk',
        'sha256': 'bad',
      }),
      throwsFormatException,
    );
  });
}
