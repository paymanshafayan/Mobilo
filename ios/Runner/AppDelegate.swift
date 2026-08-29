import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Mirrors the Dart side (AlertService) and the Android service.
  private let lowThreshold = 15
  private let fullThreshold = 95

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Local notification permission for the battery alerts.
    // Deferred to the next runloop tick: requesting authorization too early
    // (before the scene is connected) can crash on iOS 17+.
    DispatchQueue.main.async {
      UNUserNotificationCenter.current().requestAuthorization(
        options: [.alert, .sound, .badge]) { _, _ in }
    }

    // Best-effort background monitoring.
    // Apple only wakes the app opportunistically (typically while charging,
    // idle and connected to Wi-Fi); this complements the live foreground
    // monitoring that the Flutter side performs.
    application.registerForRemoteNotifications()
    application.setMinimumBackgroundFetchInterval(
      UIApplicationBackgroundFetchIntervalMinimum)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - Background fetch (best-effort background battery check)

  override func application(
    _ application: UIApplication,
    performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    let device = UIDevice.current
    device.isBatteryMonitoringEnabled = true
    let rawLevel = device.batteryLevel // -1 when unavailable
    guard rawLevel >= 0 else {
      completionHandler(.noData)
      return
    }
    let level = Int((rawLevel * 100).rounded())
    let charging = device.batteryState == .charging

    // Re-post while the condition holds: this is the background half of the
    // "repeat until dismissed" behaviour. While the app is in the foreground
    // the Dart side repeats the notification every 2 minutes; while
    // suspended we can only act when Apple wakes us, so every wake that
    // finds the condition still true re-alerts.
    if charging && level >= fullThreshold {
      postNotification(
        id: "mobilo.battery.full",
        title: "🔋 باتری شارژ کامل شد",
        body: "سطح باتری به \(fa(level))٪ رسید. برای حفظ عمر باتری، شارژر را جدا کنید."
      )
      completionHandler(.newData)
      return
    }
    if !charging && level <= lowThreshold {
      postNotification(
        id: "mobilo.battery.low",
        title: "⚠️ باتری رو به اتمام است",
        body: "سطح باتری به \(fa(level))٪ رسیده است. لطفاً گوشی را به شارژ وصل کنید."
      )
      completionHandler(.newData)
      return
    }
    completionHandler(.noData)
  }

  // MARK: - Helpers

  private func postNotification(id: String, title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  /// Converts ASCII digits to Persian digits.
  private func fa(_ value: Int) -> String {
    let digits = "۰۱۲۳۴۵۶۷۸۹"
    return String(value)
      .map { c -> Character in
        if let digit = c.wholeNumberValue, (0...9).contains(digit) {
          return digits[digits.index(digits.startIndex, offsetBy: digit)]
        }
        return c
      }
  }
}
