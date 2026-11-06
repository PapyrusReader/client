package com.papyrus.reader

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Native journal survives suspension and process death without a second database writer. */
internal class TimerNotificationStore(context: Context) {
    private val prefs = context.getSharedPreferences("reading-timer-notification", Context.MODE_PRIVATE)

    fun read(): JSONObject = JSONObject(prefs.getString("state", null) ?: "{}")

    private fun write(state: JSONObject) {
        check(prefs.edit().putString("state", state.toString()).commit()) { "Timer action could not be saved" }
    }

    fun publish(snapshot: JSONObject?) {
        val state = read()
        if (state.optJSONArray("actions")?.length() ?: 0 > 0) return
        write(JSONObject().put("base", snapshot ?: JSONObject.NULL).put("actions", JSONArray()))
    }

    fun clear() = write(JSONObject())

    fun pending(): JSONObject? {
        val state = read()
        val actions = state.optJSONArray("actions") ?: return null
        if (actions.length() == 0) return null
        val base = state.getJSONObject("base")
        return JSONObject().put("sessionId", base.getString("id")).put("version", base.getString("version"))
            .put("through", actions.getJSONObject(actions.length() - 1).getString("id")).put("actions", actions)
    }

    fun acknowledge(through: String, snapshot: JSONObject?) {
        val state = read()
        val actions = state.optJSONArray("actions") ?: return
        val remaining = JSONArray()
        var found = false
        for (index in 0 until actions.length()) {
            val action = actions.getJSONObject(index)
            if (found) remaining.put(action)
            if (action.getString("id") == through) found = true
        }
        if (!found) return
        val committed = snapshot?.optString("id") == state.optJSONObject("base")?.optString("id") &&
            snapshot?.optString("version") == through
        write(JSONObject().put("base", snapshot ?: JSONObject.NULL)
            .put("actions", if (committed) remaining else JSONArray()))
    }

    fun record(id: String?, token: String?, kind: String) {
        val state = read()
        val view = view(state) ?: return
        if (view.optString("id") != id || view.optString("token") != token) return
        val phase = view.optString("phase")
        if (kind == "pause" && phase != "running") return
        if (kind == "resume" && phase != "paused") return
        if (kind !in listOf("pause", "resume", "finish")) return
        val actions = state.optJSONArray("actions") ?: JSONArray()
        check(actions.length() < 256) { "Open Papyrus to sync your timer controls" }
        actions.put(JSONObject().put("id", UUID.randomUUID().toString()).put("kind", kind)
            .put("atMs", System.currentTimeMillis()))
        state.put("actions", actions)
        write(state)
    }

    fun view(state: JSONObject = read()): JSONObject? {
        val base = state.optJSONObject("base") ?: return null
        val result = JSONObject(base.toString()).put("token", base.getString("version"))
        val actions = state.optJSONArray("actions") ?: JSONArray()
        for (index in 0 until actions.length()) {
            val action = actions.getJSONObject(index)
            val at = action.getLong("atMs")
            val recorded = elapsed(result, at)
            result.put("recordedMs", recorded).put("runningSinceMs", JSONObject.NULL)
                .put("token", action.getString("id"))
            when (action.getString("kind")) {
                "resume" -> result.put("phase", "running").put("runningSinceMs", at)
                "pause" -> result.put("phase", "paused")
                "finish" -> return null
            }
        }
        if (!result.isNull("targetMs") && elapsed(result) >= result.getLong("targetMs")) {
            result.put("phase", "finished").put("recordedMs", result.getLong("targetMs"))
                .put("runningSinceMs", JSONObject.NULL)
        }
        return result
    }

    companion object {
        fun elapsed(view: JSONObject, now: Long = System.currentTimeMillis()): Long {
            val recorded = view.optLong("recordedMs")
            val elapsed = recorded + if (view.isNull("runningSinceMs")) 0 else (now - view.getLong("runningSinceMs")).coerceAtLeast(0)
            return if (view.isNull("targetMs")) elapsed else elapsed.coerceAtMost(view.getLong("targetMs"))
        }
    }
}

internal object TimerNotifications {
    const val channelId = "reading_timer"
    const val notificationId = 7143
    const val permissionRequest = 7144
    const val openExtra = "papyrus.open_timer"
    private var channel: MethodChannel? = null
    private var engine: FlutterEngine? = null
    private var openPending = false

