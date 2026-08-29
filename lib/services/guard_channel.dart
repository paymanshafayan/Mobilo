import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Bridge to the native Android background monitoring service
/// (see `BatteryGuardService.kt`).
///
/// On iOS there is no such service (Apple restricts background execution),
/// so every call is a no-op.
class GuardChannel {
  GuardChannel._();

  static final GuardChannel instance = GuardChannel._();

  static const MethodChannel _methodChannel =
      MethodChannel('mobilo/battery_guard');
  static const EventChannel _eventChannel =
      EventChannel('mobilo/battery_guard/events');

  bool get isAndroid => Platform.isAndroid;

  /// Whether the native background service is currently running.
  Future<bool> isRunning() async {
    if (!isAndroid) {
      return false;
    }
    try {
      final bool? running = await _methodChannel.invokeMethod<bool>('isRunning');
      return running ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Starts the native foreground service (no-op off Android).
  Future<void> start() async {
    if (!isAndroid) {
      return;
    }
    try {
      await _methodChannel.invokeMethod<void>('start');
    } on MissingPluginException {
      // Native side missing - nothing to do.
    }
  }

  /// Stops the native foreground service (no-op off Android).
  Future<void> stop() async {
    if (!isAndroid) {
      return;
    }
    try {
      await _methodChannel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Native side missing - nothing to do.
    }
  }

  /// The active alert session on Android: `'low'`, `'full'` or `null`.
  ///
  /// The session repeats a notification every 2 minutes until dismissed.
  Future<String?> getActiveAlert() async {
    if (!isAndroid) {
      return null;
    }
    try {
      final bool? running = await _methodChannel.invokeMethod<bool>('isRunning');
      if (running != true) {
        return null;
      }
      final String? alert =
          await _methodChannel.invokeMethod<String>('getActiveAlert');
      return (alert == null || alert.isEmpty) ? null : alert;
    } on MissingPluginException {
      return null;
    }
  }

  /// Ends the active alert session on Android (no-op off Android):
  /// removes the alert notifications and stops the 2-minute repetition.
  Future<void> dismissAlert() async {
    if (!isAndroid) {
      return;
    }
    try {
      await _methodChannel.invokeMethod<void>('dismissAlert');
    } on MissingPluginException {
      // Native side missing - nothing to do.
    }
  }

  /// Live events pushed by the native service.
  ///
  /// Each event is a map: `{ 'level': int, 'charging': bool, 'active': 'low' | 'full' | '' }`.
  /// The stream stays silent when the service is not running (or off Android).
  Stream<Map<String, dynamic>> get events => isAndroid
      ? _eventChannel
          .receiveBroadcastStream()
          .map<Map<String, dynamic>>((dynamic event) {
                if (event is Map) {
                  return event.cast<String, dynamic>();
                }
                return <String, dynamic>{};
              })
      : const Stream<Map<String, dynamic>>.empty();
}
