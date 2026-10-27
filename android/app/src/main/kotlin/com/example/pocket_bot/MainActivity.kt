package com.example.pocket_bot

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.ConnectivityManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.Inet4Address

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, tailnetChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "suffix") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    result.success(tailnetProbe())
                } catch (error: Exception) {
                    Log.w("PocketBot", "tailnet probe failed", error)
                    result.success(
                        mapOf(
                            "domains" to "",
                            "addresses" to emptyList<String>(),
                        ),
                    )
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "install") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path.isNullOrEmpty()) {
                    result.error("bad_path", "missing apk path", null)
                    return@setMethodCallHandler
                }
                try {
                    installApk(File(path))
                    result.success(true)
                } catch (error: Exception) {
                    result.error("install_failed", error.message, null)
                }
            }
    }

    private fun tailnetProbe(): Map<String, Any> {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return mapOf("domains" to "", "addresses" to emptyList<String>())
        val domains = StringBuilder()
        val addresses = ArrayList<String>()
        for (network in manager.allNetworks) {
            val props = manager.getLinkProperties(network) ?: continue
            val value = props.domains
            if (!value.isNullOrBlank()) {
                if (domains.isNotEmpty()) domains.append(',')
                domains.append(value)
            }
            for (link in props.linkAddresses) {
                val address = link.address
                if (address !is Inet4Address) continue
                val host = address.hostAddress ?: continue
                if (host !in addresses) addresses.add(host)
            }
        }
        return mapOf("domains" to domains.toString(), "addresses" to addresses)
    }

    private fun installApk(file: File) {
        if (!file.isFile || file.length() <= 0L) {
            throw IllegalArgumentException("apk is missing")
        }
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setSize(file.length())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
        }
        val sessionId = installer.createSession(params)
        val session = installer.openSession(sessionId)
        try {
            session.openWrite("base.apk", 0, file.length()).use { output ->
                file.inputStream().use { input -> input.copyTo(output) }
                session.fsync(output)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
            val pending = PendingIntent.getBroadcast(
                this,
                sessionId,
                Intent(this, ApkInstallReceiver::class.java),
                flags,
            )
            session.commit(pending.intentSender)
        } catch (error: Exception) {
            session.abandon()
            throw error
        } finally {
            session.close()
        }
    }

    companion object {
        const val channelName = "pocketbot/apk_install"
        const val tailnetChannelName = "pocketbot/tailnet"
    }
}
