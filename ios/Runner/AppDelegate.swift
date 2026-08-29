import Flutter
import FlutterPlugin
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Mirrors the Dart side (AlertService) and the Android service.
  private let lowThreshold = 15
  private let fullThreshold = 95
  private var lowAlerted = false
  private var fullAlerted = false

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
    var fired = false

    let device = UIDevice.current
    device.isBatteryMonitoringEnabled = true
    let rawLevel = device.batteryLevel // -1 when unavailable
    guard rawLevel >= 0 else {
      completionHandler(.noData)
      return
    }
    let level = Int((rawLevel * 100).rounded())
    let charging = device.batteryState == .charging

    if charging {
      // Plugged in: a new low-battery episode may start later.
      lowAlerted = false
    } else {
      // Unplugged: a new charge session may start later.
      fullAlerted = false
    }

    if charging && level >= fullThreshold && !fullAlerted {
      fullAlerted = true
      postNotification(
        id: "mobilo.battery.full",
        title: "🔋 باتری شارژ کامل شد",
        body: "سطح باتری به \(fa(level))٪ رسید. برای حفظ عمر باتری، شارژر را جدا کنید."
      )
      fired = true
    } else if !charging && level <= lowThreshold && !lowAlerted {
      lowAlerted = true
      postNotification(
        id: "mobilo.battery.low",
        title: "⚠️ باتری رو به اتمام است",
        body: "سطح باتری به \(fa(level))٪ رسیده است. لطفاً گوشی را به شارژ وصل کنید."
      )
      fired = true
    }

    completionHandler(fired ? .newData : .noData)
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
