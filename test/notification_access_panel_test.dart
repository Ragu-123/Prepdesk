import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasks/pages/settings/widgets/notification_access_panel.dart';
import 'package:tasks/utils/theme.dart';
import 'package:tasks/widgets/task_navigation_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var enabled = true;
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('io.github.thelazyindian.tasks/native'), (call) async {
        if (call.method == 'getNotificationAccess') return {
          'notifications': enabled, 'exact': enabled, 'fullScreen': enabled,
        };
        return null;
      });
  });
  testWidgets('Granted access hides request buttons and renders cleanly on a small phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    enabled = true;
    final preview = GlobalKey();
    await tester.pumpWidget(MaterialApp(theme: lightTheme, home: RepaintBoundary(key: preview,
      child: Scaffold(
        appBar: AppBar(title: const Text('Reminders & routine alerts')),
        body: const SingleChildScrollView(padding: EdgeInsets.all(16), child: NotificationAccessPanel()),
        floatingActionButton: FloatingActionButton(onPressed: () {}, child: const Icon(Icons.add_rounded)),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: TaskNavigationBar(selectedIndex: 0, onSelected: (_) {}, revisitCount: 3),
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Enable'), findsNothing);
    expect(find.text('Enabled'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    final boundary = preview.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/ui-previews/notification-access.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
  testWidgets('Only missing access shows Enable, including with larger text', (tester) async {
    enabled = false;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: lightTheme, home: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
      child: const Scaffold(body: SingleChildScrollView(child: NotificationAccessPanel())),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Enable'), findsNWidgets(3));
    expect(find.text('Enabled'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
