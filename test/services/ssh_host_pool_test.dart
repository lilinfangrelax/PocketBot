import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/ssh_host_pool.dart';

void main() {
  final host = GatewayInfo.ssh(host: 'box', username: 'me', password: 'pw');

  test('a failed login marks the host offline with a readable error', () async {
    final pool = SshHostPool(
      open: (_) async => throw Exception('AUTH_FAILED:SSH 认证失败，请检查用户名、密码或私钥'),
    );
    addTearDown(pool.dispose);

    expect(pool.stateOf(host).status, HostStatus.unknown);
    expect(await pool.check(host), isFalse);
    final state = pool.stateOf(host);
    expect(state.status, HostStatus.offline);
    expect(state.error, 'SSH 认证失败，请检查用户名、密码或私钥');
    expect(pool.isConnected(host), isFalse);
  });

  test('concurrent logins to one host share a single attempt', () async {
    var attempts = 0;
    final gate = Completer<SSHClient>();
    final pool = SshHostPool(open: (_) {
      attempts++;
      return gate.future;
    });
    addTearDown(pool.dispose);

    final first = pool.check(host);
    final second = pool.check(host.copyWith(workingDirectory: '/other'));
    expect(pool.stateOf(host).status, HostStatus.checking);
    gate.completeError(Exception('CONNECTION_TIMEOUT:SSH 连接超时'));
    expect(await first, isFalse);
    expect(await second, isFalse);
    expect(attempts, 1);
    expect(pool.stateOf(host).error, 'SSH 连接超时');
  });

  test('forget clears the host state', () async {
    final pool = SshHostPool(open: (_) async => throw Exception('down'));
    addTearDown(pool.dispose);
    await pool.check(host);
    pool.forget(host);
    expect(pool.stateOf(host).status, HostStatus.unknown);
  });

  test('local targets have no shared SSH client', () {
    final pool = SshHostPool(open: (_) async => throw Exception('unused'));
    addTearDown(pool.dispose);
    expect(() => pool.client(GatewayInfo.local()), throwsArgumentError);
  });

  test('hostErrorText strips exception and code prefixes', () {
    expect(hostErrorText(Exception('HOST_KEY_REJECTED:密钥变了')), '密钥变了');
    expect(hostErrorText('plain failure'), 'plain failure');
    expect(hostErrorText(Exception('')), 'SSH 连接失败');
  });
}
