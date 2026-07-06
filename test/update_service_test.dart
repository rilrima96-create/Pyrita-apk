import 'package:flutter_test/flutter_test.dart';
import 'package:pyrita_app/core/update_service.dart';

void main() {
  test('checks updates through the Pyrita release endpoint first', () {
    expect(
      UpdateService.releaseEndpoint,
      'https://api.pyrita.com/api/release/latest',
    );
    expect(UpdateService.targetAbiAsset, 'app-arm64-v8a-release.apk');
  });

  test('parses self-hosted release payload with the direct APK asset', () {
    final info = UpdateService.parseReleasePayload(
      currentVersion: '0.1.31',
      data: {
        'tag_name': 'v0.1.32',
        'html_url': 'https://pyrita.com/download',
        'body': 'Auth, server picker, and account loading fixes.',
        'assets': [
          {
            'name': 'app-armeabi-v7a-release.apk',
            'browser_download_url':
                'https://pyrita.com/api/release/file/v0.1.32/app-armeabi-v7a-release.apk',
            'size': 41000000,
          },
          {
            'name': 'app-arm64-v8a-release.apk',
            'browser_download_url':
                'https://pyrita.com/api/release/file/v0.1.32/app-arm64-v8a-release.apk',
            'size': 52000000,
          },
        ],
      },
    );

    expect(info, isNotNull);
    expect(info!.latestVersion, '0.1.32');
    expect(info.tagName, 'v0.1.32');
    expect(info.releaseUrl, 'https://pyrita.com/download');
    expect(info.assetUrl, contains('/api/release/file/v0.1.32/'));
    expect(info.assetSizeBytes, 52000000);
    expect(info.hasUpdate, isTrue);
  });
}
