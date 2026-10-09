import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/services/ssh_host_keys.dart';

void main() {
  late MemoryKnownHostStore store;

  setUp(() {
    store = MemoryKnownHostStore();
    SshHostKeys.store = store;
    SshHostKeys.prompt = null;
  });

  tearDown(() {
    SshHostKeys.store = const SecureKnownHostStore();
    SshHostKeys.prompt = null;
  });

  Future<bool> verify(String fingerprint) => SshHostKeys.verify(
        host: 'Example.com',
        port: 22,
        keyType: 'ssh-ed25519',
        fingerprint: fingerprint,
      );

  test('pins an unknown key on first use and accepts it afterwards', () async {
    expect(await verify('SHA256:aaa'), isTrue);
    expect(store.entries['example.com:22'], 'SHA256:aaa');
    expect(await verify('SHA256:aaa'), isTrue);
  });

  test('rejects a changed key when nobody can confirm it', () async {
    store.entries['example.com:22'] = 'SHA256:aaa';
    expect(await verify('SHA256:bbb'), isFalse);
    expect(store.entries['example.com:22'], 'SHA256:aaa');
  });

  test('asks the prompt and stores the key only when accepted', () async {
    final seen = <HostKeyCheck>[];
    var answer = false;
    SshHostKeys.prompt = (check) async {
      seen.add(check);
      return answer;
    };

    expect(await verify('SHA256:aaa'), isFalse);
    expect(store.entries, isEmpty);
    expect(seen.single.changed, isFalse);

    answer = true;
    expect(await verify('SHA256:aaa'), isTrue);
    expect(await verify('SHA256:bbb'), isTrue);
    expect(seen.last.changed, isTrue);
    expect(seen.last.previousFingerprint, 'SHA256:aaa');
    expect(store.entries['example.com:22'], 'SHA256:bbb');
  });

  test('forget clears the pinned key', () async {
    await verify('SHA256:aaa');
    await SshHostKeys.forget('example.com', 22);
    expect(store.entries, isEmpty);
  });
}
