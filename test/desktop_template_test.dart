import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasks/services/desktop/desktop_web_template.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Desktop uses bundled icons and fonts and exports an inspectable preview', () async {
    final html = DesktopWebTemplate.render(localIp: '192.168.1.8', port: 8080, version: '1.0.18');
    expect(html, contains('window.NYRO_ICONS'));
    expect(html, contains('/assets/material-icons.otf'));
    expect(html, contains('Prepdesk Desktop Companion'));
    expect(html, contains('/assets/prepdesk.png'));
    expect(html, isNot(contains('fonts.googleapis.com')));
    expect(html, isNot(contains('localStorage.setItem')));
    expect(html, contains('aria-labelledby="pair-title"'));
    final directory = Directory('build/desktop-preview/assets');
    await directory.create(recursive: true);
    await File('build/desktop-preview/index.html').writeAsString(html);
    for (final entry in {
      'prepdesk.png': 'assets/images/prepdesk.png',
      'prepdesk_mark.png': 'assets/images/prepdesk_mark.png',
      'material-icons.otf': 'fonts/MaterialIcons-Regular.otf',
      'studio-regular.ttf': 'assets/google_fonts/NotoSans-Regular.ttf',
      'studio-bold.ttf': 'assets/google_fonts/NotoSans-Bold.ttf',
    }.entries) {
      final data = await rootBundle.load(entry.value);
      await File('${directory.path}/${entry.key}').writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }
  });
}
