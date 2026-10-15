package org.celaut.chatui

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// The package of a service, for a node that does not have it (`docs/celaut/package.md`):
/// the user picks a `.celaut.bee` file, and the app copies it into its cache with a
/// stream (a service can be large, so never into memory). Also says if the network is
/// metered, so that the app can warn before a large transfer on mobile data.
object PackageHandler {
    private const val CHANNEL = "org.celaut.chatui/package"
    private const val REQUEST_PICK = 7303

    private var pending: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())

    fun registerWith(engine: FlutterEngine, activity: Activity) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickPackage" -> pick(activity, result)
                "isMetered" -> result.success(isMetered(activity))
                else -> result.notImplemented()
            }
        }
    }

    private fun isMetered(context: Context): Boolean {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        return manager?.isActiveNetworkMetered ?: false
    }

    private fun pick(activity: Activity, result: MethodChannel.Result) {
        // One question at a time: an older one that is still open gets no file.
        pending?.success(null)
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // Any type: a .celaut.bee file has no MIME type of its own.
            type = "*/*"
        }
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, REQUEST_PICK)
        } catch (e: Exception) {
            pending = null
            result.error("no_picker", e.message, null)
        }
    }

    /// Called by `MainActivity.onActivityResult`.
    fun onActivityResult(context: Context, requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_PICK) return
        val result = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        // The copy reads and writes the disk: not on the main thread.
        Thread {
            try {
                val copied = copy(context, uri)
                main.post { result.success(copied) }
            } catch (e: Exception) {
                main.post { result.error("copy_failed", e.message, null) }
            }
        }.start()
    }

    private fun copy(context: Context, uri: Uri): Map<String, Any> {
        val folder = File(context.cacheDir, "packages")
        folder.mkdirs()
        val target = File(folder, "picked-${System.currentTimeMillis()}.bee")
        val input = context.contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("the file cannot be opened")
        try {
            input.use { source -> target.outputStream().use { source.copyTo(it, 1 shl 16) } }
        } catch (e: Exception) {
            target.delete()
            throw e
        }
        return mapOf(
            "path" to target.absolutePath,
            "bytes" to target.length(),
            "name" to (displayName(context, uri) ?: target.name),
        )
    }

    private fun displayName(context: Context, uri: Uri): String? =
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
}
