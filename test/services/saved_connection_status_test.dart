import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/services/saved_connection_status.dart';

void main() {
  group('describeSavedConnection', () {
    test('a selected host that never connected is not green', () {
      final status = describeSavedConnection(
        sessionLive: false,
        connecting: false,
        failed: false,
        hostReachable: null,
        ssh: true,
      );

      expect(status.showConnectedBadge, isFalse);
      expect(status.showConnectButton, isTrue);
      expect(status.detailLabel, '未检查');
      expect(status.tone, SavedConnectionTone.muted);
    });

    test('a reachable SSH port is not a live agent session', () {
      final status = describeSavedConnection(
        sessionLive: false,
        connecting: false,
        failed: false,
        hostReachable: true,
        ssh: true,
      );

      expect(status.showConnectedBadge, isFalse);
      expect(status.detailLabel, '主机可达');
      expect(status.tone, SavedConnectionTone.info);
    });

    test('an unreachable host stays off the connected badge', () {
      final status = describeSavedConnection(
        sessionLive: false,
        connecting: false,
        failed: false,
        hostReachable: false,
        ssh: true,
      );

      expect(status.showConnectedBadge, isFalse);
      expect(status.detailLabel, '主机不可达');
      expect(status.tone, SavedConnectionTone.danger);
    });

    test('a failed attempt shows the failure instead of 已连接', () {
      final status = describeSavedConnection(
        sessionLive: false,
        connecting: false,
        failed: true,
        hostReachable: true,
        ssh: true,
      );

      expect(status.showConnectedBadge, isFalse);
      expect(status.showConnectButton, isTrue);
      expect(status.detailLabel, '连接失败');
      expect(status.tone, SavedConnectionTone.danger);
    });

    test('connecting shows a spinner and not the connected badge', () {
      final status = describeSavedConnection(
        sessionLive: false,
        connecting: true,
        failed: false,
        hostReachable: null,
        ssh: true,
      );

      expect(status.showConnectedBadge, isFalse);
      expect(status.showSpinner, isTrue);
      expect(status.showConnectButton, isFalse);
      expect(status.detailLabel, '正在连接');
    });

    test('a missing local agent is not shown as connected', () {
      final status = describeSavedConnection(
        sessionLive: false,
        connecting: false,
        failed: false,
        hostReachable: false,
        ssh: false,
      );

      expect(status.showConnectedBadge, isFalse);
      expect(status.detailLabel, '本机不可用');
    });

    test('only a live session is green', () {
      final status = describeSavedConnection(
        sessionLive: true,
        connecting: false,
        failed: false,
        hostReachable: null,
        ssh: true,
      );

      expect(status.showConnectedBadge, isTrue);
      expect(status.showConnectButton, isFalse);
      expect(status.detailLabel, isNull);
      expect(status.tone, SavedConnectionTone.success);
    });
  });

  group('saved connection heading', () {
    test('omits the SSH tally when there are no SSH targets', () {
      expect(
        savedConnectionsHeading(sshCount: 0, sshOnline: 0),
        '已保存的连接',
      );
    });

    test('counts probed or live SSH hosts, not saved rows', () {
      expect(
        countsAsSshOnline(sessionLive: false, hostReachable: null),
        isFalse,
      );
      expect(
        countsAsSshOnline(sessionLive: false, hostReachable: false),
        isFalse,
      );
      expect(
        countsAsSshOnline(sessionLive: false, hostReachable: true),
        isTrue,
      );
      expect(
        countsAsSshOnline(sessionLive: true, hostReachable: false),
        isTrue,
      );
      expect(
        savedConnectionsHeading(sshCount: 1, sshOnline: 0),
        '已保存的连接 · SSH 在线 0/1',
      );
    });
  });
}
