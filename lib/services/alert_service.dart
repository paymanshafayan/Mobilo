import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/fa.dart';
import 'battery_service.dart';

/// Fires the low-battery (<= 15 %) and full-battery (>= 95 %) local
/// notifications.
///
/// Platform split:
///  * **Android** - the native [BatteryGuardService] runs 24/7 in a foreground
///    service and posts all alerts by itself, so this class only drives the
///    UI there (no Dart-side notifications, to avoid duplicates).
///  * **iOS** - Apple suspends background apps, so the Dart loop alerts while
///    the app is in the foreground; opportunistic native background checks
///    (see AppDelegate.swift) cover the background best-effort.
class AlertService {
  AlertService._();

  static final AlertService instance = AlertService._();

  static const int lowThreshold = 15;
  static const int fullThreshold = 95;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<BatterySnapshot>? _subscription;

  // Hysteresis flags: alert once per discharge episode / charge session.
  bool _lowAlerted = false;
  bool _fullAlerted = false;

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

  void _onSnapshot(BatterySnapshot snapshot) {
    if (Platform.isAndroid) {
      return; // Native service owns the alerts on Android.
    }
    final int? level = snapshot.level;
    if (level == null) {
      return;
    }

    if (snapshot.isCharging) {
      // Plugged in: a new low-battery episode may start later.
      _lowAlerted = false;
      if (level >= fullThreshold && !_fullAlerted) {
        _fullAlerted = true;
        _show(2002, Strings.fullBatteryTitle, Strings.fullBatteryBody(level));
      }
    } else {
      // Unplugged: a new charge session may start later.
      _fullAlerted = false;
      if (level <= lowThreshold && !_lowAlerted) {
        _lowAlerted = true;
        _show(2001, Strings.lowBatteryTitle, Strings.lowBatteryBody(level));
      }
    }
  }

  Future<void> _show(int id, String title, String body) async {
    try {
      await _notifications.show(id, title, body, _details);
    } catch (_) {
      // Never let a notification failure crash the app.
    }
  }
}
