import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:tasks/data/database_service.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String studyChannelId = 'nyro_study_channel';
  static const String studyChannelName = 'NYRO Study Notifications';
  static const String dailyChannelId = 'nyro_daily_channel';
  static const String dailyChannelName = 'Daily Study Routine';
  static const String alarmChannelId = 'nyro_alarm_channel';
  static const String alarmChannelName = 'Full-Screen Study Alarms';

  final StreamController<String> _payloadController = StreamController<String>.broadcast();
  Stream<String> get onNotificationPayloadTapped => _payloadController.stream;

  String? _pendingLaunchPayload;
  String? get pendingLaunchPayload => _pendingLaunchPayload;
  void clearPendingLaunchPayload() => _pendingLaunchPayload = null;

  Future<void> init() async {
    _configureLocalTimeZone();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        final payload = response.payload;
        final actionId = response.actionId;

        if (actionId == 'snooze_5' || actionId == 'snooze_10') {
          final minutes = (actionId == 'snooze_5') ? 5 : 10;
          final snoozeDt = DateTime.now().add(Duration(minutes: minutes));
          final reminderId = (response.id != null && response.id! > 0)
              ? response.id!
              : (DateTime.now().millisecondsSinceEpoch % 100000);
          final isAlarm = payload != null && payload.startsWith('route:alarm:');
          await NotificationService.instance.scheduleReminder(
            id: reminderId,
            title: 'Snoozed Reminder',
            body: 'Snoozed for $minutes minutes',
            scheduledDate: snoozeDt,
            alertType: isAlarm ? 'alarm' : 'notification',
          );
        } else if (actionId == 'dismiss') {
          if (response.id != null) {
            await NotificationService.instance.cancelReminder(response.id!);
          }
        } else if (payload != null && payload.isNotEmpty) {
          _payloadController.add(payload);
        }
      },
    );

    try {
      final launchDetails = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
      if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
        _pendingLaunchPayload = launchDetails.notificationResponse?.payload;
      }
    } catch (_) {}

    // Create Notification Channels explicitly on Android 8.0+
    final android = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          studyChannelId,
          studyChannelName,
          description: 'Alerts and reminders for GATE study tasks, custom reminders, and revisits',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          dailyChannelId,
          dailyChannelName,
          description: 'Scheduled reminders for Morning, Afternoon, and Evening study blocks',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          alarmChannelId,
          alarmChannelName,
          description: 'Critical ringing study alarms with full-screen wake screen',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
    }

    // Request permissions asynchronously without blocking app startup
    requestPermissions().catchError((_) => false);

    // Automatically load alert settings from DatabaseService and schedule daily routine on startup
    try {
      final alertSettings = await DatabaseService.instance.getAlertSettings();
      final morning = (alertSettings['morning_brief'] as int? ?? 1) == 1;
      final afternoon = (alertSettings['afternoon_session'] as int? ?? 1) == 1;
      final evening = (alertSettings['evening_review'] as int? ?? 1) == 1;
      await scheduleDailySessionAlerts(
        morning: morning,
        afternoon: afternoon,
        evening: evening,
      );
    } catch (_) {}
  }

  void _configureLocalTimeZone() {
    tz_data.initializeTimeZones();
    try {
      final offset = DateTime.now().timeZoneOffset;
      // Match timezone database against current system offset
      for (final entry in tz.timeZoneDatabase.locations.entries) {
        final loc = entry.value;
        final nowInLoc = tz.TZDateTime.now(loc);
        if (nowInLoc.timeZoneOffset == offset) {
          tz.setLocalLocation(loc);
          return;
        }
      }
    } catch (_) {}
  }

  Future<bool> requestPermissions() async {
    final android = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    try {
      await android?.requestExactAlarmsPermission();
    } catch (_) {}
    return granted ?? false;
  }

  // Instant notification for testing permissions & channels
  Future<void> showInstantNotification({
    required String title,
    required String body,
    String? payload,
    String type = 'reminder',
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      studyChannelId,
      studyChannelName,
      channelDescription: 'Alerts and reminders for GATE study tasks',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    final id = DateTime.now().millisecondsSinceEpoch % 100000;
    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      platformDetails,
      payload: payload ?? 'route:reminders',
    );

    try {
      await DatabaseService.instance.addInAppNotification(
        title: title,
        message: body,
        type: type,
      );
    } catch (_) {}
  }

  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? repeatDays,
    String alertType = 'notification',
    List<String>? checkpoints,
  }) async {
    // Clear any previous notification triggers for this reminder ID
    await cancelReminder(id);

    final isAlarm = alertType.toLowerCase() == 'alarm';
    final targetChannel = isAlarm ? alarmChannelId : studyChannelId;
    final targetChannelName = isAlarm ? alarmChannelName : studyChannelName;

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      targetChannel,
      targetChannelName,
      channelDescription: isAlarm
          ? 'Full-screen study alarm ringing overlay'
          : 'Alerts and reminders for GATE study tasks',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: isAlarm,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      actions: const [
        AndroidNotificationAction('snooze_5', 'Snooze 5m'),
        AndroidNotificationAction('snooze_10', 'Snooze 10m'),
        AndroidNotificationAction('dismiss', 'Dismiss'),
      ],
    );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    final now = tz.TZDateTime.now(tz.local);

    final parsedDays = (repeatDays != null && repeatDays.trim().isNotEmpty)
        ? repeatDays
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .where((d) => d >= 0 && d <= 6)
            .toSet()
        : <int>{};

    final notifPayload = isAlarm ? 'route:alarm:$id:$title' : 'route:reminders';

    if (parsedDays.isEmpty) {
      // One-time reminder
      var tzScheduled = tz.TZDateTime.from(scheduledDate, tz.local);
      if (tzScheduled.isBefore(now)) {
        if (now.difference(tzScheduled).inMinutes <= 5) {
          tzScheduled = now.add(const Duration(seconds: 5));
        } else {
          return; // Skip past dates
        }
      }

      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          tzScheduled,
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: notifPayload,
        );
      } catch (_) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          tzScheduled,
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: notifPayload,
        );
      }
    } else if (parsedDays.length == 7) {
      // Daily recurring routine (all 7 days selected)
      var nextTime = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        scheduledDate.hour,
        scheduledDate.minute,
      );
      if (nextTime.isBefore(now)) {
        nextTime = nextTime.add(const Duration(days: 1));
      }

      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          nextTime,
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: notifPayload,
        );
      } catch (_) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          nextTime,
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: notifPayload,
        );
      }
    } else {
      // Specific days of week routine (e.g. Mon, Wed, Fri)
      for (final dayIndex in parsedDays) {
        final targetWeekday = (dayIndex == 0) ? 7 : dayIndex;
        var targetDate = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          scheduledDate.hour,
          scheduledDate.minute,
        );
        while (targetDate.weekday != targetWeekday || targetDate.isBefore(now)) {
          targetDate = targetDate.add(const Duration(days: 1));
        }

        final notifId = id * 10 + dayIndex;
        try {
          await flutterLocalNotificationsPlugin.zonedSchedule(
            notifId,
            title,
            body,
            targetDate,
            platformDetails,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
            payload: notifPayload,
          );
        } catch (_) {
          await flutterLocalNotificationsPlugin.zonedSchedule(
            notifId,
            title,
            body,
            targetDate,
            platformDetails,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
            payload: notifPayload,
          );
        }
      }
    }

    // Schedule any extra checkpoints for this reminder
    if (checkpoints != null && checkpoints.isNotEmpty) {
      for (int i = 0; i < checkpoints.length; i++) {
        final cpStr = checkpoints[i];
        final cpDt = DateTime.tryParse(cpStr);
        if (cpDt == null) continue;
        var tzCp = tz.TZDateTime.from(cpDt, tz.local);
        if (tzCp.isBefore(now)) continue;

        final cpId = id * 100 + (i + 1);
        try {
          await flutterLocalNotificationsPlugin.zonedSchedule(
            cpId,
            '$title (Checkpoint ${i + 1})',
            body,
            tzCp,
            platformDetails,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: notifPayload,
          );
        } catch (_) {}
      }
    }

    // Log scheduled reminder
    try {
      await DatabaseService.instance.addInAppNotification(
        title: 'Reminder: $title',
        message: body,
        type: isAlarm ? 'alarm' : 'reminder',
      );
    } catch (_) {}
  }

  // Google Keep Note Reminder Scheduling
  Future<void> scheduleKeepNoteReminder({
    required String noteId,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? repeat,
  }) async {
    final int notifId = (noteId.hashCode.abs() % 50000) + 20000;
    await cancelKeepNoteReminder(noteId);

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      studyChannelId,
      studyChannelName,
      channelDescription: 'Google Keep Note Reminders',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      actions: [
        AndroidNotificationAction('snooze_10', 'Snooze 10m'),
        AndroidNotificationAction('dismiss', 'Dismiss'),
      ],
    );

    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
    final now = tz.TZDateTime.now(tz.local);
    var tzScheduled = tz.TZDateTime.from(scheduledDate, tz.local);

    if (tzScheduled.isBefore(now)) {
      if (now.difference(tzScheduled).inMinutes <= 5) {
        tzScheduled = now.add(const Duration(seconds: 5));
      } else {
        return;
      }
    }

    final payload = 'route:keep_note:$noteId';
    final isDaily = repeat?.toUpperCase() == 'DAILY';

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        notifId,
        title.isNotEmpty ? title : 'Note Reminder',
        body.isNotEmpty ? body : 'Keep Note Reminder',
        tzScheduled,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: isDaily ? DateTimeComponents.time : null,
        payload: payload,
      );
    } catch (_) {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        notifId,
        title.isNotEmpty ? title : 'Note Reminder',
        body.isNotEmpty ? body : 'Keep Note Reminder',
        tzScheduled,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: isDaily ? DateTimeComponents.time : null,
        payload: payload,
      );
    }

    try {
      await DatabaseService.instance.addInAppNotification(
        title: 'Keep Reminder: ${title.isNotEmpty ? title : "Note"}',
        message: body.isNotEmpty ? body : 'Note reminder scheduled',
        type: 'keep_note',
      );
    } catch (_) {}
  }

  Future<void> cancelKeepNoteReminder(String noteId) async {
    final int notifId = (noteId.hashCode.abs() % 50000) + 20000;
    await flutterLocalNotificationsPlugin.cancel(notifId);
  }

  Future<void> scheduleDailySessionAlerts({
    bool morning = true,
    bool afternoon = true,
    bool evening = true,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      dailyChannelId,
      dailyChannelName,
      channelDescription: 'Scheduled reminders for Morning, Afternoon, and Evening blocks',
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );
    const platformDetails = NotificationDetails(android: androidDetails);

    final now = tz.TZDateTime.now(tz.local);
    const payload = 'route:today';

    // 1. Morning Block at 5:00 AM (ID: 9001)
    if (morning) {
      var morningTime = tz.TZDateTime(tz.local, now.year, now.month, now.day, 5, 0);
      if (morningTime.isBefore(now)) {
        morningTime = morningTime.add(const Duration(days: 1));
      }
      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          9001,
          'Morning Study Brief (05:00 AM)',
          'Rise and conquer: Review your target lectures and recall items for today!',
          morningTime,
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: payload,
        );
      } catch (_) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          9001,
          'Morning Study Brief (05:00 AM)',
          'Rise and conquer: Review your target lectures and recall items for today!',
          morningTime,
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: payload,
        );
      }
    } else {
      await cancelNotification(9001);
    }

    // 2. Afternoon Session at 1:30 PM (ID: 9002)
    if (afternoon) {
      var afternoonTime = tz.TZDateTime(tz.local, now.year, now.month, now.day, 13, 30);
      if (afternoonTime.isBefore(now)) {
        afternoonTime = afternoonTime.add(const Duration(days: 1));
      }
      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          9002,
          'Afternoon Session (01:30 PM)',
          'Time for Afternoon & Aptitude Block. Stay focused on your GATE target!',
          afternoonTime,
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: payload,
        );
      } catch (_) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          9002,
          'Afternoon Session (01:30 PM)',
          'Time for Afternoon & Aptitude Block. Stay focused on your GATE target!',
          afternoonTime,
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: payload,
        );
      }
    } else {
      await cancelNotification(9002);
    }

    // 3. Evening Review at 7:00 PM (ID: 9003)
    if (evening) {
      var eveningTime = tz.TZDateTime(tz.local, now.year, now.month, now.day, 19, 0);
      if (eveningTime.isBefore(now)) {
        eveningTime = eveningTime.add(const Duration(days: 1));
      }
      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          9003,
          'Evening Review & Recall (07:00 PM)',
          'Wrap up today lectures, log tricky quiz mistakes, and clear Day 1/4/7 recall checkpoints.',
          eveningTime,
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: payload,
        );
      } catch (_) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          9003,
          'Evening Review & Recall (07:00 PM)',
          'Wrap up today lectures, log tricky quiz mistakes, and clear Day 1/4/7 recall checkpoints.',
          eveningTime,
          platformDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: payload,
        );
      }
    } else {
      await cancelNotification(9003);
    }

    if (morning || afternoon || evening) {
      try {
        await DatabaseService.instance.addInAppNotification(
          title: 'Daily Study Routine Active',
          message: 'Daily study checkpoints configured (Morning brief, recall shield, evening review).',
          type: 'routine',
        );
      } catch (_) {}
    }
  }

  Future<void> cancelReminder(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
    for (int d = 0; d < 7; d++) {
      try {
        await flutterLocalNotificationsPlugin.cancel(id * 10 + d);
      } catch (_) {}
    }
    for (int i = 0; i < 20; i++) {
      try {
        await flutterLocalNotificationsPlugin.cancel(id * 100 + i);
      } catch (_) {}
    }
  }

  Future<void> cancelNotification(int id) async {
    await cancelReminder(id);
  }

  Future<void> cancelAll() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }
}
