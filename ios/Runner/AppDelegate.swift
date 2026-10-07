import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UNUserNotificationCenterDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "dev.kejian/reminders",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleReminderCall(call, result: result)
    }
  }

  private let center = UNUserNotificationCenter.current()
  private let prefix = "kejian.reminder."

  private func handleReminderCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "permission":
      center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    case "status":
      center.getNotificationSettings { [weak self] settings in
        self?.center.getPendingNotificationRequests { requests in
          let count = requests.filter { $0.identifier.hasPrefix(self?.prefix ?? "") }.count
          let authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
          DispatchQueue.main.async {
            result(["authorized": authorized, "pending": count, "supported": true])
          }
        }
      }
    case "schedule":
      let reminders = (call.arguments as? [String: Any])?["reminders"] as? [[String: Any]] ?? []
      let selected = Array(reminders.prefix(63))
      center.removePendingNotificationRequests(withIdentifiers: selected.map { self.prefix + String(describing: $0["id"] ?? "") })
      center.removeAllPendingNotificationRequests()
      let group = DispatchGroup()
      var accepted = 0
      let lock = NSLock()
      let now = Date().timeIntervalSince1970 * 1000
      for item in selected {
        guard let id = item["id"], let timestamp = (item["timestamp"] as? NSNumber)?.doubleValue,
              timestamp > now else { continue }
        let content = UNMutableNotificationContent()
        content.title = item["title"] as? String ?? "课程提醒"
        content.body = item["body"] as? String ?? ""
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, (timestamp - now) / 1000), repeats: false)
        let request = UNNotificationRequest(identifier: self.prefix + String(describing: id), content: content, trigger: trigger)
        group.enter()
        center.add(request) { error in
          if error == nil { lock.lock(); accepted += 1; lock.unlock() }
          group.leave()
        }
      }
      group.notify(queue: .main) { result(accepted) }
    case "cancel":
      center.removeAllPendingNotificationRequests()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
