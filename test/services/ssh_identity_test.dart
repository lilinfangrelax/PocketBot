import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/services/acp_transport.dart';

void main() {
  late Directory dir;
  final hasKeygen = Process.runSync('which', ['ssh-keygen']).exitCode == 0;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ssh-identity');
  });

  tearDown(() => dir.delete(recursive: true));

  Future<String> generateKey(String passphrase) async {
    final path = '${dir.path}/id_${passphrase.isEmpty ? 'plain' : 'locked'}';
    final result = await Process.run('ssh-keygen', [
      '-q', '-t', 'ed25519', '-N', passphrase, '-f', path, //
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return File(path).readAsString();
  }

  test('returns null when no key is configured', () {
    expect(loadSshIdentities('  '), isNull);
  });

  test('loads unencrypted keys', () async {
    final pem = await generateKey('');
    expect(loadSshIdentities(pem), hasLength(1));
  }, skip: !hasKeygen);

  test('asks for a passphrase and rejects a wrong one', () async {
    final pem = await generateKey('secret');
    expect(
      () => loadSshIdentities(pem),
      throwsA(predicate((e) => '$e'.contains('请填写私钥密码'))),
    );
    expect(
      () => loadSshIdentities(pem, passphrase: 'wrong'),
      throwsA(predicate((e) => '$e'.contains('私钥密码不正确'))),
    );
    expect(loadSshIdentities(pem, passphrase: 'secret'), hasLength(1));
  }, skip: !hasKeygen);
}
