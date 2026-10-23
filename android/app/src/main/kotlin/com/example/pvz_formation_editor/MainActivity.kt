package com.example.pvz_formation_editor

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var output: ByteArray? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pvz_formation_editor/files").setMethodCallHandler { call, result ->
            if (call.method != "pickProject" && call.method != "saveFile") { result.notImplemented(); return@setMethodCallHandler }
            if (pending != null) { result.error("busy", "文件对话框已打开", null); return@setMethodCallHandler }
            val intent: Intent
            val code: Int
            if (call.method == "pickProject") {
                intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply { type = "*/*"; addCategory(Intent.CATEGORY_OPENABLE) }
                code = 4101
            } else {
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("name")
                if (bytes == null || name == null) { result.error("arguments", "文件参数无效", null); return@setMethodCallHandler }
                output = bytes
                intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    type = call.argument<String>("mime") ?: "application/octet-stream"
                    addCategory(Intent.CATEGORY_OPENABLE)
                    putExtra(Intent.EXTRA_TITLE, name)
                }
                code = 4102
            }
            pending = result
            try { startActivityForResult(intent, code) }
            catch (error: Exception) { pending = null; output = null; result.error("dialog_failed", error.localizedMessage, null) }
        }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != 4101 && requestCode != 4102) { super.onActivityResult(requestCode, resultCode, data); return }
        val result = pending ?: return
        pending = null
        val bytes = output
        output = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
        try {
            if (requestCode == 4101) {
                val input = contentResolver.openInputStream(uri) ?: throw IllegalStateException("无法读取文件")
                val buffer = java.io.ByteArrayOutputStream()
                input.use { stream ->
                    val chunk = ByteArray(8192)
                    while (true) {
                        val count = stream.read(chunk)
                        if (count < 0) break
                        if (buffer.size() + count > 8 * 1024 * 1024) throw IllegalArgumentException("项目文件超过 8 MiB")
                        buffer.write(chunk, 0, count)
                    }
                }
                result.success(buffer.toByteArray())
            } else {
                val stream = contentResolver.openOutputStream(uri, "wt") ?: throw IllegalStateException("无法写入文件")
                stream.use { it.write(bytes ?: throw IllegalStateException("导出内容丢失")); it.flush() }
                result.success(uri.toString())
            }
        } catch (error: Exception) { result.error("file_failed", error.localizedMessage, null) }
    }
}
