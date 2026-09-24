package com.vtq.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Mientras la app esté abierta la pantalla no se apaga.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vtq/updater")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getVersionCode" -> result.success(versionCode())
                    // Carpeta que expone el FileProvider (ver res/xml/file_paths.xml).
                    "getUpdateDir" -> result.success(File(cacheDir, "updates").apply { mkdirs() }.absolutePath)
                    "installApk" -> result.success(installApk(call.argument<String>("path")!!))
                    else -> result.notImplemented()
                }
            }
    }

    private fun versionCode(): Long {
        val info = packageManager.getPackageInfo(packageName, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
    }

    /**
     * Abre el instalador de Android con la APK descargada.
     * Devuelve "needs_permission" si el usuario todavía no ha permitido que VTQ
     * instale apps (se abre esa pantalla de ajustes y Dart reintenta al volver).
     */
    private fun installApk(path: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
            )
            return "needs_permission"
        }

        val uri = FileProvider.getUriForFile(this, "$packageName.updates", File(path))
        startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        return "started"
    }
}
