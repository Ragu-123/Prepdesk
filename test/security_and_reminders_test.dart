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

class _Paths extends PathProviderPlatform {
  final String path;
  _Paths(this.path);
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
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
  test('Cloud export strips vault credentials and protected notes', () async {
    final db = await dbService.database;
    await db.insert('keep_notes', {'id': 'private', 'title': 'Secret', 'content': 'Private', 'is_locked': 1, 'created_at': 1, 'updated_at': 1});
    await dbService.setKeepVaultPinHash('old-hash');
    final path = await dbService.exportSanitizedDatabaseForCloudUpload();
    final exported = await openDatabase(path);
    expect(await exported.query('keep_notes'), isEmpty);
    expect(await exported.query('app_config', where: "key LIKE 'keep_vault_%'"), isEmpty);
    await exported.close();
    expect(await db.query('keep_notes'), hasLength(1));
  });
  testWidgets('Missing vault credentials never turn unlock into PIN setup', (tester) async {
    var unlocked = false;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => VaultService.instance.showAuthDialog(context,
        onAuthenticated: () => unlocked = true), child: const Text('Open private note')),
    ))));
    await tester.tap(find.text('Open private note'));
    await tester.pumpAndSettle();
    expect(unlocked, isFalse);
    expect(find.text('Set Master Vault PIN'), findsNothing);
    expect(find.text('Vault credentials are unavailable. Protected notes remain locked.'), findsOneWidget);
  });
}
