import 'dart:async';
import 'dart:convert';
import 'notification_route.dart';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:tasks/data/database_service.dart';

@pragma('vm:entry-point')
void notificationActionBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init(background: true);
  await NotificationService.instance.handleResponse(response);
}

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String studyChannelId = 'nyro_study_channel';
  static const String studyChannelName = 'NYRO Study Notifications';
  static const String dailyChannelId = 'nyro_daily_channel';
  static const String dailyChannelName = 'Daily Study Routine';
  static const String alarmChannelId = 'nyro_alarm_channel_v2';
  static const String alarmChannelName = 'Full-Screen Study Alarms';

  final StreamController<String> _payloadController = StreamController<String>.broadcast();
  Stream<String> get onNotificationPayloadTapped => _payloadController.stream;

  String? _pendingLaunchPayload;
  String? get pendingLaunchPayload => _pendingLaunchPayload;
  void clearPendingLaunchPayload() => _pendingLaunchPayload = null;

  Future<void> init({bool background = false}) async {
    await _configureLocalTimeZone();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: handleResponse,
      onDidReceiveBackgroundNotificationResponse: notificationActionBackground,
    );

    if (background) return;

    try {
      final launchDetails = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
      if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
        final response = launchDetails.notificationResponse;
        if (response != null && (response.actionId?.isNotEmpty ?? false)) {
          await handleResponse(response);
        } else {
          _pendingLaunchPayload = response?.payload;
        }
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
          audioAttributesUsage: AudioAttributesUsage.alarm,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
    }

    try { await syncDailyRoutineFromSettings(); } catch (_) {}
    try { await migrateNativeAlarms(); } catch (_) {}
  }

  Future<void> syncDailyRoutineFromSettings() async {
    final settings = await DatabaseService.instance.getAlertSettings();
    await scheduleDailySessionAlerts(
      morning: settings['morning_brief'] == 1,
      afternoon: settings['afternoon_session'] == 1,
      evening: settings['evening_review'] == 1,
    );
  }

  Future<void> _configureLocalTimeZone() async {
    tz_data.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone));
  }

  Future<void> handleResponse(NotificationResponse response) async {
    final action = response.actionId;
    if (action == 'snooze_5' || action == 'snooze_10') {
      await snooze(payload: response.payload ?? 'route:reminders',
        minutes: action == 'snooze_5' ? 5 : 10);
    } else if (action != 'dismiss') {
      final payload = response.payload;
      if (payload != null && payload.isNotEmpty) _payloadController.add(payload);
    }
    // Action buttons cancel only the displayed notification through Android.
    // They must not cancel the next occurrence of a recurring reminder.
  }

  Future<void> snooze({required String payload, required int minutes}) async {
    final route = NotificationRoute.parse(payload);
    final isAlarm = route != null;
    var title = route?.title ?? 'Snoozed reminder';
    if (route == null && payload.startsWith('route:reminders:')) {
      final id = int.tryParse(payload.substring('route:reminders:'.length));
      final reminders = await DatabaseService.instance.getCustomReminders();
      final matches = reminders.where((row) => row['id'] == id);
      if (matches.isNotEmpty) title = matches.first['text']?.toString() ?? title;
    } else if (payload.startsWith('route:keep_note:')) {
      final note = await DatabaseService.instance.getKeepNoteById(payload.substring('route:keep_note:'.length));
      if (note != null) title = note.isLocked ? 'Protected note reminder' : note.title;
    }
    final details = NotificationDetails(android: AndroidNotificationDetails(
      isAlarm ? alarmChannelId : studyChannelId,
      isAlarm ? alarmChannelName : studyChannelName,
      importance: Importance.max,
      priority: Priority.high,
      category: isAlarm ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.reminder,
      visibility: payload.startsWith('route:keep_note:') ? NotificationVisibility.private : NotificationVisibility.public,
      styleInformation: BigTextStyleInformation('Snoozed for $minutes minutes',
        contentTitle: '<b>${const HtmlEscape().convert(title)}</b>', htmlFormatContentTitle: true),
      fullScreenIntent: isAlarm,
      autoCancel: !isAlarm,
      timeoutAfter: isAlarm ? 120000 : null,
      additionalFlags: isAlarm ? Int32List.fromList([4]) : null,
      audioAttributesUsage: isAlarm ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
      actions: const [
        AndroidNotificationAction('snooze_5', 'Snooze 5m'),
        AndroidNotificationAction('snooze_10', 'Snooze 10m'),
        AndroidNotificationAction('dismiss', 'Dismiss'),
      ],
    ));
    final id = 0x60000000 | (DateTime.now().microsecondsSinceEpoch & 0x0fffffff);
    final snoozePayload = route != null ? NotificationRoute(id, route.groupId, title).encode() : payload;
    final when = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(id, title, 'Snoozed for $minutes minutes',
        when, details, payload: snoozePayload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime);
    } catch (_) {
      await flutterLocalNotificationsPlugin.zonedSchedule(id, title, 'Snoozed for $minutes minutes',
        when, details, payload: snoozePayload,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime);
    }
  }

  Future<void> dismissDisplayed(int id) async {
    await _native.invokeMethod('stopStudyAlarm', {'id': id});
    await const MethodChannel('io.github.thelazyindian.tasks/native')
        .invokeMethod('dismissDeliveredNotification', {'id': id});
  }

  // Dedicated namespaces avoid collisions with task IDs, routines and Keep.
  static int _childId(int id, int index) => 0x20000000 | ((id & 0x1fffff) << 6) | index;

  Future<void> _requestNotificationsIfNeeded() async {
    final android = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (await android?.areNotificationsEnabled() == false) {
      await android?.requestNotificationsPermission();
    }
  }

  Future<bool> requestPermissions() async {
    final android = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? false;
  }

  // Instant notification for testing permissions & channels
  Future<void> showInstantNotification({
    required String title,
    required String body,
    String? payload,
    String type = 'reminder',
  }) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      studyChannelId,
      studyChannelName,
      channelDescription: 'Alerts and reminders for GATE study tasks',
      importance: Importance.max,
      priority: Priority.high,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(body,
        contentTitle: '<b>${const HtmlEscape().convert(title)}</b>', htmlFormatContentTitle: true),
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    final NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

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
    if ((title == 'Study Reminder' || title == 'NYRO Study Task') && body.trim().isNotEmpty) title = body.trim();
    await _requestNotificationsIfNeeded();
    final isAlarm = alertType.toLowerCase() == 'alarm';
    if (isAlarm) await prepareAlarmAccess();
    // Cancel the old schedule only after access has been verified.
    await cancelReminder(id);
    if (isAlarm) {
      await _scheduleNativeAlarm(id: id, title: title, body: body,
        scheduledDate: scheduledDate, repeatDays: repeatDays, checkpoints: checkpoints);
      return;
    }

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
      autoCancel: !isAlarm,
      timeoutAfter: isAlarm ? 120000 : null,
      additionalFlags: isAlarm ? Int32List.fromList([4]) : null,
      audioAttributesUsage: isAlarm ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(body == title ? 'Your scheduled study reminder is due.' : body,
        contentTitle: '<b>${const HtmlEscape().convert(title)}</b>', htmlFormatContentTitle: true,
        summaryText: 'Study reminder'),
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

    final notifPayload = isAlarm ? NotificationRoute(id, id, title).encode() : 'route:reminders:$id';

    if (parsedDays.isEmpty) {
      // One-time reminder
      var tzScheduled = tz.TZDateTime.from(scheduledDate, tz.local);
      if (tzScheduled.isBefore(now)) {
        if (now.difference(tzScheduled).inMinutes <= 5) {
          tzScheduled = now.add(const Duration(seconds: 5));
        }
      }

      if (tzScheduled.isAfter(now)) {
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

        final notifId = _childId(id, dayIndex);
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
            payload: isAlarm ? NotificationRoute(notifId, id, title).encode() : notifPayload,
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
            payload: isAlarm ? NotificationRoute(notifId, id, title).encode() : notifPayload,
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

        final cpId = _childId(id, i + 8);
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
            payload: isAlarm ? NotificationRoute(cpId, id, title).encode() : notifPayload,
          );
        } catch (_) {
          await flutterLocalNotificationsPlugin.zonedSchedule(
            cpId, '$title (Checkpoint ${i + 1})', body, tzCp, platformDetails,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
            payload: isAlarm ? NotificationRoute(cpId, id, title).encode() : notifPayload,
          );
        }
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
    bool requestPermission = true,
  }) async {
    if (requestPermission) await _requestNotificationsIfNeeded();
    final int notifId = (noteId.hashCode.abs() % 50000) + 20000;
    await cancelKeepNoteReminder(noteId);

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      studyChannelId,
      studyChannelName,
      channelDescription: 'Google Keep Note Reminders',
      importance: Importance.max,
      priority: Priority.high,
      visibility: NotificationVisibility.private,
      styleInformation: BigTextStyleInformation(body,
        contentTitle: '<b>${const HtmlEscape().convert(title)}</b>', htmlFormatContentTitle: true),
      showWhen: true,
      enableVibration: true,
      playSound: true,
      actions: [
        AndroidNotificationAction('snooze_10', 'Snooze 10m'),
        AndroidNotificationAction('dismiss', 'Dismiss'),
      ],
    );

    final NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
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

  Future<void> refreshKeepNotePrivacy(String noteId) async {
    final note = await DatabaseService.instance.getKeepNoteById(noteId);
    if (note == null) return;
    if (note.isLocked) {
      final db = await DatabaseService.instance.database;
      await db.update('inapp_notifications', {
        'title': 'Protected note reminder', 'message': 'Unlock Keep to view this note.',
      }, where: 'type = ? AND title = ?',
        whereArgs: ['keep_note', 'Keep Reminder: ${note.title.isNotEmpty ? note.title : "Note"}']);
      // Older releases did not retain a note ID in save-history records.
      await db.update('inapp_notifications', {'message': 'Open Keep to view your notes.'},
        where: 'title IN (?, ?)', whereArgs: ['Note Created', 'Note Saved']);
    }
    // Remove the previously scheduled plaintext notification before replacing it.
    await cancelKeepNoteReminder(noteId);
    if (note.reminderAt == null) return;
    await scheduleKeepNoteReminder(noteId: note.id,
      title: note.isLocked ? 'Protected note reminder' : note.title,
      body: note.isLocked ? 'Unlock Keep to view this note.' : note.content,
      scheduledDate: DateTime.fromMillisecondsSinceEpoch(note.reminderAt!), repeat: note.reminderRepeat,
      requestPermission: false);
  }

  Future<void> cancelKeepNoteReminder(String noteId) async {
    final int notifId = (noteId.hashCode.abs() % 50000) + 20000;
    await flutterLocalNotificationsPlugin.cancel(notifId);
    final pending = await flutterLocalNotificationsPlugin.pendingNotificationRequests();
    for (final notification in pending) {
      if (notification.payload == 'route:keep_note:$noteId') {
        await flutterLocalNotificationsPlugin.cancel(notification.id);
      }
    }
  }

  Future<void> scheduleDailySessionAlerts({
    bool morning = true,
    bool afternoon = true,
    bool evening = true,
  }) async {
    final settings = await DatabaseService.instance.getAlertSettings();
    final morningClock = (settings['morning_brief_time']?.toString() ?? '05:00').split(':');
    final shieldClock = (settings['shield_time']?.toString() ?? '21:30').split(':');
    final now = tz.TZDateTime.now(tz.local);
    const details = NotificationDetails(android: AndroidNotificationDetails(
      dailyChannelId, dailyChannelName,
      importance: Importance.high, priority: Priority.high,
      visibility: NotificationVisibility.private,
    ));
    Future<void> schedule(int id, bool enabled, int hour, int minute, String title, String body) async {
      if (!enabled) {
        await flutterLocalNotificationsPlugin.cancel(id);
        return;
      }
      var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
      if (!next.isAfter(now)) next = tz.TZDateTime(tz.local, now.year, now.month, now.day + 1, hour, minute);
      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(id, title, body, next, details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time, payload: 'route:today');
      } catch (_) {
        await flutterLocalNotificationsPlugin.zonedSchedule(id, title, body, next, details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time, payload: 'route:today');
      }
    }
    await schedule(9001, morning, int.tryParse(morningClock.first) ?? 5,
      morningClock.length > 1 ? int.tryParse(morningClock[1]) ?? 0 : 0,
      'Morning Study Brief', 'Review your lecture targets and due recalls for today.');
    await schedule(9002, afternoon, 13, 30,
      'Afternoon Session', 'Continue your study session and make time for aptitude practice.');
    await schedule(9003, evening, 19, 0,
      'Evening Review', 'Review today, log mistakes and clear due recall checkpoints.');
    await schedule(9004, settings['backlog_shield'] == 1, int.tryParse(shieldClock.first) ?? 21,
      shieldClock.length > 1 ? int.tryParse(shieldClock[1]) ?? 30 : 30,
      'Evening Backlog Shield', 'Check unfinished study tasks and plan your next session.');
  }

  static const _native = MethodChannel('io.github.thelazyindian.tasks/native');

  Future<void> testRingingAlarm(String title) async {
    await _requestNotificationsIfNeeded();
    await prepareAlarmAccess();
    final id = 0x70000000 | (DateTime.now().microsecondsSinceEpoch & 0x00ffffff);
    await _native.invokeMethod('scheduleStudyAlarms', {'alarms': [{
      'id': id, 'group': id, 'at': DateTime.now().add(const Duration(seconds: 2)).millisecondsSinceEpoch,
      'title': title, 'body': 'Test alarm', 'intervalDays': 0,
    }]});
  }

  Future<void> prepareAlarmAccess() async {
    final android = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    var access = await _native.invokeMapMethod<String, bool>('getNotificationAccess') ?? {};
    if (access['notifications'] != true) throw StateError('Allow notifications before saving a ringing alarm.');
    if (access['exact'] != true) {
      await android?.requestExactAlarmsPermission();
      access = await _native.invokeMapMethod<String, bool>('getNotificationAccess') ?? {};
      if (access['exact'] != true) throw StateError('Enable precise timing in Settings before saving a ringing alarm.');
    }
    if (access['fullScreen'] != true) {
      await _native.invokeMethod('openFullScreenIntentSettings');
      throw StateError('Enable full-screen alarm access in Android settings, then return and save your alarm.');
    }
  }

  Future<void> _scheduleNativeAlarm({required int id, required String title, required String body,
    required DateTime scheduledDate, String? repeatDays, List<String>? checkpoints}) async {
    final now = DateTime.now();
    final days = (repeatDays ?? '').split(',').map((day) => int.tryParse(day.trim()))
        .whereType<int>().where((day) => day >= 0 && day <= 6).toSet();
    final alarms = <Map<String, dynamic>>[];
    void add(DateTime time, int index, int intervalDays, String label) {
      if (!time.isAfter(now)) return;
      alarms.add({'id': _childId(id, index), 'group': id, 'at': time.millisecondsSinceEpoch,
        'title': label, 'body': body, 'intervalDays': intervalDays});
    }
    if (days.isEmpty) {
      add(scheduledDate, 0, 0, title);
    } else if (days.length == 7) {
      var next = DateTime(now.year, now.month, now.day, scheduledDate.hour, scheduledDate.minute);
      if (!next.isAfter(now)) next = DateTime(now.year, now.month, now.day + 1, scheduledDate.hour, scheduledDate.minute);
      add(next, 0, 1, title);
    } else {
      for (final day in days) {
        var next = DateTime(now.year, now.month, now.day, scheduledDate.hour, scheduledDate.minute);
        while (next.weekday % 7 != day || !next.isAfter(now)) {
          next = DateTime(next.year, next.month, next.day + 1, scheduledDate.hour, scheduledDate.minute);
        }
        add(next, day, 7, title);
      }
    }
    for (var i = 0; i < (checkpoints?.length ?? 0); i++) {
      final time = DateTime.tryParse(checkpoints![i]);
      if (time != null) add(time, i + 8, 0, '$title (Checkpoint ${i + 1})');
    }
    await _native.invokeMethod('scheduleStudyAlarms', {'alarms': alarms});
    await DatabaseService.instance.addInAppNotification(title: 'Alarm scheduled: $title', message: body, type: 'alarm');
  }

  Future<void> migrateNativeAlarms() async {
    final db = DatabaseService.instance;
    if (await _native.invokeMethod<bool>('hasStudyAlarmMigration') == true) return;
    final access = await _native.invokeMapMethod<String, bool>('getNotificationAccess') ?? {};
    if (access['exact'] != true || access['fullScreen'] != true) return;
    final reminders = await db.getCustomReminders();
    for (final reminder in reminders) {
      if (reminder['alert_type'] != 'alarm' || reminder['status'] == 'COMPLETED') continue;
      final time = DateTime.tryParse(reminder['remind_at']?.toString() ?? '');
      final id = reminder['id'] as int?;
      if (time == null || id == null) continue;
      List<String> checkpoints = [];
      try { checkpoints = (jsonDecode(reminder['checkpoints_json']?.toString() ?? '[]') as List).map((v) => v.toString()).toList(); } catch (_) {}
      await cancelReminder(id);
      await _scheduleNativeAlarm(id: id, title: reminder['text']?.toString() ?? 'Study alarm', body: '',
        scheduledDate: time, repeatDays: reminder['repeat_days']?.toString(), checkpoints: checkpoints);
    }
    await _native.invokeMethod('markStudyAlarmMigration');
  }

  Future<void> cancelReminder(int id) async {
    await _native.invokeMethod('cancelStudyAlarmGroup', {'group': id});
    await flutterLocalNotificationsPlugin.cancel(id);
    final pending = await flutterLocalNotificationsPlugin.pendingNotificationRequests();
    final childIds = <int>{for (var i = 0; i < 64; i++) _childId(id, i)};
    final legacyIds = <int>{
      for (var d = 0; d < 7; d++) id * 10 + d,
      for (var i = 1; i <= 20; i++) id * 100 + i,
    };
    for (final request in pending) {
      final payload = request.payload ?? '';
      final alarmRoute = NotificationRoute.parse(payload);
      if (alarmRoute?.groupId == id || (childIds.contains(request.id) && (payload.startsWith('route:alarm:') || payload.startsWith('route:reminders:'))) || payload == 'route:reminders:$id' || payload.startsWith('route:alarm:$id:') ||
          (legacyIds.contains(request.id) && payload == 'route:reminders')) {
        await flutterLocalNotificationsPlugin.cancel(request.id);
      }
    }
  }

  Future<void> cancelNotification(int id) async {
    await cancelReminder(id);
  }

  Future<void> cancelAll() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }
}
