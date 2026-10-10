/// How a saved-connection row should be painted.
///
/// Green means the ACP session for that row is up. A saved or last-selected
/// target, and a host whose SSH port answered a probe, are not a session.
enum SavedConnectionTone { muted, info, success, danger }

class SavedConnectionPresentation {
  const SavedConnectionPresentation({
    required this.showConnectedBadge,
    required this.showSpinner,
    required this.showConnectButton,
    required this.detailLabel,
    required this.tone,
  });

  final bool showConnectedBadge;
  final bool showSpinner;
  final bool showConnectButton;
  final String? detailLabel;
  final SavedConnectionTone tone;
}

/// [hostReachable] is null until a probe finishes. [sessionLive] is the ACP
/// transport for this row, not merely "this is the selected gateway".
SavedConnectionPresentation describeSavedConnection({
  required bool sessionLive,
  required bool connecting,
  required bool failed,
  required bool? hostReachable,
  required bool ssh,
}) {
  if (sessionLive) {
    return const SavedConnectionPresentation(
      showConnectedBadge: true,
      showSpinner: false,
      showConnectButton: false,
      detailLabel: null,
      tone: SavedConnectionTone.success,
    );
  }
  if (connecting) {
    return const SavedConnectionPresentation(
      showConnectedBadge: false,
      showSpinner: true,
      showConnectButton: false,
      detailLabel: '正在连接',
      tone: SavedConnectionTone.info,
    );
  }
  if (failed) {
    return const SavedConnectionPresentation(
      showConnectedBadge: false,
      showSpinner: false,
      showConnectButton: true,
      detailLabel: '连接失败',
      tone: SavedConnectionTone.danger,
    );
  }
  if (hostReachable == true) {
    return SavedConnectionPresentation(
      showConnectedBadge: false,
      showSpinner: false,
      showConnectButton: true,
      detailLabel: ssh ? '主机可达' : '本机可用',
      tone: SavedConnectionTone.info,
    );
  }
  if (hostReachable == false) {
    return SavedConnectionPresentation(
      showConnectedBadge: false,
      showSpinner: false,
      showConnectButton: true,
      detailLabel: ssh ? '主机不可达' : '本机不可用',
      tone: SavedConnectionTone.danger,
    );
  }
  return const SavedConnectionPresentation(
    showConnectedBadge: false,
    showSpinner: false,
    showConnectButton: true,
    detailLabel: '未检查',
    tone: SavedConnectionTone.muted,
  );
}

/// Counts a host the port probe reached, or one with a live session.
bool countsAsSshOnline({
  required bool sessionLive,
  required bool? hostReachable,
}) =>
    sessionLive || hostReachable == true;

String savedConnectionsHeading({
  required int sshCount,
  required int sshOnline,
}) {
  if (sshCount == 0) return '已保存的连接';
  return '已保存的连接 · SSH 在线 $sshOnline/$sshCount';
}
