import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocket_bot/config/update_channel.dart';
import 'package:pocket_bot/services/dev_update.dart';
import 'package:pocket_bot/services/github_update_service.dart';
import 'package:pocket_bot/services/tailnet_dns.dart';
import 'package:test/test.dart';

void main() {
  const sha =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
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
    expect(
      tailnetSuffixFromDomains(['msi-laptop.tail07bfd4.ts.net.']),
      'tail07bfd4.ts.net',
    );
    expect(tailnetSuffixFromDomains(['ts.net']), isNull);
    expect(tailnetSuffixFromText(''), isNull);
  });

  test('tailscale addresses exclude the magicdns service', () {
    expect(isTailscaleIPv4('100.64.0.1'), isTrue);
    expect(isTailscaleIPv4('100.127.255.254'), isTrue);
    expect(isTailscaleIPv4('100.73.210.105'), isTrue);
    expect(isTailscaleIPv4('100.100.100.100'), isFalse);
    expect(isTailscaleIPv4('100.63.255.255'), isFalse);
    expect(isTailscaleIPv4('192.168.1.1'), isFalse);
    expect(
      tailscaleIpv4FromAddress('::ffff:100.73.210.105'),
      '100.73.210.105',
    );
    expect(tailscaleIpv4FromAddress('::ffff:6449:d269'), '100.73.210.105');
    expect(tailscaleIpv4FromAddress('100.100.100.100'), isNull);
  });

  test('a machine ptr name reduces to the tailnet suffix', () {
    expect(
      tailnetSuffixFromName('msi-laptop.tail07bfd4.ts.net.'),
      'tail07bfd4.ts.net',
    );
    expect(tailnetSuffixFromName('tail07bfd4.ts.net'), 'tail07bfd4.ts.net');
    expect(tailnetSuffixFromName('ts.net'), isNull);
  });

  test('missing search domains fall back to the phone ptr record', () async {
    var lookups = 0;
    final found = await resolveTailnetSuffix(
      domains: 'ts.net',
      addresses: const ['192.168.1.8', '100.90.1.2'],
      ptrLookup: (ip) async {
        lookups++;
        expect(ip, '100.90.1.2');
        return 'pixel.tail07bfd4.ts.net.';
      },
      observeLocalTailscaleAddress: () async {
        fail('local address is already known');
      },
    );
    expect(found.suffix, 'tail07bfd4.ts.net');
    expect(found.interfaceUp, isTrue);
    expect(lookups, 1);
  });

  test('a tailscale address without a ptr is still connected', () async {
    final found = await resolveTailnetSuffix(
      domains: '',
      addresses: const ['100.90.1.2'],
      ptrLookup: (_) async => null,
    );
    expect(found.suffix, isNull);
    expect(found.interfaceUp, isTrue);
  });

  test('quad 100 does not count as this phone', () async {
    var observed = false;
    final found = await resolveTailnetSuffix(
      domains: '',
      addresses: const ['100.100.100.100'],
      ptrLookup: (_) async => fail('no query'),
      observeLocalTailscaleAddress: () async {
        observed = true;
        return null;
      },
    );
    expect(observed, isTrue);
    expect(found.interfaceUp, isFalse);
    expect(found.suffix, isNull);
  });

  test('reaching magicdns counts as connected', () async {
    final found = await resolveTailnetSuffix(
      domains: '',
      addresses: const [],
      ptrLookup: (_) async => fail('no address to reverse'),
      magicDnsReachable: () async => true,
    );
    expect(found.suffix, isNull);
    expect(found.interfaceUp, isTrue);
  });

  test('ptr response yields the magicdns name', () {
    const name = 'msi-laptop.tail07bfd4.ts.net.';
    final query = encodeDnsPtrQuery(id: 0x5042, ipv4: '100.73.210.105');
    final response = _ptrResponse(query, name);
    expect(
      ptrNameFromDnsResponse(response, queryId: 0x5042),
      'msi-laptop.tail07bfd4.ts.net',
    );
    expect(ptrNameFromDnsResponse(response, queryId: 1), isNull);
    expect(ptrNameFromDnsResponse(_loopingPtr(), queryId: 1), isNull);
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

  test('dev channel finds the tailscale manifest without a saved address',
      () async {
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

  test('dev channel distinguishes a connected phone with no dns name',
      () async {
    final client = MockClient((request) async {
      fail('should not request ${request.url}');
    });
    final service = GithubUpdateService(
      httpClient: client,
      platform: () => UpdatePlatform.android,
      tailnetSuffix: () async => null,
      tailscaleUp: () async => true,
      installedDevSha256: () => null,
    );
    final outcome = await service.checkForUpdates(channel: UpdateChannel.dev);
    service.close();
    expect(outcome.notice, '已连上 Tailscale，但没有读到 tailnet 域名');
  });
}

Uint8List _ptrResponse(Uint8List query, String name) {
  final rdata = BytesBuilder(copy: false);
  for (final label in name.split('.').where((part) => part.isNotEmpty)) {
    final bytes = ascii.encode(label);
    rdata.addByte(bytes.length);
    rdata.add(bytes);
  }
  rdata.addByte(0);
  final body = rdata.toBytes();
  final packet = Uint8List(query.length + 12 + body.length);
  packet.setRange(0, query.length, query);
  packet[2] = 0x81;
  packet[3] = 0x80;
  packet[7] = 1;
  var offset = query.length;
  packet[offset++] = 0xc0;
  packet[offset++] = 0x0c;
  packet[offset++] = 0x00;
  packet[offset++] = 0x0c;
  packet[offset++] = 0x00;
  packet[offset++] = 0x01;
  offset += 4;
  packet[offset++] = body.length >> 8;
  packet[offset++] = body.length & 0xff;
  packet.setRange(offset, offset + body.length, body);
  return packet;
}

Uint8List _loopingPtr() {
  return Uint8List.fromList([
    0x00,
    0x01,
    0x81,
    0x80,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x00,
    0xc0,
    0x0c,
    0x00,
    0x0c,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x02,
    0xc0,
    0x0c,
  ]);
}
