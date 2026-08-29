import 'dart:async';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pocket_bot/utils/logger.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  int _notificationCount = 0;

  Future<void> initialize() async {
    if (_isInitialized) return;

    Logger.info('Initializing notification service...');

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(settings);
    await _createNotificationChannel();
    _isInitialized = true;
    Logger.info('Notification service initialized');
  }

  Future<void> _createNotificationChannel() async {
    if (Platform.isAndroid) {
      const androidChannel = AndroidNotificationChannel(
        'messages',
        'Messages',
        description: 'Chat message notifications',
        importance: Importance.max,
        showBadge: true,
        enableVibration: true,
        playSound: true,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);
      
      Logger.info('Notification channel created');
    }
  }

  Future<bool> requestPermissions() async {
    Logger.info('Requesting notification permissions...');
    
    if (Platform.isIOS) {
      final granted = await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      final result = granted ?? false;
      Logger.info('iOS notification permission: $result');
      return result;
    } else if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      
      final granted = await androidPlugin?.requestNotificationsPermission();
      final result = granted ?? false;
      Logger.info('Android notification permission: $result');
      return result;
    }
    
    return false;
  }

  Future<bool> _checkPermission() async {
    if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      
      return await androidPlugin?.areNotificationsEnabled() ?? false;
    }
    return true;
  }

  Future<void> showMessageNotification({
    required String sessionKey,
    required String sessionName,
    required String message,
  }) async {
    final hasPermission = await _checkPermission();
    
    if (!hasPermission) {
      Logger.warning('Notification permission not enabled');
      return;
    }

    Logger.info('Showing notification: sessionKey=$sessionKey, message=$message');

    final truncatedName = sessionName.length > 20
        ? '...${sessionName.substring(sessionName.length - 17)}'
        : sessionName;

    final displayText = message.length > 80
        ? '${message.substring(0, 80)}...'
        : message;

    _notificationCount++;

    const androidDetails = AndroidNotificationDetails(
      'messages',
      'Messages',
      channelDescription: 'Chat message notifications',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _notifications.show(
        sessionKey.hashCode ^ _notificationCount,
        '$truncatedName:',
        displayText,
        details,
      );
      Logger.info('Notification shown successfully');
    } catch (e) {
      Logger.error('Failed to show notification: $e');
    }
  }

  Future<void> cancelNotification(String sessionKey) async {
    await _notifications.cancel(sessionKey.hashCode);
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
    _notificationCount = 0;
  }
}
