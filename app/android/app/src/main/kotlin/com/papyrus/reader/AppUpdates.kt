package com.papyrus.reader

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class AppUpdates(private val activity: Activity) {
    private val packageManager get() = activity.packageManager
    private val packageName get() = activity.packageName
    private val cacheDir get() = activity.cacheDir
    private val preferences by lazy { activity.getPreferences(Activity.MODE_PRIVATE) }
    private val updates by lazy { AppUpdateManagerFactory.create(activity) }
    private val requestCode = 7412

    fun configure(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.papyrus.reader/updates")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "channel" -> result.success(BuildConfig.FLAVOR)
                        "check" -> updates.appUpdateInfo
                            .addOnSuccessListener { info ->
                                val available = info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE &&
                                    info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)
                                result.success(if (available) info.availableVersionCode() else null)
                            }
                            .addOnFailureListener { result.error("play", "Google Play could not check for updates", null) }
                        "installPlay" -> updates.appUpdateInfo
                            .addOnSuccessListener { info ->
                                try {
                                    val started = updates.startUpdateFlowForResult(
                                        info, activity, AppUpdateOptions.newBuilder(AppUpdateType.IMMEDIATE).build(), requestCode
                                    )
                                    if (started) {
                                        preferences.edit().putBoolean("playUpdateStarted", true).apply()
                                        result.success(null)
                                    }
                                    else result.error("play", "Google Play did not start the update", null)
                                } catch (error: Exception) {
                                    result.error("play", "Could not start the Play update", null)
                                }
                            }
                            .addOnFailureListener { result.error("play", "Google Play update is unavailable", null) }
                        "canInstall" -> {
                            check(BuildConfig.FLAVOR == "direct")
                            val allowed = Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls()
                            if (!allowed) {
                                activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                            }
                            result.success(allowed)
                        }
                        "installApk" -> {
                            installApk(requireNotNull(call.argument<String>("path")))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("update", "Could not prepare the update", null)
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun installApk(filename: String) {
        check(BuildConfig.FLAVOR == "direct")
        val file = File(filename).canonicalFile
        val directory = File(cacheDir, "papyrus-updates").canonicalFile
        require(file.path.startsWith(directory.path + File.separator) && file.isFile)
        val flags = PackageManager.GET_SIGNATURES
        val candidate = requireNotNull(packageManager.getPackageArchiveInfo(file.path, flags))
        val installed = packageManager.getPackageInfo(packageName, flags)
        require(candidate.packageName == packageName && candidate.versionCode > installed.versionCode)
        require(candidate.signatures?.toSet() == installed.signatures?.toSet() && !candidate.signatures.isNullOrEmpty())
        val uri = FileProvider.getUriForFile(activity, "$packageName.updates", file)
        activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
    }

    fun resumeUpdate() {
        if (BuildConfig.FLAVOR != "play" || !preferences.getBoolean("playUpdateStarted", false)) return
        updates.appUpdateInfo.addOnSuccessListener { info ->
            if (info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS) {
                try {
                    updates.startUpdateFlowForResult(
                        info, activity, AppUpdateOptions.newBuilder(AppUpdateType.IMMEDIATE).build(), requestCode
                    )
                } catch (_: Exception) {
                    // A failed or cancelled update must leave the library usable.
                }
            } else {
                preferences.edit().remove("playUpdateStarted").apply()
            }
        }
    }
}
