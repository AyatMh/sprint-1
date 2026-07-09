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

  // Reminder notification ids live in [_baseId, _baseId + _maxReminders).
  static const int _baseId = 2000;
  static const int _maxReminders = 21;
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

  // Replaces all scheduled reminders with the given ones. Each fires weekly on
  // its weekday (1=Mon … 7=Sun) at its hour:minute. Passing an empty list just
  // cancels everything.
  static Future<void> scheduleReminders(
    List<({int weekday, int hour, int minute})> reminders,
  ) async {
    await init();
    await cancelAllReminders();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'practice_reminders',
        'Practice reminders',
        channelDescription: 'Reminders to practice interviews',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    final count = reminders.length.clamp(0, _maxReminders);
    for (var i = 0; i < count; i++) {
      final r = reminders[i];
      await _plugin.zonedSchedule(
        id: _baseId + i,
        title: 'Time to practice 🎤',
        body:
            "Keep your streak going — record a quick answer and see how you're improving.",
        scheduledDate: _nextInstanceOfWeekday(r.weekday, r.hour, r.minute),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents:
            DateTimeComponents.dayOfWeekAndTime, // repeat weekly
      );
    }
  }

  static Future<void> cancelAllReminders() async {
    for (var i = 0; i < _maxReminders; i++) {
      try {
        await _plugin.cancel(id: _baseId + i);
      } catch (e) {
        debugPrint('cancelReminder $i failed: $e');
      }
    }
    // Clear the legacy single daily reminder id from older builds.
    try {
      await _plugin.cancel(id: 1001);
    } catch (_) {}
  }

  // Next occurrence of [weekday] at hour:minute in local time.
  static tz.TZDateTime _nextInstanceOfWeekday(int weekday, int hour, int minute) {
    var scheduled = _nextInstanceOfTime(hour, minute);
    while (scheduled.weekday != weekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  // Next occurrence of hour:minute in local time, tomorrow if already past.
  static tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
