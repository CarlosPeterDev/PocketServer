package com.pocketserver.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.Executors

internal class StaticSiteController(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : AutoCloseable {
    private val pickerRequest = 0x5053
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var server: LoopbackSiteServer? = null

    private val channel = MethodChannel(messenger, "com.pocketserver.app/static_site").apply {
        setMethodCallHandler { call, result ->
            when (call.method) {
                "chooseAndStart" -> chooseDocument(result)
                "stop" -> {
                    server?.close()
                    server = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun chooseDocument(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("picker_busy", "The document picker is already open", null)
            return
        }
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "text/html"
        }
        try {
            activity.startActivityForResult(intent, pickerRequest)
        } catch (_: ActivityNotFoundException) {
            pending = null
            result.error("picker_unavailable", "No document picker is available", null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != pickerRequest) return
        val result = pending ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            result.success(null)
            return
        }
        worker.execute {
            val page = runCatching { readHtml(uri) }
            activity.runOnUiThread {
                if (pending !== result) return@runOnUiThread
                pending = null
                page.fold(
                    onSuccess = { start(it, result) },
                    onFailure = {
                        result.error("file_unavailable", "Choose a nonempty HTML file up to 1 MiB", null)
                    },
                )
            }
        }
    }

    private fun readHtml(uri: Uri): ByteArray {
        val input = activity.contentResolver.openInputStream(uri)
            ?: throw IOException("Unable to open the selected document")
        return input.use {
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val count = it.read(buffer)
                if (count < 0) break
                if (output.size() + count > LoopbackSiteServer.MAX_PAGE_BYTES) {
                    throw IOException("Document exceeds size limit")
                }
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        }
    }

    private fun start(page: ByteArray, result: MethodChannel.Result) {
        if (page.isEmpty()) {
            result.error("file_unavailable", "Choose a nonempty HTML file up to 1 MiB", null)
            return
        }
        try {
            val next = LoopbackSiteServer.start(page)
            server?.close()
            server = next
            result.success(next.url())
        } catch (_: IOException) {
            result.error("server_unavailable", "Could not start local hosting", null)
        }
    }

    override fun close() {
        pending = null
        channel.setMethodCallHandler(null)
        worker.shutdownNow()
        server?.close()
        server = null
    }
}
