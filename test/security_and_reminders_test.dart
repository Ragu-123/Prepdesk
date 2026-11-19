import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tasks/data/database_service.dart';
import 'package:tasks/services/vault_service.dart';
import 'package:tasks/services/notification_service.dart';
import 'package:tasks/services/desktop/desktop_notes_handler.dart';
import 'package:tasks/services/desktop/desktop_auth_handler.dart';
import 'package:tasks/data/keep_note_model.dart';
import 'package:tasks/services/desktop_log_server_service.dart';
import 'package:tasks/pages/keep/note_reader_page.dart';
import 'package:tasks/pages/tabs/today_tab.dart';
import 'package:tasks/pages/tabs/widgets/today_progress_summary.dart';
import 'package:tasks/widgets/protected_content.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/services/appearance_service.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:tasks/pages/settings/settings_page.dart';
import 'package:tasks/pages/settings/appearance_settings_page.dart';
import 'package:tasks/pages/alerts/alerts_page.dart';
import 'package:tasks/pages/home/home_page.dart';
import 'package:tasks/widgets/app_appearance_lifecycle.dart';

class _Paths extends PathProviderPlatform {
  final String path;
  _Paths(this.path);
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

class _RealHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => super.createHttpClient(context);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  final dbService = DatabaseService.instance;
  setUpAll(() async {
    final text = FontLoader('NotoSans')
      ..addFont(rootBundle.load('assets/google_fonts/NotoSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/google_fonts/NotoSans-Bold.ttf'));
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await text.load();
    await icons.load();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('nyro-regression-');
    PathProviderPlatform.instance = _Paths(temp.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
    await dbService.database;
  });
  setUp(() async {
    final db = await dbService.database;
    await db.delete('custom_reminders');
    await db.delete('keep_notes');
    await db.delete('mistake_records');
    await db.delete('lectures');
    await db.delete('revisit_items');
    await db.delete('quiz_items');
    await db.delete('app_config', where: "key LIKE 'keep_vault_%'");
  });
  tearDownAll(() async {
    await (await dbService.database).close();
    await temp.delete(recursive: true);
  });
  test('A reminder with a future checkpoint remains active after its first time', () async {
    final db = await dbService.database;
    final now = DateTime.now();
    for (final entry in [
      {'id': 1, 'checkpoints_json': jsonEncode([now.add(const Duration(days: 1)).toIso8601String()]), 'repeat_days': ''},
      {'id': 2, 'checkpoints_json': '[]', 'repeat_days': ''},
      {'id': 3, 'checkpoints_json': '[]', 'repeat_days': '1,3'},
    ]) {
      await db.insert('custom_reminders', {
        'text': 'Study', 'remind_at': now.subtract(const Duration(days: 1)).toIso8601String(),
        'status': 'PENDING', ...entry,
      });
    }
    expect(await dbService.autoCompleteExpiredReminders(), 1);
    final rows = await db.query('custom_reminders', orderBy: 'id');
    expect(rows[0]['status'], 'PENDING');
    expect(rows[1]['status'], 'COMPLETED');
    expect(rows[2]['status'], 'PENDING');
  });
  test('Checking off one checkpoint advances the schedule instead of completing the group', () async {
    final db = await dbService.database;
    final now = DateTime.now();
    await db.insert('custom_reminders', {'id': 5, 'text': 'Revision', 'status': 'PENDING',
      'remind_at': now.subtract(const Duration(hours: 1)).toIso8601String(), 'repeat_days': '',
      'checkpoints_json': jsonEncode([now.add(const Duration(days: 1)).toIso8601String(), now.add(const Duration(days: 2)).toIso8601String()])});
    expect(await dbService.completeReminderOccurrence(5), isTrue);
    var row = (await db.query('custom_reminders', where: 'id = 5')).single;
    expect(row['status'], 'PENDING');
    expect(jsonDecode(row['checkpoints_json'] as String), hasLength(1));
    expect(await dbService.completeReminderOccurrence(5), isTrue);
    expect(await dbService.completeReminderOccurrence(5), isFalse);
    row = (await db.query('custom_reminders', where: 'id = 5')).single;
    expect(row['status'], 'COMPLETED');
  });
  test('Alarm mode delegates to Android alarm-clock scheduling, including future checkpoints', () async {
    Map<dynamic, dynamic>? scheduled;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('io.github.thelazyindian.tasks/native'), (call) async {
        if (call.method == 'getNotificationAccess') return {'notifications': true, 'exact': true, 'fullScreen': true};
        if (call.method == 'scheduleStudyAlarms') scheduled = call.arguments as Map;
        return null;
      });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'), (call) async {
        if (call.method == 'areNotificationsEnabled') return true;
        if (call.method == 'pendingNotificationRequests') return [];
        return null;
      });
    final now = DateTime.now();
    await NotificationService.instance.scheduleReminder(id: 77, title: 'Study Reminder', body: 'Review matrices',
      alertType: 'alarm', scheduledDate: now.subtract(const Duration(hours: 1)),
      checkpoints: [now.add(const Duration(hours: 1)).toIso8601String()]);
    expect(scheduled, isNotNull);
    final alarms = scheduled!['alarms'] as List;
    expect(alarms, hasLength(1));
    expect((alarms.single as Map)['title'], contains('Review matrices'));
    expect((alarms.single as Map)['group'], 77);
    expect((alarms.single as Map)['intervalDays'], 0);
  });
  test('Cloud export strips vault credentials and protected notes', () async {
    final db = await dbService.database;
    await db.insert('keep_notes', {'id': 'private', 'title': 'Secret', 'content': 'Private', 'is_locked': 1, 'created_at': 1, 'updated_at': 1});
    await db.insert('keep_notes', {'id': 'public', 'title': 'Revision', 'created_at': 1, 'updated_at': 1});
    await dbService.setKeepVaultPinHash('old-hash');
    final path = await dbService.exportSanitizedDatabaseForCloudUpload();
    final exported = await openDatabase(path);
    expect((await exported.query('keep_notes')).map((row) => row['id']), ['public']);
    expect(await exported.query('app_config', where: "key LIKE 'keep_vault_%'"), isEmpty);
    await exported.close();
    expect(await db.query('keep_notes'), hasLength(2));
  });
  test('Desktop cannot read, overwrite or delete protected notes', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final db = await dbService.database;
      await db.insert('keep_notes', {'id': 'private', 'title': 'Hidden title', 'content': 'Secret text', 'is_locked': 1, 'created_at': 1, 'updated_at': 1});
      final handler = DesktopNotesHandler(authHandler: DesktopAuthHandler());
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) {
        if (request.method == 'GET') handler.handleGetNotes(request);
        else if (request.method == 'POST') handler.handleCreateNote(request);
        else if (request.method == 'PATCH') handler.handleUpdateNote(request, 'private');
        else handler.handleDeleteNote(request, 'private');
      });
      final client = HttpClient();
      Future<HttpClientResponse> send(String method, [Map<String, dynamic>? data]) async {
        final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}/api/notes'));
        request.headers.contentType = ContentType.json;
        if (data != null) request.write(jsonEncode(data));
        return request.close();
      }
      try {
        final list = await send('GET');
        final body = await utf8.decodeStream(list);
        expect(body, isNot(contains('Secret text')));
        expect(body, isNot(contains('Hidden title')));
        for (final method in ['POST', 'PATCH', 'DELETE']) {
          final response = await send(method, {'id': 'private', 'title': 'Replacement'});
          expect(response.statusCode, method == 'POST' ? HttpStatus.conflict : HttpStatus.forbidden);
          await response.drain<void>();
        }
        expect((await dbService.getKeepNoteById('private'))!.content, 'Secret text');
        final created = await send('POST', {'id': 'public', 'title': 'Revision notes'});
        expect(created.statusCode, HttpStatus.created);
        await created.drain<void>();
      } finally {
        client.close(force: true);
        await server.close(force: true);
        await subscription.cancel();
      }
    }, _RealHttp());
  });
  testWidgets('Missing vault credentials never turn unlock into PIN setup', (tester) async {
    var unlocked = false;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => VaultService.instance.showAuthDialog(context,
        onAuthenticated: () => unlocked = true), child: const Text('Open private note')),
    ))));
    await tester.runAsync(() async {
      await tester.tap(find.text('Open private note'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(unlocked, isFalse);
    expect(find.text('Set Master Vault PIN'), findsNothing);
    expect(find.text('Vault credentials are unavailable. Protected notes remain locked.'), findsOneWidget);
  });

  test('Subject traps carry to Today, weekly and test-series quizzes with different titles', () async {
    await dbService.insertMistakeRecord(subject: 'Linear Algebra', topic: 'Rank',
      questionText: 'Find rank', keyTakeaway: 'Count pivots', severity: 'HIGH', quizTitle: 'Matrices 1');
    final quizzes = [
      {'id': 1, 'title': 'Next quiz', 'subject': 'linear algebra', 'quiz_type': 'TOPIC'},
      {'id': 2, 'title': 'Week 2', 'subject': 'Engineering Mathematics', 'module_name': 'Linear Algebra', 'quiz_type': 'WEEKLY'},
      {'id': 3, 'title': 'Test series 4', 'subject': 'All Subjects', 'syllabus_topics': 'Calculus; Linear Algebra', 'quiz_type': 'TEST_SERIES'},
      {'id': 4, 'title': 'Thermodynamics', 'subject': 'Mechanical Engineering'},
    ];
    expect(await dbService.getQuizTrapCounts(quizzes), {1: 1, 2: 1, 3: 1, 4: 0});
    expect((await dbService.getQuizTraps('Next quiz', subject: 'LINEAR ALGEBRA')).single['topic'], 'Rank');
  });

  test('Legacy protection flags fail closed and reject a stale desktop edit or delete', () async {
    final db = await dbService.database;
    for (final value in ['true', 'TRUE', 1, 2, 'locked']) {
      await db.insert('keep_notes', {'id': 'legacy-$value', 'title': 'Private', 'is_locked': value,
        'created_at': 1, 'updated_at': 1});
      final note = (await dbService.getKeepNoteById('legacy-$value'))!;
      expect(note.isLocked, isTrue);
      expect(await dbService.saveDesktopNote(note.copyWith(title: 'Overwrite', isLocked: false), creating: false), isFalse);
      expect(await dbService.deleteDesktopNote(note.id), isFalse);
    }
    final stale = KeepNote(id: 'race', title: 'Original');
    await dbService.saveKeepNote(stale);
    await dbService.toggleLockKeepNote('race', true);
    expect(await dbService.saveDesktopNote(stale.copyWith(title: 'Stale write'), creating: false), isFalse);
    expect((await dbService.getKeepNoteById('race'))!.title, 'Original');
  });

  test('Notification branding and the adaptive preference apply to both delivery and native alarms', () async {
    Map<dynamic, dynamic>? delivered;
    bool? nativeAdaptive;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('io.github.thelazyindian.tasks/native'), (call) async {
        if (call.method == 'setAdaptiveColors') nativeAdaptive = (call.arguments as Map)['enabled'] as bool;
        return null;
      });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'), (call) async {
        if (call.method == 'show') delivered = call.arguments as Map;
        return null;
      });
    final appearance = AppearanceService.instance;
    await appearance.selectAccent(2);
    await NotificationService.instance.showInstantNotification(title: 'Linear Algebra', body: 'Review rank');
    final android = delivered!['platformSpecifics'] as Map;
    expect(android['icon'], 'ic_nyro_notification');
    expect(android['largeIcon'], 'nyro_notification_logo');
    expect([android['colorRed'], android['colorGreen'], android['colorBlue']], [49, 93, 168]);
    expect(nativeAdaptive, isFalse);
    await appearance.setEnabled(true);
    await NotificationService.instance.showInstantNotification(title: 'Linear Algebra', body: 'Review rank');
    final adaptive = appearance.accent.toARGB32();
    final next = delivered!['platformSpecifics'] as Map;
    expect([next['colorRed'], next['colorGreen'], next['colorBlue']],
      [(adaptive >> 16) & 255, (adaptive >> 8) & 255, adaptive & 255]);
    expect(nativeAdaptive, isTrue);
    expect(await dbService.getConfig('adaptive_colors'), '1');
  });

  test('Refreshing a daily note whose original date has passed keeps its next occurrence', () async {
    tz_data.initializeTimeZones();
    Map<dynamic, dynamic>? scheduled;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'), (call) async {
        if (call.method == 'pendingNotificationRequests') return [];
        if (call.method == 'zonedSchedule') scheduled = call.arguments as Map;
        return null;
      });
    await NotificationService.instance.scheduleKeepNoteReminder(noteId: 'daily', title: 'Daily recall',
      body: 'Review formulas', scheduledDate: DateTime.now().subtract(const Duration(days: 10)),
      repeat: 'DAILY', requestPermission: false, recordHistory: false);
    expect(scheduled, isNotNull);
    expect(DateTime.parse(scheduled!['scheduledDateTime'] as String).isAfter(DateTime.now().toUtc().subtract(const Duration(seconds: 1))), isTrue);
    expect(scheduled!['matchDateTimeComponents'], isNotNull);
  });

  test('Keep searches tags with or without a hash and hides protected results', () async {
    await dbService.saveKeepNote(KeepNote(id: 'tag-public', title: 'Day one', tags: ['Eigenvalues']));
    await dbService.saveKeepNote(KeepNote(id: 'tag-private', title: 'Day two', tags: ['Eigenvalues']));
    await dbService.toggleLockKeepNote('tag-private', true);
    for (final query in ['EIGEN', '#eigenvalues']) {
      final notes = await dbService.getKeepNotes(searchQuery: query);
      expect(notes.map((note) => note.id), ['tag-public']);
    }
  });

  test('Daily ringing alarms use a recurring native schedule when access is granted', () async {
    tz_data.initializeTimeZones();
    await dbService.setConfig('routine_full_screen', '1');
    final scheduled = <Map>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('io.github.thelazyindian.tasks/native'), (call) async {
        if (call.method == 'getNotificationAccess') {
          return {'notifications': true, 'exact': true, 'fullScreen': true};
        }
        if (call.method == 'scheduleStudyAlarms') {
          scheduled.addAll((call.arguments['alarms'] as List).cast<Map>());
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'), (_) async => null,
    );
    await NotificationService.instance.scheduleDailySessionAlerts(afternoon: false, evening: false);
    final morning = scheduled.singleWhere((alarm) => alarm['group'] == -9001);
    expect(morning['intervalDays'], 1);
    expect(morning['id'], greaterThan(9001));
    expect(morning['at'], greaterThan(DateTime.now().millisecondsSinceEpoch));
  });

  test('New sessions rotate once and a selected fixed accent survives reopening', () async {
    final appearance = AppearanceService.instance;
    await dbService.setConfig('adaptive_colors', '1');
    await dbService.setConfig('appearance_accent_index', '2');
    await appearance.load(newSession: true);
    final first = appearance.accent;
    expect(first, isNot(googleBlue));
    for (var i = 0; i < 3; i++) {
      await appearance.load();
      expect(appearance.accent, first);
    }
    await appearance.load(newSession: true);
    expect(appearance.accent, isNot(first));
    await appearance.selectAccent(4);
    await appearance.load(newSession: true);
    expect(appearance.accent, AppearanceService.palette[4]);
    expect(await dbService.getConfig('appearance_accent_index'), '4');
    await appearance.setEnabled(true);
  });

  test('Protecting a note immediately revokes the paired desktop and emits a privacy event', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final reservation = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = reservation.port;
      await reservation.close(force: true);
      final studio = DesktopLogServerService.instance;
      await studio.startServer(port: port);
      final client = HttpClient();
      StreamSubscription<String>? stream;
      try {
        final token = studio.verifyPin(studio.pairingPin)!;
        Future<HttpClientResponse> get(String path) async {
          final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
          return request.close();
        }
        final response = await get('/api/session/events');
        expect(response.statusCode, 200);
        expect(response.headers.value('cache-control'), 'no-store');
        final ready = Completer<void>();
        final revoked = Completer<void>();
        stream = response.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
          if (line == 'event: ready' && !ready.isCompleted) ready.complete();
          if (line == 'event: privacy' && !revoked.isCompleted) revoked.complete();
        });
        await ready.future.timeout(const Duration(seconds: 5));
        await dbService.saveKeepNote(KeepNote(id: 'screen', title: 'Sensitive'));
        await dbService.toggleLockKeepNote('screen', true);
        await revoked.future.timeout(const Duration(seconds: 5));
        final denied = await get('/api/notes');
        expect(denied.statusCode, HttpStatus.unauthorized);
        await denied.drain<void>();
      } finally {
        await stream?.cancel();
        client.close(force: true);
        await studio.stopServer();
      }
    }, _RealHttp());
  });

  Future<void> settleDatabase(WidgetTester tester, Finder ready) async {
    for (var i = 0; i < 40 && ready.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(ready, findsWidgets);
  }

  testWidgets('Notes open as a full-screen reader and editing requires the pencil', (tester) async {
    await tester.runAsync(() => dbService.saveKeepNote(KeepNote(id: 'reader', title: 'Read me', content: 'A quiet reading surface')));
    await tester.pumpWidget(MaterialApp(theme: lightTheme, home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => NoteReaderPage.open(context, 'reader'), child: const Text('Open note'))))));
    await tester.tap(find.text('Open note'));
    await settleDatabase(tester, find.text('Read me'));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('A quiet reading surface'), findsOneWidget);
    await tester.tap(find.text('Edit note'));
    await settleDatabase(tester, find.byType(TextField));
    expect(find.byType(TextField), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Protecting an already-open reader masks its contents', (tester) async {
    await tester.runAsync(() => dbService.saveKeepNote(KeepNote(id: 'reader-lock', title: 'Sensitive content')));
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => NoteReaderPage.open(context, 'reader-lock'), child: const Text('Open note'))))));
    await tester.tap(find.text('Open note'));
    await settleDatabase(tester, find.text('Sensitive content'));
    await tester.runAsync(() => dbService.toggleLockKeepNote('reader-lock', true));
    await settleDatabase(tester, find.text('Unlock note'));
    expect(find.text('Sensitive content'), findsNothing);
    expect(find.text('Edit note'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Nested protected surfaces keep screenshot protection until the last surface closes', (tester) async {
    final flags = <bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('io.github.thelazyindian.tasks/native'), (call) async {
        if (call.method == 'setSecureWindow') flags.add((call.arguments as Map)['enabled'] as bool);
        return null;
      });
    Widget surface(bool nested) => MaterialApp(home: ProtectedContent(key: const ValueKey('outer'), protected: true,
      child: nested ? const ProtectedContent(protected: true, child: Text('Private')) : const Text('Private')));
    await tester.pumpWidget(surface(true));
    await tester.pumpWidget(surface(false));
    await tester.pump();
    expect(flags, isNotEmpty);
    expect(flags.every((flag) => flag), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(flags.last, isFalse);
  });

  testWidgets('Today shows database study progress, keeps sections pinned and exposes carried traps', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fonts = FontLoader('NotoSans')..addFont(rootBundle.load('assets/google_fonts/NotoSans-Regular.ttf'));
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await tester.runAsync(() async { await fonts.load(); await icons.load(); });
    final date = DateTime(2026, 11, 18);
    await tester.runAsync(() async {
    final db = await dbService.database;
    for (var i = 0; i < 12; i++) {
      await db.insert('lectures', {'date_str': '2026-11-18', 'topic': 'Linear Algebra',
        'details': 'Matrices ${i + 1}', 'duration_hours': 1.5, 'status': i == 0 ? 'COMPLETED' : 'PENDING'});
    }
    await db.insert('quiz_items', {'id': 501, 'date_str': '2026-11-18', 'title': 'Next matrices quiz',
      'subject': 'Linear Algebra', 'quiz_type': 'TOPIC', 'status': 'PENDING'});
    await dbService.insertMistakeRecord(subject: 'Linear Algebra', topic: 'Rank', questionText: 'Find rank',
      keyTakeaway: 'Count pivots', severity: 'HIGH', quizTitle: 'Previous quiz');
    });
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final preview = GlobalKey();
    await tester.pumpWidget(MaterialApp(theme: lightTheme, home: RepaintBoundary(key: preview,
      child: Scaffold(appBar: AppBar(title: const Text('Today')), body: TodayTab(currentDate: date,
        onDataChanged: () {}, scrollController: controller, onOpenScheduleForm: () {}, onOpenTimetable: () {})))));
    await settleDatabase(tester, find.byType(TodayProgressSummary));
    final summary = tester.widget<TodayProgressSummary>(find.byType(TodayProgressSummary));
    expect(summary.watchedHours, 1.5);
    expect(summary.lecturesDone, 1);
    expect(summary.lecturesTotal, 12);
    await tester.runAsync(() async {
      final image = await (preview.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/ui-previews/today-dashboard.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    controller.jumpTo(650);
    await tester.pumpAndSettle();
    final schedule = find.text('Schedule');
    expect(tester.getTopLeft(schedule).dy, lessThan(200));
    await tester.tap(find.text('Quizzes').last);
    await tester.pumpAndSettle();
    expect(find.text('1 trap to review'), findsOneWidget);
    expect(find.byTooltip('quiz options'), findsNothing);
    await tester.tap(find.text('Next matrices quiz'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('quiz options'), findsOneWidget);
    await tester.tap(find.byTooltip('quiz options'));
    await tester.pumpAndSettle();
    expect(find.text('Edit quiz'), findsOneWidget);
    expect(find.text('Delete quiz'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Today can pin its section tabs on an empty day and keep them pinned when switching sections', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(theme: lightTheme, home: Scaffold(body: TodayTab(
      currentDate: DateTime(2099, 3, 8), onDataChanged: () {}, scrollController: controller,
    ))));
    await settleDatabase(tester, find.byType(TodayProgressSummary));
    final scroll = find.byType(CustomScrollView);
    final schedule = find.text('Schedule');
    final before = tester.getTopLeft(schedule).dy;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final pinned = tester.getTopLeft(schedule).dy;
    expect(before - pinned, greaterThan(100));
    expect(pinned - tester.getTopLeft(scroll).dy, lessThan(60));
    await tester.tap(find.text('Revisits').last);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(schedule).dy, closeTo(pinned, 1));
    await tester.pumpWidget(const SizedBox());
  });

  test('Lecture edits shift unfinished recalls and deletion preserves completed recall history', () async {
    final db = await dbService.database;
    final id = await dbService.insertScheduledLecture(subject: 'Algebra', lectureName: 'Matrices',
      date: DateTime(2026, 11, 10), durationHours: 1);
    await db.update('revisit_items', {'status': 'COMPLETED'},
      where: 'lecture_id = ? AND offset_days = 1', whereArgs: [id]);
    await dbService.editLecture(id, title: 'Eigenvalues', subject: 'Algebra',
      date: DateTime(2026, 11, 13), hours: 2, session: 'Evening');
    var recalls = await db.query('revisit_items', where: 'lecture_id = ?', whereArgs: [id], orderBy: 'offset_days');
    expect(recalls.first['due_date'], '11 Nov 2026');
    expect(recalls[1]['due_date'], '17 Nov 2026');
    expect(recalls[1]['topic'], 'Algebra • Eigenvalues');
    expect((await dbService.getLecturesForDate(DateTime(2026, 11, 13))).single['details'], 'Eigenvalues');
    await dbService.deleteLecture(id);
    recalls = await db.query('revisit_items', where: 'topic LIKE ?', whereArgs: ['Algebra%']);
    expect(recalls, hasLength(1));
    expect(recalls.single['status'], 'COMPLETED');
    expect(recalls.single['lecture_id'], isNull);
  });

  test('Editing a quiz keeps its score and deleting the quiz keeps its logged traps', () async {
    final db = await dbService.database;
    final id = await dbService.insertQuiz(subject: 'Linear Algebra', title: 'Matrices', date: DateTime(2026, 11, 10));
    await db.update('quiz_items', {'score': 18, 'status': 'COMPLETED'}, where: 'id = ?', whereArgs: [id]);
    await dbService.insertMistakeRecord(subject: 'Linear Algebra', topic: 'Rank',
      questionText: 'Find rank', keyTakeaway: 'Count pivots', severity: 'HIGH', quizTitle: 'Matrices');
    await dbService.editQuiz(id, title: 'Matrices mock', subject: 'Linear Algebra', type: 'TEST_SERIES',
      date: DateTime(2026, 11, 11), minutes: 30, marks: 20, module: 'Matrices', syllabus: 'Rank', link: '');
    final quiz = (await db.query('quiz_items', where: 'id = ?', whereArgs: [id])).single;
    expect(quiz['quiz_type'], 'TEST_SERIES');
    expect(quiz['score'], 18);
    expect(quiz['status'], 'COMPLETED');
    await dbService.deleteQuiz(id);
    expect(await db.query('quiz_items', where: 'id = ?', whereArgs: [id]), isEmpty);
    expect(await db.query('mistake_records', where: 'quiz_title = ?', whereArgs: ['Matrices']), hasLength(1));
  });

  Future<void> savePreview(WidgetTester tester, GlobalKey key, String name) async {
    await tester.runAsync(() async {
      final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/ui-previews/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('Adaptive colors is grouped under Appearance and opens its own settings page', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await dbService.setConfig('adaptive_colors', '1');
      await dbService.setConfig('appearance_accent_index', '1');
      await AppearanceService.instance.load();
    });
    final preview = GlobalKey();
    await tester.pumpWidget(MaterialApp(theme: AppearanceService.instance.theme,
      builder: (context, child) => RepaintBoundary(key: preview, child: child!), home: const SettingsPage()));
    await settleDatabase(tester, find.text('Appearance'));
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.ensureVisible(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.byType(AppearanceSettingsPage), findsOneWidget);
    expect(find.text('Adaptive colors'), findsOneWidget);
    expect(find.text('Current accent'), findsOneWidget);
    expect(find.text('Iris'), findsWidgets);
    await savePreview(tester, preview, 'appearance-settings');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Reminder editor and calendar follow the active theme, including a live theme change', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final accent = ValueNotifier<Color>(AppearanceService.palette[1]);
    addTearDown(accent.dispose);
    final preview = GlobalKey();
    await tester.pumpWidget(ValueListenableBuilder<Color>(valueListenable: accent,
      builder: (_, color, __) => MaterialApp(theme: buildLightTheme(color),
        builder: (context, child) => RepaintBoundary(key: preview, child: child!),
        home: AlertsPage(onDataChanged: () {}, onOpenAddReminder: () {}))));
    await settleDatabase(tester, find.text('No Reminders Scheduled'));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(ElevatedButton, 'Save');
    expect(tester.widget<ElevatedButton>(save).style!.backgroundColor!.resolve({}), accent.value);
    accent.value = AppearanceService.palette[4];
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(save).style!.backgroundColor!.resolve({}), accent.value);
    await savePreview(tester, preview, 'reminder-themed');
    await tester.ensureVisible(find.text('Schedule Date'));
    await tester.tap(find.text('Schedule Date'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(DatePickerDialog))).colorScheme.primary, accent.value);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Quick add uses the shared accent and follows Mistakes and Test Series', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await dbService.setConfig('auto_check_updates', '0');
      await dbService.setConfig('auto_start_server', '0');
      await dbService.setConfig('notification_accent_v22', AppearanceService.instance.accent.toARGB32().toString());
    });
    final preview = GlobalKey();
    final accent = AppearanceService.palette[3];
    await tester.pumpWidget(MaterialApp(theme: buildLightTheme(accent),
      builder: (context, child) => RepaintBoundary(key: preview, child: child!), home: const HomePage()));
    await settleDatabase(tester, find.byType(TodayProgressSummary));
    await tester.tap(find.text('Add session'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(ElevatedButton, 'Save');
    expect(tester.widget<ElevatedButton>(save).style!.backgroundColor!.resolve({}), accent);
    await savePreview(tester, preview, 'schedule-themed');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Revisit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mistakes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Log a mistake'));
    await tester.pumpAndSettle();
    expect(find.text('Save Mistake Record'), findsOneWidget);
    Navigator.of(tester.element(find.text('Save Mistake Record'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Quizzes'));
    await tester.pump();
    await settleDatabase(tester, find.text('No quizzes found for the selected filter.'));
    await tester.tap(find.text('Test Series Mocks'));
    await tester.pump();
    await settleDatabase(tester, find.text('No quizzes found for the selected filter.'));
    await tester.tap(find.byTooltip('Add a test series mock'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Test Series Mocks')).selected, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  });

  testWidgets('Reopening from the background chooses a fresh shared accent', (tester) async {
    await tester.runAsync(() async {
      tz_data.initializeTimeZones();
      await dbService.setConfig('adaptive_colors', '1');
      await dbService.setConfig('appearance_accent_index', '1');
      await AppearanceService.instance.load();
    });
    final before = AppearanceService.instance.accent;
    await tester.pumpWidget(const AppAppearanceLifecycle(child: MaterialApp(home: SizedBox())));
    await tester.runAsync(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final appearance = AppearanceService.instance;
        if (appearance.accent != before && await dbService.getConfig('notification_accent_v22') == appearance.accent.toARGB32().toString()) break;
      }
    });
    await tester.pumpAndSettle();
    expect(AppearanceService.instance.accent, isNot(before));
    expect(AppearanceService.instance.colorFor('Reminder'), AppearanceService.instance.accent);
    await tester.pumpWidget(const SizedBox());
  });
}
