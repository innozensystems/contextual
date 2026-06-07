package com.contextual.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.contextual.R
import com.contextual.app.MainActivity

object NotificationHelper {
    const val CHANNEL_TASK_CONTEXT = "task_context"
    const val GROUP_TASKS = "com.contextual.TASKS"

    fun createNotificationChannels(context: Context) {
        val name = context.getString(R.string.channel_task_context)
        val description = context.getString(R.string.channel_task_context_desc)
        val importance = NotificationManager.IMPORTANCE_HIGH
        val channel = NotificationChannel(CHANNEL_TASK_CONTEXT, name, importance).apply {
            this.description = description
            setShowBadge(true)
        }

        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    fun showContextNotification(
        context: Context,
        taskId: String,
        locationName: String,
        taskTitles: List<String>
    ) {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("task_id", taskId)
        }
        val pendingIntent = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val completeIntent = Intent(context, NotificationActionReceiver::class.java).apply {
            action = "COMPLETE_TASK"
            putExtra("task_id", taskId)
        }
        val completePending = PendingIntent.getBroadcast(
            context, taskId.hashCode(), completeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val snoozeIntent = Intent(context, NotificationActionReceiver::class.java).apply {
            action = "SNOOZE_TASK"
            putExtra("task_id", taskId)
        }
        val snoozePending = PendingIntent.getBroadcast(
            context, (taskId + "snooze").hashCode(), snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val contentText = if (taskTitles.size == 1) {
            taskTitles.first()
        } else {
            "${taskTitles.size} tasks"
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_TASK_CONTEXT)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Near: $locationName")
            .setContentText(contentText)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setGroup(GROUP_TASKS)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .addAction(R.drawable.ic_check, "Got it", completePending)
            .addAction(R.drawable.ic_snooze, "Snooze 1h", snoozePending)
            .setStyle(NotificationCompat.InboxStyle()
                .setSummaryText("$locationName — ${taskTitles.size} tasks")
                .also { style ->
                    taskTitles.forEach { style.addLine(it) }
                }
            )

        with(NotificationManagerCompat.from(context)) {
            notify(taskId.hashCode(), builder.build())
        }
    }
}
