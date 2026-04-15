import 'dart:developer' as developer;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static const String _logTag = 'NotificationService';

  Future<void> init() async {
    developer.log('Initializing notifications', name: _logTag);
    tz_data.initializeTimeZones();
    final Object localTimezoneInfo = await FlutterTimezone.getLocalTimezone();
    final String timeZoneName = _resolveTimezoneName(localTimezoneInfo);
    developer.log(
      'Timezone resolved from "$localTimezoneInfo" -> "$timeZoneName"',
      name: _logTag,
    );
    tz.setLocalLocation(_resolveTimezoneLocation(timeZoneName));

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
          macOS: initializationSettingsDarwin,
        );

    await _notificationsPlugin.initialize(settings: initializationSettings);
    developer.log('Notifications initialized', name: _logTag);
  }

  /// Extract an IANA timezone (e.g. `Asia/Kolkata`) from plugin output.
  String _resolveTimezoneName(Object timezoneInfo) {
    final String rawValue = timezoneInfo.toString();
    final RegExpMatch? ianaMatch = RegExp(
      r'[A-Za-z_]+(?:/[A-Za-z_+-]+)+',
    ).firstMatch(rawValue);
    return ianaMatch?.group(0) ?? 'UTC';
  }

  /// Guard against unknown timezone identifiers and use UTC as fallback.
  tz.Location _resolveTimezoneLocation(String timezoneName) {
    try {
      return tz.getLocation(timezoneName);
    } on Exception {
      developer.log(
        'Unknown timezone "$timezoneName", falling back to UTC',
        name: _logTag,
      );
      return tz.UTC;
    }
  }

  /// Schedule a notification for a task
  Future<void> scheduleTaskReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    developer.log(
      'Scheduling reminder id=$id at $scheduledTime with title="$title"',
      name: _logTag,
    );
    await _notificationsPlugin.zonedSchedule(
      id: id,
      scheduledDate: tz.TZDateTime.from(scheduledTime, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'task_reminders',
          'Task Reminders',
          channelDescription: 'Regular reminders for unfinished tasks',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      title: title,
      body: body,
    );
    developer.log('Reminder scheduled id=$id', name: _logTag);
  }

  /// Cancel a specific notification
  Future<void> cancelNotification(int id) async {
    developer.log('Cancelling reminder id=$id', name: _logTag);
    await _notificationsPlugin.cancel(id: id);
  }
}
