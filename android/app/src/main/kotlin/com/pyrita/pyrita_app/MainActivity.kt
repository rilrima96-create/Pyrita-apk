package com.pyrita.pyrita_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        // Канал для нашего custom APK installer'а. open_filex и
        // share_plus оба пытались, оба silently failed на Android 14+
        // Samsung One UI (юзер: «моргнула и выключилась»). Native intent
        // с правильными FLAG'ами надёжнее.
        private const val INSTALLER_CHANNEL = "com.pyrita.pyrita_app/installer"

        // Authority должен соответствовать FileProvider declaration в
        // AndroidManifest.xml. Кейс-сенситивно.
        private const val FILE_PROVIDER_AUTHORITY =
            "com.pyrita.pyrita_app.fileprovider"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INSTALLER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID_ARG", "path is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val ok = installApk(path)
                        result.success(ok)
                    } catch (e: Exception) {
                        result.error(
                            "INSTALL_FAILED",
                            "Failed to start installer: ${e.message}",
                            e.stackTraceToString(),
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Триггерит Android system package installer для скачанного APK.
     *
     * Шаги:
     *   1. File → content:// URI через FileProvider (требуется на N+)
     *   2. ACTION_VIEW intent с MIME application/vnd.android.package-archive
     *   3. FLAG_ACTIVITY_NEW_TASK — required когда intent отправлен из
     *      non-Activity context. Без этого Android иногда silent-reject'ит
     *      (юзер видит мгновенный flash вместо installer dialog).
     *   4. FLAG_GRANT_READ_URI_PERMISSION — package installer (system app)
     *      должен temp-grant'ить read access к нашему content URI.
     *
     * Returns: true если intent successfully запущен, false если файл нет.
     * Throws: ActivityNotFoundException если нет package installer'а
     *         (теоретически невозможно, но safe-defaulted).
     */
    private fun installApk(path: String): Boolean {
        val apk = File(path)
        if (!apk.exists() || apk.length() <= 0) {
            return false
        }

        val uri: Uri = FileProvider.getUriForFile(
            this,
            FILE_PROVIDER_AUTHORITY,
            apk,
        )

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            // Android 11+ scoped storage — extra hint что receiver
            // нужно ContextCompat startActivity.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
            }
        }

        startActivity(intent)
        return true
    }
}
