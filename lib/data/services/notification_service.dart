import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// Thin wrapper around flutter_local_notifications for the daily practice
// reminder. Everything is static so it can be initialized once in main().
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _dailyReminderId = 1001;
  static bool _ready = false;

  // Sets up timezones and the plugin. Safe to call once at startup.
  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (_) {
      // Fall back to UTC — reminders still fire, just anchored to UTC.
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
    );
    _ready = true;
  }

  // Requests OS permission to post notifications (Android 13+, iOS).
  static Future<bool> requestPermissions() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    var granted = true;
    if (android != null) {
      granted = await android.requestNotificationsPermission() ?? true;
    }
    if (ios != null) {
      granted = await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          true;
    }
    return granted;
  }

  // (Re)schedules a reminder that repeats every day at [hour]:[minute].
  static Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
  }) async {
    await init();
    await cancelReminder();

    await _plugin.zonedSchedule(
      id: _dailyReminderId,
      title: 'Time to practice 🎤',
      body:
          "Keep your streak going — record a quick answer and see how you're improving.",
      scheduledDate: _nextInstanceOf(hour, minute),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'practice_reminders',
          'Practice reminders',
          channelDescription: 'Daily reminders to practice interviews',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily
    );
  }

  static Future<void> cancelReminder() async {
    try {
      await _plugin.cancel(id: _dailyReminderId);
    } catch (e) {
      debugPrint('cancelReminder failed: $e');
    }
  }

  // The next occurrence of hour:minute in local time, tomorrow if already past.
  static tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
