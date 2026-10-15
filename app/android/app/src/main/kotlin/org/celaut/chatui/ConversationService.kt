package org.celaut.chatui

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/// Keeps the process, and so the tunnel sockets, alive while a conversation with a
/// service is open and the app is in the background (`docs/celaut-plan.md`, section 3).
/// The instance itself runs on the node and is not affected.
///
/// The foreground service type is `specialUse`. `dataSync` is for transfers that end,
/// and on Android 15 (targetSdk 35 and later) the system stops it after 6 hours in 24;
/// a conversation can be longer. `specialUse` has no such limit. It needs a subtype
/// property in the manifest, and a store review if the app is on Google Play; this app
/// is not.
///
/// If the user refuses the notification permission (Android 13+), the service still
/// runs: the system shows it in the list of running apps, but there is no notification
/// in the shade.
class ConversationService : Service() {
    companion object {
        private const val CHANNEL_ID = "conversation"
        private const val NOTIFICATION_ID = 7301

        fun start(context: Context): Boolean = try {
            context.applicationContext.let {
                androidx.core.content.ContextCompat.startForegroundService(
                    it, Intent(it, ConversationService::class.java)
                )
            }
            true
        } catch (e: Exception) {
            // For example ForegroundServiceStartNotAllowedException (Android 12+) when
            // the app is not in the foreground. The conversation works without it.
            false
        }

        fun stop(context: Context) {
            val app = context.applicationContext
            app.stopService(Intent(app, ConversationService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val notification = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            stopSelf()
        }
        // The service holds nothing but the process: if the system kills it, the
        // tunnel is gone and there is nothing to restart.
        return START_NOT_STICKY
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.conversation_channel_name),
                    NotificationManager.IMPORTANCE_LOW
                )
            )
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(
                this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        }
        return builder
            .setSmallIcon(R.drawable.ic_conversation)
            .setContentTitle(getString(R.string.conversation_notification_title))
            .setContentText(getString(R.string.conversation_notification_text))
            .setOngoing(true)
            .setContentIntent(open)
            .build()
    }
}
