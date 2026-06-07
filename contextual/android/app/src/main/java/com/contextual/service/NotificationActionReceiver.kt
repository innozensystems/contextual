package com.contextual.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.contextual.data.SupabaseClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val taskId = intent.getStringExtra("task_id") ?: return

        when (intent.action) {
            "COMPLETE_TASK" -> {
                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        SupabaseClient.completeTask(taskId)
                        // Show undo notification
                        showUndoNotification(context, taskId)
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }
            "SNOOZE_TASK" -> {
                // Reschedule notification for 1 hour
                val snoozeIntent = Intent(context, NotificationActionReceiver::class.java).apply {
                    action = "TRIGGER_SNOOZED"
                    putExtra("task_id", taskId)
                }
                // Use AlarmManager in production
            }
        }
    }

    private fun showUndoNotification(context: Context, taskId: String) {
        // In production: show undo notification with 10s timeout
    }
}
