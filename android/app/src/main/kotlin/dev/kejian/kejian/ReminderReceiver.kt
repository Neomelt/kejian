package dev.kejian.kejian

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/** Delivers one local course reminder. The alarm itself is intentionally inexact. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ID, 0)
        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty().ifBlank { "课程提醒" }
        val body = intent.getStringExtra(EXTRA_BODY).orEmpty()
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "课程提醒", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "课程开始前的本地提醒"
                }
            )
        }
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = launch?.let {
            PendingIntent.getActivity(context, id, it, PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag())
        }
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .apply { if (contentIntent != null) setContentIntent(contentIntent) }
            .build()
        manager.notify(id, notification)
    }

    companion object {
        const val CHANNEL_ID = "course_reminders"
        const val EXTRA_ID = "id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val PREFS = "reminder_schedule"
        const val KEY_ITEMS = "items"

        fun immutableFlag(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else 0

        fun alarmIntent(context: Context, id: Int, title: String, body: String): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                id,
                Intent(context, ReminderReceiver::class.java).apply {
                    putExtra(EXTRA_ID, id)
                    putExtra(EXTRA_TITLE, title)
                    putExtra(EXTRA_BODY, body)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
            )

        fun cancelAll(context: Context, ids: Collection<Int>) {
            val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            ids.forEach { alarms.cancel(alarmIntent(context, it, "", "")) }
            context.getSystemService(Context.NOTIFICATION_SERVICE)?.let {
                (it as NotificationManager).cancelAll()
            }
        }
    }
}
