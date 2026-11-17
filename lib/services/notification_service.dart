import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/constants/audio_constants.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  static const channelId = AudioConstants.notificationChannelId;
  static const channelName = AudioConstants.notificationChannelName;
  static const notificationId = AudioConstants.notificationId;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Function(String action)? _actionCallback;

  NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  void setActionCallback(Function(String action) callback) {
    _actionCallback = callback;
  }

  Future<void> init() async {
    const AndroidInitializationSettings android = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const DarwinInitializationSettings ios = DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestAlertPermission: false,
    );
    const InitializationSettings settings = InitializationSettings(
      android: android,
      iOS: ios,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Create notification channel for Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      channelName,
      importance: Importance.low,
      enableVibration: false,
      playSound: false,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  Future<void> showPlaybackNotification({
    required String title,
    required String subtitle,
    required bool isPlaying,
  }) async {
    final List<AndroidNotificationAction> actions = [
      const AndroidNotificationAction(
        AudioConstants.actionPrevSegment,
        'Previous',
        showsUserInterface: true,
        cancelNotification: false,
      ),
      AndroidNotificationAction(
        AudioConstants.actionPlayPause,
        isPlaying ? 'Pause' : 'Play',
        showsUserInterface: true,
        cancelNotification: false,
      ),
      const AndroidNotificationAction(
        AudioConstants.actionNextSegment,
        'Next',
        showsUserInterface: true,
        cancelNotification: false,
      ),
      const AndroidNotificationAction(
        AudioConstants.actionStop,
        'Stop',
        showsUserInterface: true,
        cancelNotification: true,
      ),
    ];

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.low,
      priority: Priority.low,
      showProgress: false,
      playSound: false,
      actions: actions,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
      subtitle: subtitle,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(notificationId, title, subtitle, details);
  }

  Future<void> cancelNotification() async {
    await _plugin.cancel(notificationId);
  }

  static const int downloadNotificationId = 2001;

  Future<void> showDownloadNotification({
    required String title,
    required String subtitle,
    int? progress,
    int? maxProgress,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.low,
      priority: Priority.low,
      showProgress: progress != null,
      maxProgress: maxProgress ?? 100,
      progress: progress ?? 0,
      playSound: false,
      ongoing: progress != null && progress < (maxProgress ?? 100),
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: false,
        presentSound: false,
        subtitle: subtitle,
      ),
    );

    await _plugin.show(downloadNotificationId, title, subtitle, details);
  }

  Future<void> cancelDownloadNotification() async {
    await _plugin.cancel(downloadNotificationId);
  }

  void _onNotificationResponse(NotificationResponse response) {
    final actionId = response.actionId;
    if (actionId != null && actionId.isNotEmpty && _actionCallback != null) {
      debugPrint("Notification action triggered: $actionId");
      _actionCallback!(actionId);
    }
  }
}
