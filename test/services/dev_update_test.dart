import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocket_bot/config/update_channel.dart';
import 'package:pocket_bot/services/dev_update.dart';
import 'package:pocket_bot/services/github_update_service.dart';
import 'package:test/test.dart';

void main() {
  const sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const rebuilt =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  test('pubspec version drops the build number', () {
    expect(
      readPubspecVersion('name: pocket_bot\nversion: 1.2.27-beta+3\n'),
      '1.2.27-beta',
    );
  });

  test('tailnet suffix ignores machine hostnames', () {
    const status = '''
MagicDNS: enabled tailnet-wide (suffix = example.ts.net)

Other devices can reach this device at msi-laptop.example.ts.net.

Search Domains:
  - example.ts.net
  - ts.net.
''';
    expect(tailnetSuffixFromText(status), 'example.ts.net');
    expect(
      tailnetSuffixFromDomains(['msi-laptop.example.ts.net', 'example.ts.net']),
      'example.ts.net',
    );
    expect(tailnetSuffixFromText(''), isNull);
  });

  test('manifest uri uses the service name and discovered suffix', () {
    expect(
      devUpdateManifestUri('Example.ts.net'),
      Uri.parse('https://msi-laptop.example.ts.net/update.json'),
    );
    expect(
      () => devUpdateManifestUri('msi-laptop.example.ts.net'),
      throwsFormatException,
    );
  });

  test('a rebuilt apk is offered when the version string stays the same', () {
    expect(
      devBuildAvailable(sha256: rebuilt, installedSha256: sha),
      isTrue,
    );
    expect(
      devBuildAvailable(sha256: sha, installedSha256: sha.toUpperCase()),
      isFalse,
    );
  });

  test('byte ranges resume from an offset', () {
    final whole = byteRangeForRequest(null, 10);
    expect(whole!.start, 0);
    expect(whole.end, 10);
    final rest = byteRangeForRequest('bytes=4-', 10);
    expect(rest!.start, 4);
    expect(rest.length, 6);
    expect(byteRangeForRequest('bytes=10-', 10), isNull);
  });

  test('dev channel finds the tailscale manifest without a saved address', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'msi-laptop.example.ts.net');
      expect(request.url.path, '/update.json');
      return http.Response(
        jsonEncode({
          'version': '1.2.27-beta',
          'sha256': rebuilt,
          'size': 128,
          'file': devUpdateApkName,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = GithubUpdateService(
      httpClient: client,
      currentVersion: () => '1.2.27-beta',
      platform: () => UpdatePlatform.android,
      tailnetSuffix: () async => 'example.ts.net',
      installedDevSha256: () => sha,
    );
    final outcome = await service.checkForUpdates(channel: UpdateChannel.dev);
    service.close();

    expect(outcome.hasUpdate, isTrue);
    expect(outcome.result!.sourceLabel, '开发机');
    expect(outcome.result!.devSha256, rebuilt);
    expect(
      outcome.result!.platformAsset!.downloadUrl,
      'https://msi-laptop.example.ts.net/PocketBot.apk',
    );
  });

  test('dev channel stays quiet after that build was installed', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'version': '1.2.27-beta',
          'sha256': sha,
          'size': 128,
          'file': devUpdateApkName,
        }),
        200,
      );
    });
    final service = GithubUpdateService(
      httpClient: client,
      currentVersion: () => '1.2.27-beta',
      platform: () => UpdatePlatform.android,
      tailnetSuffix: () async => 'example.ts.net',
      installedDevSha256: () => sha,
    );
    final outcome = await service.checkForUpdates(channel: UpdateChannel.dev);
    service.close();
    expect(outcome.hasUpdate, isFalse);
    expect(outcome.notice, '已是最新版本');
  });

  test('dev channel does not guess a host when tailscale is down', () async {
    final client = MockClient((request) async {
      fail('should not request ${request.url}');
    });
    final service = GithubUpdateService(
      httpClient: client,
      platform: () => UpdatePlatform.android,
      tailnetSuffix: () async => null,
      installedDevSha256: () => null,
    );
    final outcome = await service.checkForUpdates(channel: UpdateChannel.dev);
    service.close();
    expect(outcome.notice, '手机没有连上 Tailscale');
  });
}
