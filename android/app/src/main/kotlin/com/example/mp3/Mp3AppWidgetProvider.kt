package com.example.mp3

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.KeyEvent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetLaunchIntent

class Mp3AppWidgetProvider : HomeWidgetProvider() {

    companion object {
        const val ACTION_PLAY_PAUSE = "com.example.mp3.WIDGET_PLAY_PAUSE"
        const val ACTION_PREV = "com.example.mp3.WIDGET_PREV"
        const val ACTION_NEXT = "com.example.mp3.WIDGET_NEXT"
        const val ACTION_REWIND = "com.example.mp3.WIDGET_REWIND"
        const val ACTION_FORWARD = "com.example.mp3.WIDGET_FORWARD"
        const val ACTION_STOP = "com.example.mp3.WIDGET_STOP"
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_PLAY_PAUSE -> sendMediaKeyEvent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
            ACTION_PREV -> sendMediaKeyEvent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS)
            ACTION_NEXT -> sendMediaKeyEvent(context, KeyEvent.KEYCODE_MEDIA_NEXT)
            ACTION_REWIND -> sendMediaKeyEvent(context, KeyEvent.KEYCODE_MEDIA_REWIND)
            ACTION_FORWARD -> sendMediaKeyEvent(context, KeyEvent.KEYCODE_MEDIA_FAST_FORWARD)
            ACTION_STOP -> sendMediaKeyEvent(context, KeyEvent.KEYCODE_MEDIA_STOP)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_layout).apply {
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java
                )
                setOnClickPendingIntent(R.id.widget_container, pendingIntent)

                val title = widgetData.getString("title", null) ?: "MP360"
                val artist = widgetData.getString("artist", null) ?: "No Audio Playing"
                val isPlaying = widgetData.getBoolean("isPlaying", false)

                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_artist, artist)

                setImageViewResource(
                    R.id.widget_btn_play_pause,
                    if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
                )

                setOnClickPendingIntent(
                    R.id.widget_btn_prev,
                    createBroadcastPendingIntent(context, ACTION_PREV, 101)
                )
                setOnClickPendingIntent(
                    R.id.widget_btn_rewind,
                    createBroadcastPendingIntent(context, ACTION_REWIND, 103)
                )
                setOnClickPendingIntent(
                    R.id.widget_btn_play_pause,
                    createBroadcastPendingIntent(context, ACTION_PLAY_PAUSE, 100)
                )
                setOnClickPendingIntent(
                    R.id.widget_btn_forward,
                    createBroadcastPendingIntent(context, ACTION_FORWARD, 104)
                )
                setOnClickPendingIntent(
                    R.id.widget_btn_next,
                    createBroadcastPendingIntent(context, ACTION_NEXT, 102)
                )
                setOnClickPendingIntent(
                    R.id.widget_btn_stop,
                    createBroadcastPendingIntent(context, ACTION_STOP, 105)
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun createBroadcastPendingIntent(
        context: Context,
        action: String,
        requestCode: Int
    ): PendingIntent {
        val intent = Intent(context, Mp3AppWidgetProvider::class.java).apply {
            this.action = action
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun sendMediaKeyEvent(context: Context, keyCode: Int) {
        val receiverClass = try {
            Class.forName("com.ryanheise.audioservice.MediaButtonReceiver")
        } catch (_: Exception) {
            null
        }

        if (receiverClass != null) {
            val downIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                component = ComponentName(context, receiverClass)
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            }
            context.sendBroadcast(downIntent)

            val upIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                component = ComponentName(context, receiverClass)
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_UP, keyCode))
            }
            context.sendBroadcast(upIntent)
        }
    }
}
