import 'package:flutter_test/flutter_test.dart';
import 'package:tasks/services/app_update_service.dart';

void main() {
  Map<String, dynamic> asset(String name) => {
    'name': name,
    'browser_download_url': 'https://example.com/$name',
    'size': 42,
  };

  final release = {
    'assets': [
      asset('prepdesk-x86_64.apk'),
      asset('app-release.apk'),
      asset('prepdesk-arm64-v8a.apk'),
    ],
  };

  test('Update selects the APK for the device architecture', () {
    for (final abi in ['arm64-v8a', 'x86_64']) {
      final update = AppReleaseInfo.fromJson(release, androidAbi: abi);
      expect(update.apkDownloadUrl, endsWith('prepdesk-$abi.apk'));
      expect(update.apkSizeBytes, 42);
    }
  });

  test('Unknown architectures fall back to the universal APK', () {
    expect(AppReleaseInfo.fromJson(release).apkDownloadUrl, endsWith('app-release.apk'));
  });

  test('Older APK names work while incompatible device APKs are skipped', () {
    final oldRelease = {
      'assets': [asset('prepdesk-x86_64.apk'), asset('prepdesk-release.apk')],
    };
    final update = AppReleaseInfo.fromJson(oldRelease, androidAbi: 'arm64-v8a');
    expect(update.apkDownloadUrl, endsWith('prepdesk-release.apk'));
  });
}
