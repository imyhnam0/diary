package com.example.diary

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.util.Base64
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

class DiaryMoodWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (widgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, widgetId)
        }
    }

    companion object {
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_TODAY = "flutter.widget_today_emoji"
        private const val KEY_TODAY_IMAGE = "flutter.widget_today_image_base64"
        private const val KEY_RECENT = "flutter.widget_recent_emojis_json"
        private const val KEY_RECENT_IMAGES = "flutter.widget_recent_images_json"
        private const val KEY_MONTH = "flutter.widget_month_key"
        private const val KEY_MONTH_MAP = "flutter.widget_month_map_json"
        private const val KEY_MONTH_MAP_IMAGES = "flutter.widget_month_map_images_json"
        private const val KEY_LANGUAGE = "flutter.widget_language"

        fun updateAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, DiaryMoodWidgetProvider::class.java)
            val widgetIds = manager.getAppWidgetIds(component)
            for (widgetId in widgetIds) {
                updateWidget(context, manager, widgetId)
            }
        }

        private fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.diary_mood_widget)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val languageCode = prefs.getString(KEY_LANGUAGE, "ko") ?: "ko"
            val isEnglish = languageCode == "en"

            views.setTextViewText(R.id.widget_today_label, if (isEnglish) "TODAY" else "오늘")
            views.setTextViewText(R.id.widget_recent_label, if (isEnglish) "RECENT" else "최근")

            val todayEmoji = prefs.getString(KEY_TODAY, "") ?: ""
            val todayImage = prefs.getString(KEY_TODAY_IMAGE, "") ?: ""
            val hasTodayRecord = hasTodayRecord(prefs)
            bindMood(
                views = views,
                textViewId = R.id.widget_today_emoji,
                imageViewId = R.id.widget_today_icon,
                emoji = if (hasTodayRecord) todayEmoji else "",
                imageBase64 = if (hasTodayRecord) todayImage else "",
                emptyText = if (isEnglish) "None" else "없음"
            )

            val recent = parseRecentEmojis(prefs.getString(KEY_RECENT, "[]") ?: "[]")
            val recentImages = parseRecentEmojis(prefs.getString(KEY_RECENT_IMAGES, "[]") ?: "[]")
            val recentViews = intArrayOf(
                R.id.widget_recent_1,
                R.id.widget_recent_2,
                R.id.widget_recent_3,
                R.id.widget_recent_4,
                R.id.widget_recent_5,
                R.id.widget_recent_6
            )
            val recentImageViews = intArrayOf(
                R.id.widget_recent_1_icon,
                R.id.widget_recent_2_icon,
                R.id.widget_recent_3_icon,
                R.id.widget_recent_4_icon,
                R.id.widget_recent_5_icon,
                R.id.widget_recent_6_icon
            )
            for (i in recentViews.indices) {
                val emoji = if (i < recent.size) recent[i] else ""
                val image = if (i < recentImages.size) recentImages[i] else ""
                bindMood(
                    views = views,
                    textViewId = recentViews[i],
                    imageViewId = recentImageViews[i],
                    emoji = emoji,
                    imageBase64 = image,
                    emptyText = ""
                )
            }

            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    appWidgetId,
                    launchIntent,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    } else {
                        PendingIntent.FLAG_UPDATE_CURRENT
                    }
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun parseRecentEmojis(rawJson: String): List<String> {
            return try {
                val arr = JSONArray(rawJson)
                buildList {
                    for (i in 0 until arr.length()) {
                        val value = arr.optString(i, "")
                        if (value.isNotBlank()) add(value)
                    }
                }
            } catch (_: Exception) {
                emptyList()
            }
        }

        private fun bindMood(
            views: RemoteViews,
            textViewId: Int,
            imageViewId: Int,
            emoji: String,
            imageBase64: String,
            emptyText: String
        ) {
            val imageBytes = decodeBase64(imageBase64)
            if (imageBytes != null) {
                val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                if (bitmap != null) {
                    views.setImageViewBitmap(imageViewId, bitmap)
                    views.setViewVisibility(imageViewId, View.VISIBLE)
                    views.setViewVisibility(textViewId, View.GONE)
                    return
                }
            }

            views.setTextViewText(textViewId, if (emoji.isBlank()) emptyText else emoji)
            views.setViewVisibility(textViewId, View.VISIBLE)
            views.setViewVisibility(imageViewId, View.GONE)
        }

        private fun decodeBase64(value: String): ByteArray? {
            if (value.isBlank()) return null
            return try {
                Base64.decode(value, Base64.DEFAULT)
            } catch (_: Exception) {
                null
            }
        }

        private fun hasTodayRecord(
            prefs: android.content.SharedPreferences
        ): Boolean {
            val monthKey = prefs.getString(KEY_MONTH, "") ?: ""
            val now = Calendar.getInstance()
            val currentMonthKey = String.format(
                "%04d-%02d",
                now.get(Calendar.YEAR),
                now.get(Calendar.MONTH) + 1
            )
            if (monthKey != currentMonthKey) {
                return false
            }

            val todayKey = "${now.get(Calendar.DAY_OF_MONTH)}"
            val monthEmojiMap = parseJsonMap(prefs.getString(KEY_MONTH_MAP, "{}") ?: "{}")
            val monthImageMap = parseJsonMap(prefs.getString(KEY_MONTH_MAP_IMAGES, "{}") ?: "{}")
            val hasEmoji = (monthEmojiMap[todayKey] ?: "").isNotBlank()
            val hasImage = (monthImageMap[todayKey] ?: "").isNotBlank()
            return hasEmoji || hasImage
        }

        private fun parseJsonMap(rawJson: String): Map<String, String> {
            return try {
                val obj = JSONObject(rawJson)
                buildMap {
                    val keys = obj.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        val value = obj.optString(key, "")
                        if (value.isNotBlank()) {
                            put(key, value)
                        }
                    }
                }
            } catch (_: Exception) {
                emptyMap()
            }
        }
    }
}
