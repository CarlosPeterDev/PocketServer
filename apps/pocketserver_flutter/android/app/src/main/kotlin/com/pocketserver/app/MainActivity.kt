package com.pocketserver.app

import android.content.Intent
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var hostDiagnosticsChannel: MethodChannel? = null
    private var staticSite: StaticSiteController? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        staticSite = StaticSiteController(this, messenger)
        hostDiagnosticsChannel = MethodChannel(
            messenger,
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

    @Deprecated("Uses the Activity document picker result supported by FlutterActivity.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        staticSite?.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        staticSite?.close()
        staticSite = null
        hostDiagnosticsChannel?.setMethodCallHandler(null)
        hostDiagnosticsChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