    fun configure(activity: Activity, engine: FlutterEngine) {
        this.engine = engine
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "papyrus/reading_timer").also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                try {
                    val store = TimerNotificationStore(activity)
                    val args = call.arguments as? Map<*, *>
                    val snapshot = (args?.get("snapshot") as? Map<*, *>)?.let { JSONObject(it) }
                    when (call.method) {
                        "pending" -> {
                            if (openPending) {
                                openPending = false
                                Handler(Looper.getMainLooper()).post { bridge.invokeMethod("open", null) }
                            }
                            result.success(store.pending()?.toMap())
                        }
                        "publish" -> {
                            store.publish(snapshot)
                            refresh(activity, args?.get("foreground") == true)
                            result.success(null)
                        }
                        "acknowledge" -> {
                            store.acknowledge(args?.get("through") as String, snapshot)
                            refresh(activity, false)
                            result.success(null)
                        }
                        "clear" -> {
                            store.clear()
                            refresh(activity, false)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("notification", error.message, null)
                }
            }
        }
        opened(activity.intent)
    }

    fun detach(engine: FlutterEngine) {
        if (this.engine === engine) {
            channel?.setMethodCallHandler(null)
            channel = null
            this.engine = null
        }
    }

    fun opened(intent: Intent?) {
        if (intent?.getBooleanExtra(openExtra, false) == true) {
            openPending = true
            channel?.invokeMethod("changed", null)
        }
    }

    fun changed() = channel?.invokeMethod("changed", null)

    fun refresh(context: Context, foreground: Boolean) {
        val view = TimerNotificationStore(context).view()
        if (view == null) {
            context.stopService(Intent(context, ReadingTimerService::class.java))
            NotificationManagerCompat.from(context).cancel(notificationId)
            return
        }
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            val prefs = context.getSharedPreferences("reading-timer-notification", Context.MODE_PRIVATE)
            if (foreground && context is Activity && !prefs.getBoolean("permissionAsked", false)) {
                prefs.edit().putBoolean("permissionAsked", true).apply()
                ActivityCompat.requestPermissions(context, arrayOf(Manifest.permission.POST_NOTIFICATIONS), permissionRequest)
            }
            return
        }
        if (ReadingTimerService.current != null) {
            ReadingTimerService.current?.refresh()
        } else if (foreground) {
            ContextCompat.startForegroundService(context, Intent(context, ReadingTimerService::class.java))
        }
    }

    private fun JSONObject.toMap(): Map<String, Any?> = keys().asSequence().associateWith { key ->
        when (val value = get(key)) {
            JSONObject.NULL -> null
            is JSONObject -> value.toMap()
            is JSONArray -> (0 until value.length()).map { value.getJSONObject(it).toMap() }
            else -> value
        }
    }
}

class ReadingTimerService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private val update = Runnable { refresh() }
    private val wake = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = refresh()
    }

    override fun onCreate() {
        super.onCreate()
        current = this
        ContextCompat.registerReceiver(this, wake, IntentFilter(Intent.ACTION_SCREEN_ON), ContextCompat.RECEIVER_NOT_EXPORTED)
        if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(TimerNotifications.channelId, "Reading timer", NotificationManager.IMPORTANCE_LOW)
                    .apply { description = "Active reading sessions and timer controls"; setSound(null, null) }
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            intent?.getStringExtra("kind")?.let {
                TimerNotificationStore(this).record(intent.getStringExtra("id"), intent.getStringExtra("token"), it)
                TimerNotifications.changed()
            }
            refresh()
        } catch (_: Exception) {
            // A failed durable write leaves the previous timer and its controls intact.
            refresh()
        }
        return START_STICKY
    }

    fun refresh() {
        handler.removeCallbacks(update)
        val view = TimerNotificationStore(this).view()
        if (view == null) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        val elapsed = TimerNotificationStore.elapsed(view)
        val running = view.getString("phase") == "running"
        val finished = view.getString("phase") == "finished"
        val countdown = !view.isNull("targetMs")
        val shown = if (countdown) (view.getLong("targetMs") - elapsed).coerceAtLeast(0) else elapsed
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(TimerNotifications.openExtra, true), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = NotificationCompat.Builder(this, TimerNotifications.channelId)
            .setSmallIcon(R.drawable.ic_reading_timer).setContentTitle(view.getString("title"))
            .setContentText(if (finished) (if (countdown && shown == 0L) "Reading goal reached" else "Finished") else if (running) "Reading" else "Paused · ${format(shown)}")
            .setContentIntent(open).setOnlyAlertOnce(true).setOngoing(!finished).setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_STOPWATCH).setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setShowWhen(running).setUsesChronometer(running).setChronometerCountDown(countdown)
            .setWhen(if (countdown) System.currentTimeMillis() + shown else System.currentTimeMillis() - elapsed)
        if (!finished) builder.addAction(0, if (running) "Pause" else "Resume", action(view, if (running) "pause" else "resume"))
        builder.addAction(0, if (finished) "Save" else "Finish", action(view, "finish"))
        val notification = builder.build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(TimerNotifications.notificationId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(TimerNotifications.notificationId, notification)
        }
        if (!running) {
            stopForeground(STOP_FOREGROUND_DETACH)
            stopSelf()
        } else if (running && countdown) {
            handler.postDelayed(update, shown.coerceAtLeast(1))
        }
    }

    private fun action(view: JSONObject, kind: String): PendingIntent {
        val intent = Intent(this, ReadingTimerService::class.java).putExtra("kind", kind)
            .putExtra("id", view.getString("id")).putExtra("token", view.getString("token"))
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return if (Build.VERSION.SDK_INT >= 26) PendingIntent.getForegroundService(this, kind.hashCode(), intent, flags)
            else PendingIntent.getService(this, kind.hashCode(), intent, flags)
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        unregisterReceiver(wake)
        if (current === this) current = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        internal var current: ReadingTimerService? = null
        private fun format(milliseconds: Long): String {
            val seconds = milliseconds / 1000
            return if (seconds >= 3600) "%d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60)
                else "%02d:%02d".format(seconds / 60, seconds % 60)
        }
    }
}
