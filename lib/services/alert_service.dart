import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/fa.dart';
import 'battery_service.dart';

/// Fires the low-battery (<= 15 %) and full-battery (>= 95 %) local
/// notifications.
///
/// Alert sessions repeat a notification every [repeatInterval] (2 minutes)
/// until the user dismisses them (the circular "انصراف" button in the UI,
/// the notification's skip action, or the condition resolving itself).
///
/// Platform split:
///  * **Android** - the native [BatteryGuardService] runs 24/7 in a foreground
///    service and owns the whole session (post + repeat + dismiss), so this
///    class only drives the UI there (no Dart-side notifications, to avoid
///    duplicates).
///  * **iOS** - Apple suspends background apps, so the Dart loop runs the
///    session while the app is in the foreground; opportunistic native
///    background checks (see AppDelegate.swift) re-post while suspended.
class AlertService {
  AlertService._();

  static final AlertService instance = AlertService._();

  static const int lowThreshold = 15;
  static const int fullThreshold = 95;

  /// How often an active alert is repeated.
  static const Duration repeatInterval = Duration(minutes: 2);

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// Lazy [FlutterTts] used to announce alerts aloud on iOS.
  FlutterTts? _tts;

  StreamSubscription<BatterySnapshot>? _subscription;
  Timer? _repeatTimer;

  /// The active alert session: `'low'`, `'full'` or `null`.
  ///
  /// The UI watches this to show the circular dismiss button.
  final ValueNotifier<String?> activeAlert = ValueNotifier<String?>(null);

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'battery_guard_alerts',
    'اخطارهای باتری',
    channelDescription: 'اخطارهای شارژ کم و کامل',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  static const DarwinNotificationDetails _iosDetails =
      DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  static const NotificationDetails _details = NotificationDetails(
    android: _androidDetails,
    iOS: _iosDetails,
  );

  /// Initializes the local notifications plugin.
  Future<void> init() async {
    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _notifications.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
  }

  /// Requests the notification permission (Android 13+ and iOS).
  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
    if (Platform.isIOS) {
      await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  /// Starts the foreground alerting loop. Safe to call multiple times.
  Future<void> start() async {
    if (_subscription == null) {
      _subscription = BatteryService.instance.snapshots.listen(_onSnapshot);
    }
    await BatteryService.instance.start();
  }

  /// Ends the active alert session (the "انصراف" button calls this on iOS).
  void dismissAlerts() {
    final String? active = activeAlert.value;
    if (active == null) {
      return;
    }
    activeAlert.value = null;
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  void _onSnapshot(BatterySnapshot snapshot) {
    if (Platform.isAndroid) {
      return; // Native service owns the alert sessions on Android.
    }
    final int? level = snapshot.level;
    if (level == null) {
      return;
    }

    final bool lowCondition =
        !snapshot.isCharging && level <= lowThreshold;
    final bool fullCondition = snapshot.isCharging && level >= fullThreshold;

    // End sessions whose condition is gone.
    if (activeAlert.value == 'low' && !lowCondition) {
      dismissAlerts();
    }
    if (activeAlert.value == 'full' && !fullCondition) {
      dismissAlerts();
    }

    // Start new sessions (repetition is driven by the timer below).
    if (lowCondition && activeAlert.value != 'low') {
      _beginSession('low', level);
    } else if (fullCondition && activeAlert.value != 'full') {
      _beginSession('full', level);
    }
  }

  void _beginSession(String kind, int level) {
    activeAlert.value = kind;
    _show(kind, level);
    _repeatTimer?.cancel();
    _repeatTimer = Timer(repeatInterval, _onRepeat);
  }

  void _onRepeat() {
    final String? kind = activeAlert.value;
    if (kind == null) {
      return;
    }
    final int level = BatteryService.instance.last?.level ?? 0;
    _show(kind, level);
    _repeatTimer = Timer(repeatInterval, _onRepeat);
  }

  void _show(String kind, int level) {
    final int id = kind == 'low' ? 2001 : 2002;
    final String title =
        kind == 'low' ? Strings.lowBatteryTitle : Strings.fullBatteryTitle;
    final String body = kind == 'low'
        ? '${Strings.lowBatteryBody(level)} '
            '(تا فشردن «انصراف»، هر ۲ دقیقه تکرار می‌شود)'
        : '${Strings.fullBatteryBody(level)} '
            '(تا فشردن «انصراف»، هر ۲ دقیقه تکرار می‌شود)';
    showNotification(id, title, body);
    unawaited(_speakAlert(kind, level));
  }

  /// Speaks the alert aloud (iOS foreground only).
  ///
  /// On Android the native foreground service owns every alert session and
  /// speaks through the platform TTS itself, so it works even with the app
  /// closed (see `BatteryGuardService.kt`); the Dart loop is not involved
  /// there to avoid a double announcement.
  Future<void> _speakAlert(String kind, int level) async {
    if (!Platform.isIOS) {
      return;
    }
    try {
      _tts ??= await _createTts();
      await _tts?.speak(alertSpeechText(kind, level));
    } catch (_) {
      // Voice is best effort - the notification is always shown.
    }
  }

  Future<FlutterTts?> _createTts() async {
    try {
      final FlutterTts tts = FlutterTts();
      await tts.setLanguage('fa-IR');
      await tts.setSpeechRate(0.95);
      await tts.setVolume(1.0);
      return tts;
    } catch (_) {
      return null;
    }
  }

  Future<void> showNotification(int id, String title, String body) async {
    try {
      await _notifications.show(id, title, body, _details);
    } catch (_) {
      // Never let a notification failure crash the app.
    }
  }
}
