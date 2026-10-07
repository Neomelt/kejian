package dev.kejian.kejian

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONArray

/** Reinstates persisted alarms after a reboot or app update. */
class ReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val raw = context.getSharedPreferences(ReminderReceiver.PREFS, Context.MODE_PRIVATE)
            .getString(ReminderReceiver.KEY_ITEMS, "[]") ?: "[]"
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        runCatching {
            val array = JSONArray(raw)
            for (index in 0 until array.length()) {
                val item = array.getJSONObject(index)
                val timestamp = item.optLong("timestamp")
                if (timestamp <= now) continue
                alarms.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    timestamp,
                    ReminderReceiver.alarmIntent(
                        context,
                        item.getInt("id"),
                        item.optString("title"),
                        item.optString("body")
                    )
                )
            }
        }
    }
}
