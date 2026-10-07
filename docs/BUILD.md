# Mobile builds

The project uses Flutter 3.47.6. Android release builds use the Gradle wrapper in `android/`; iOS packaging runs on a macOS GitHub Actions runner because Xcode is required.

## Android

For a local development artifact:

```sh
export PATH="$HOME/.local/share/flutter/bin:$PATH"
flutter pub get
flutter build apk --release
```

With a real release keystore, set `ANDROID_KEYSTORE_FILE`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` before running the same command. If those values are absent the Gradle script deliberately falls back to the debug key, so that artifact must not be distributed as a production release. The tag-only CI job requires the four secrets plus `ANDROID_KEYSTORE_BASE64` and fails when any is missing.

The workflow produces a test-signed APK on normal branch builds, and a separately named signed APK for `v*` tags after secret validation.

## iOS

GitHub Actions runs `flutter build ios --release --no-codesign`, then packages `build/ios/iphoneos/Runner.app` as `Kejian.ipa`. This is an unsigned IPA intended for sideload/signing by the owner; no Apple signing credentials are stored in the repository.

## Reminder channel contract

Flutter calls `dev.kejian/reminders` with these methods:

* `permission` requests notification permission and returns `bool`.
* `status` returns `{authorized: bool, pending: int, supported: bool}`.
* `schedule` accepts `{reminders: [{id, title, body, timestamp}]}` where `timestamp` is epoch milliseconds, cancels the previous set, and returns the number accepted. iOS caps the set at 63; Android uses inexact `AlarmManager` alarms and restores persisted alarms after reboot.
* `cancel` removes all pending reminders and returns `true`.

The app asks for notification permission only when the user enables reminders, not during startup.
