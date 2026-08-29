package com.mobilo.mobilo

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
                    "isRunning" -> result.success(BatteryGuardService.isRunning)
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
    }
}
