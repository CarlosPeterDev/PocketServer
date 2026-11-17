package com.pocketserver.app

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var hostDiagnosticsChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        hostDiagnosticsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.pocketserver.app/host_diagnostics",
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAvailableStorageBytes" -> {
                        try {
                            result.success(StatFs(filesDir.absolutePath).availableBytes)
                        } catch (_: IllegalArgumentException) {
                            result.error("storage_unavailable", "App data volume unavailable", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        hostDiagnosticsChannel?.setMethodCallHandler(null)
        hostDiagnosticsChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
