package com.example.mp3

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.view.KeyEvent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetLaunchIntent

class Mp3AppWidgetProvider : HomeWidgetProvider() {

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
                    R.id.widget_btn_play_pause,
                    createMediaActionPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 100)
                )
                setOnClickPendingIntent(
                    R.id.widget_btn_prev,
                    createMediaActionPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS, 101)
                )
                setOnClickPendingIntent(
                    R.id.widget_btn_next,
                    createMediaActionPendingIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT, 102)
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun createMediaActionPendingIntent(
        context: Context,
        keyCode: Int,
        requestCode: Int
    ): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            setPackage(context.packageName)
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}

