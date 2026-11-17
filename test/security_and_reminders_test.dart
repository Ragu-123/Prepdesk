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
}
