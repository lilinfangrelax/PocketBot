import 'package:pocket_bot/config/update_channel.dart';
import 'package:pocket_bot/services/github_release_client.dart';
import 'package:test/test.dart';

void main() {
  test('a beta build follows the beta channel until the user chooses', () {
    expect(
      resolveUpdateChannel(currentVersion: '1.2.18-beta'),
      UpdateChannel.beta,
    );
    expect(
      resolveUpdateChannel(currentVersion: '1.2.18'),
      UpdateChannel.stable,
    );
    expect(
      resolveUpdateChannel(
        savedId: 'stable',
        currentVersion: '1.2.18-beta',
      ),
      UpdateChannel.stable,
    );
  });

  test('a missing dev host says the tailscale publisher was not found', () {
    const outcome = UpdateCheckOutcome(
      channel: UpdateChannel.dev,
      failure: UpdateCheckFailure.emptyChannel,
    );
    expect(outcome.notice, '没有发现 Tailscale 上的开发机');
  });

  test('an empty stable channel tells the user to switch to beta', () {
    const outcome = UpdateCheckOutcome(
      channel: UpdateChannel.stable,
      failure: UpdateCheckFailure.emptyChannel,
    );
    expect(outcome.notice, contains('Beta'));
    expect(outcome.hasUpdate, isFalse);
  });

  test('a request failure stays distinct from an empty channel', () {
    const failed = UpdateCheckOutcome(
      channel: UpdateChannel.beta,
      failure: UpdateCheckFailure.request,
    );
    expect(failed.notice, '检查更新失败');
  });

  test('a request failure includes a redacted proxy error', () {
    const failed = UpdateCheckOutcome(
      channel: UpdateChannel.beta,
      failure: UpdateCheckFailure.request,
      error: 'HandshakeException: https://user:secret@proxy.local:8080/',
    );
    expect(failed.notice, contains('检查更新失败'));
    expect(failed.notice, contains('***:***@proxy.local:8080'));
    expect(failed.notice, isNot(contains('secret')));
  });
}
