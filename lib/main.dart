import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'services/alert_service.dart';
import 'services/guard_channel.dart';
import 'services/voice_assistant.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Prepare local notifications (used for the low/full battery alerts on iOS;
  // on Android the native background service posts its own notifications).
  await AlertService.instance.init();
  await AlertService.instance.requestPermissions();

  // Android: make sure the 24/7 background guardian service is running.
  final GuardChannel guard = GuardChannel.instance;
  if (guard.isAndroid) {
    if (!(await guard.isRunning())) {
      await guard.start();
    }
  }

  // iOS: run the foreground alerting loop.
  // (On Android the native service owns all alerts, so the Dart loop
  // only listens on iOS to avoid double notifications.)
  await AlertService.instance.start();

  // Mobina: arm the always-listening voice assistant (wake word «مبینا»).
  // On Android this also starts the native foreground wake service.
  unawaited(VoiceAssistant.instance.start());

  runApp(const MobiloApp());
}
