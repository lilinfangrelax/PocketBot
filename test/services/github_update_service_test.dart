import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocket_bot/config/update_channel.dart';
import 'package:pocket_bot/services/github_release_client.dart';
import 'package:test/test.dart';

Map<String, dynamic> _release({
  required String tag,
  required bool prerelease,
  List<Map<String, dynamic>> assets = const [],
}) {
  return {
    'tag_name': tag,
    'name': tag,
    'body': 'notes for $tag',
    'prerelease': prerelease,
    'draft': false,
    'html_url': 'https://github.com/lilinfangrelax/PocketBot/releases/tag/$tag',
    'assets': assets,
  };
}

Map<String, dynamic> _apk(String version) => {
      'name': 'PocketBot-$version.apk',
      'browser_download_url':
          'https://github.com/lilinfangrelax/PocketBot/releases/download/v$version/PocketBot-$version.apk',
      'size': 1024 * 1024,
    };

Map<String, dynamic> _zip(String version) => {
      'name': 'PocketBot-Windows-$version.zip',
      'browser_download_url':
          'https://github.com/lilinfangrelax/PocketBot/releases/download/v$version/PocketBot-Windows-$version.zip',
      'size': 8 * 1024 * 1024,
    };

void main() {
  group('GithubRelease.pickLatest', () {
    final releases = [
      GithubRelease.fromJson(_release(
        tag: 'v1.3.0-beta.1',
        prerelease: true,
        assets: [_apk('1.3.0-beta.1')],
      )),
      GithubRelease.fromJson(_release(
        tag: 'v1.2.0',
        prerelease: false,
        assets: [_apk('1.2.0'), _zip('1.2.0')],
      )),
      GithubRelease.fromJson(_release(
        tag: 'v1.1.1',
        prerelease: false,
        assets: [_apk('1.1.1')],
      )),
    ];

    test('stable ignores prereleases', () {
      final latest = GithubRelease.pickLatest(
        releases,
        channel: UpdateChannel.stable,
      );
      expect(latest?.tagName, 'v1.2.0');
    });

    test('beta picks the newest version including prereleases', () {
      final latest = GithubRelease.pickLatest(
        releases,
        channel: UpdateChannel.beta,
      );
      expect(latest?.tagName, 'v1.3.0-beta.1');
    });

    test('skips drafts and unparsable tags', () {
      final mixed = [
        GithubRelease.fromJson({
          ..._release(tag: 'nightly', prerelease: false),
          'draft': false,
        }),
        GithubRelease.fromJson({
          ..._release(tag: 'v1.4.0', prerelease: false),
          'draft': true,
        }),
        GithubRelease.fromJson(_release(tag: 'v1.0.0', prerelease: false)),
      ];
      final latest = GithubRelease.pickLatest(
        mixed,
        channel: UpdateChannel.stable,
      );
      expect(latest?.tagName, 'v1.0.0');
    });
  });

  group('GithubRelease.assetFor', () {
    test('selects apk and windows zip', () {
      final release = GithubRelease.fromJson(_release(
        tag: 'v1.2.0',
        prerelease: false,
        assets: [_apk('1.2.0'), _zip('1.2.0')],
      ));
      expect(release.assetFor(UpdatePlatform.android)?.name,
          'PocketBot-1.2.0.apk');
      expect(
        release.assetFor(UpdatePlatform.windows)?.name,
        'PocketBot-Windows-1.2.0.zip',
      );
      expect(release.assetFor(UpdatePlatform.other), isNull);
    });
  });

  group('GithubUpdateService.checkForUpdates', () {
    late List<Map<String, dynamic>> payload;

    MockClient client() {
      return MockClient((request) async {
        expect(request.url.path, contains('/releases'));
        expect(request.headers['User-Agent'], 'PocketBot');
        return http.Response(
          jsonEncode(payload),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
    }

    GithubReleaseClient service({
      required String current,
      required UpdatePlatform platform,
    }) {
      return GithubReleaseClient(
        httpClient: client(),
        currentVersion: () => current,
        platform: () => platform,
      );
    }

    setUp(() {
      payload = [
        _release(
          tag: 'v1.3.0-beta.1',
          prerelease: true,
          assets: [_apk('1.3.0-beta.1')],
        ),
        _release(
          tag: 'v1.2.0',
          prerelease: false,
          assets: [_apk('1.2.0'), _zip('1.2.0')],
        ),
      ];
    });

    test('stable user on latest stable is up to date', () async {
      final result = await service(
        current: '1.2.0',
        platform: UpdatePlatform.android,
      ).checkForUpdates(channel: UpdateChannel.stable);
      expect(result, isNotNull);
      expect(result!.updateAvailable, isFalse);
      expect(result.release.tagName, 'v1.2.0');
    });

    test('beta user is offered a newer prerelease', () async {
      final result = await service(
        current: '1.2.0',
        platform: UpdatePlatform.android,
      ).checkForUpdates(channel: UpdateChannel.beta);
      expect(result!.updateAvailable, isTrue);
      expect(result.release.tagName, 'v1.3.0-beta.1');
      expect(result.canDownload, isTrue);
    });

    test('stable does not downgrade from a newer beta', () async {
      final result = await service(
        current: '1.3.0-beta.1',
        platform: UpdatePlatform.android,
      ).checkForUpdates(channel: UpdateChannel.stable);
      expect(result!.updateAvailable, isFalse);
      expect(result.release.tagName, 'v1.2.0');
    });

    test('stable offers the release that supersedes the same beta', () async {
      payload = [
        _release(
          tag: 'v1.3.0',
          prerelease: false,
          assets: [_apk('1.3.0')],
        ),
        _release(
          tag: 'v1.3.0-beta.1',
          prerelease: true,
          assets: [_apk('1.3.0-beta.1')],
        ),
      ];
      final result = await service(
        current: '1.3.0-beta.1',
        platform: UpdatePlatform.android,
      ).checkForUpdates(channel: UpdateChannel.stable);
      expect(result!.updateAvailable, isTrue);
      expect(result.release.tagName, 'v1.3.0');
    });

    test('throws when GitHub responds with an error', () async {
      final failing = GithubReleaseClient(
        httpClient: MockClient((request) async => http.Response('nope', 403)),
        currentVersion: () => '1.0.0',
        platform: () => UpdatePlatform.android,
      );
      expect(
        () => failing.checkForUpdates(channel: UpdateChannel.stable),
        throwsA(isA<GithubReleaseException>()),
      );
    });
  });
}
