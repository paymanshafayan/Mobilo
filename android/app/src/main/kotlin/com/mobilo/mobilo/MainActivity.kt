package com.mobilo.mobilo

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mobilo/battery_guard")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        BatteryGuardService.start(this)
                        result.success(null)
                    }
                    "stop" -> {
                        BatteryGuardService.stop(this)
                        result.success(null)
                    }
                    "dismissAlert" -> {
                        BatteryGuardService.dismissAlert(this)
                        result.success(null)
                    }
                    "isRunning" -> result.success(BatteryGuardService.isRunning)
                    "getActiveAlert" -> {
                        // Only report an active session while the service lives,
                        // so the UI never shows a stale skip button.
                        result.success(
                            if (BatteryGuardService.isRunning) {
                                BatteryGuardService.activeAlert
                            } else {
                                null
                            }
                        )
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "mobilo/battery_guard/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    BatteryGuardService.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    BatteryGuardService.setEventSink(null)
                }
            })

        // Mobina voice assistant: Dart -> native start/stop; the service
        // calls back ("status" / "command") over the same channel.
        VoiceAssistantService.engine = flutterEngine
        VoiceAssistantService.engine?.let { engine ->
            forwardPendingCommand(engine)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VoiceAssistantService.CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        startVoiceService(VoiceAssistantService.ACTION_START)
                        result.success(null)
                    }
                    "stop" -> {
                        startVoiceService(VoiceAssistantService.ACTION_STOP)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onResume() {
        super.onResume()
        // The engine is (re)attached; deliver any command the wake service
        // captured while the activity was destroyed.
        VoiceAssistantService.engine?.let { forwardPendingCommand(it) }
    }

    override fun onDestroy() {
        VoiceAssistantService.engine = null
        super.onDestroy()
    }

    private fun startVoiceService(action: String) {
        val intent = Intent(this, VoiceAssistantService::class.java).setAction(action)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                @Suppress("DEPRECATION")
                startService(intent)
            }
        } catch (_: Exception) {
        }
    }

    private fun forwardPendingCommand(engine: FlutterEngine) {
        val pending = VoiceAssistantService.pendingCommand ?: return
        VoiceAssistantService.pendingCommand = null
        try {
            MethodChannel(engine.dartExecutor.binaryMessenger, VoiceAssistantService.CHANNEL_NAME)
                .invokeMethod("command", mapOf("text" to pending))
        } catch (_: Exception) {
            VoiceAssistantService.pendingCommand = pending
        }
    }
}
