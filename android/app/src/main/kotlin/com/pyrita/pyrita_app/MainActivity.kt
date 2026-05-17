package com.pyrita.pyrita_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.content.FileProvider
import dev.amirzr.flutter_v2ray_client.v2ray.V2rayController
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

        // flutter_v2ray_client v3.2.0 plugin's notification disconnect button
        // setActions(0, "Отключить", notificationContentPendingIntent) — это
        // BUG в плагине: content-intent (которые открывает app), а НЕ stop-intent
        // (который останавливает VPN). Плагин выставляет `intent.action =
        // "FROM_DISCONNECT_BTN"` на этом content-intent и ожидает что HOST
        // app (мы) обработает этот action и вызовет StopV2ray.
        // См. V2rayCoreManager.java showNotification() line 326-360.
        // Без этой обработки нажатие "Отключить" в плагиновой шторке просто
        // открывает app и ничего больше не делает.
        private const val ACTION_FROM_DISCONNECT_BTN = "FROM_DISCONNECT_BTN"

        // flutter_local_notifications v18.0.1 action with showsUserInterface=true:
        // intent.action = "SELECT_FOREGROUND_NOTIFICATION", extras["actionId"]
        // = action.id. Используется для НАШЕЙ custom PRIORITY_LOW notification
        // в PyritaNotificationService. Native fallback дополняет Dart callback —
        // защита от race condition (action triggered ДО того как Dart-side
        // init() завершился и подписался на disconnectRequests stream).
        private const val ACTION_FLN_FOREGROUND = "SELECT_FOREGROUND_NOTIFICATION"
        private const val EXTRA_ACTION_ID = "actionId"
        private const val ACTION_ID_DISCONNECT = "action_disconnect"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleVpnDisconnectIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // setIntent чтобы getIntent() возвращал актуальный в случае
        // последующих обращений из Flutter/native кода.
        setIntent(intent)
        handleVpnDisconnectIntent(intent)
    }

    /**
     * Если intent пришёл от плагиновой notification "Отключить" кнопки —
     * вызываем StopV2ray. См. comment у ACTION_FROM_DISCONNECT_BTN.
     *
     * Также обрабатываем наш custom-action "pyrita_stop_vpn" — это тот
     * который flutter_local_notifications установит на нашей PRIORITY_LOW
     * notification's action button (с showsUserInterface=true → action
     * triggering brings activity to foreground with launch intent).
     */
    private fun handleVpnDisconnectIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return

        val isPluginDisconnect = action == ACTION_FROM_DISCONNECT_BTN
        val isOurDisconnect = action == ACTION_FLN_FOREGROUND &&
            intent.getStringExtra(EXTRA_ACTION_ID) == ACTION_ID_DISCONNECT

        if (!isPluginDisconnect && !isOurDisconnect) return

        Log.i(
            "PyritaMA",
            "Disconnect intent received " +
                "(plugin=${isPluginDisconnect} ours=${isOurDisconnect}), stopping VPN"
        )
        try {
            V2rayController.StopV2ray(applicationContext)
        } catch (e: Exception) {
            Log.w("PyritaMA", "StopV2ray failed: ${e.message}")
        }
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
