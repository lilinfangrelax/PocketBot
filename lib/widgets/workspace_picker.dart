import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pocket_bot/models/group_workspace.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/screens/remote_directory_picker.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/ssh_host_pool.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';

/// What the user chose in [pickWorkspace].
class WorkspaceChoice {
  final GroupWorkspace? workspace;

  const WorkspaceChoice(this.workspace);

  bool get cleared => workspace == null;
}

/// Saved hosts, one entry per machine.
List<GatewayInfo> distinctHosts(List<GatewayInfo> saved) {
  final seen = <String>{};
  return [
    for (final gateway in saved)
      if (seen.add(gateway.hostId)) gateway,
  ];
}

String workspaceLabel(ConnectionManager manager, GroupWorkspace workspace) {
  final host = manager.hostById(workspace.hostId);
  final where = host == null
      ? '已删除的主机'
      : (host.name.isEmpty ? host.hostLabel : host.name);
  return '$where · ${workspace.workingDirectory}';
}

/// Asks for a saved host, logs in to it, then browses for a folder.
/// Returns null when cancelled, or a choice with no workspace when the user
/// cleared it.
Future<WorkspaceChoice?> pickWorkspace(
  BuildContext context, {
  required String groupId,
  GroupWorkspace? current,
}) async {
  final manager = context.read<ConnectionManager>();
  final hosts = distinctHosts(manager.savedGateways);
  if (hosts.isEmpty) {
    showAppNotice(context, '还没有保存的主机，请先在「发现」页添加');
    return null;
  }

  final picked = await showDialog<Object>(
    context: context,
    builder: (_) => _HostDialog(hosts: hosts, current: current),
  );
  if (picked == null || !context.mounted) return null;
  if (picked == _clearChoice) return const WorkspaceChoice(null);
  final host = picked as GatewayInfo;

  final initial = current != null && current.hostId == host.hostId
      ? current.workingDirectory
      : host.workingDirectory;
  final String? path;
  if (host.kind == AgentTransportKind.ssh) {
    path = await _browseRemote(context, manager, host, initial);
  } else {
    path = await _askLocalPath(context, initial);
  }
  if (path == null || path.trim().isEmpty) return null;
  return WorkspaceChoice(GroupWorkspace(
    groupId: groupId,
    hostId: host.hostId,
    workingDirectory: path.trim(),
  ));
}

const _clearChoice = Object();

Future<String?> _browseRemote(
  BuildContext context,
  ConnectionManager manager,
  GatewayInfo host,
  String initial,
) async {
  if (host.requiresAuth) {
    showAppNotice(context, '这台主机没有保存密码或私钥，请先在「发现」页编辑');
    return null;
  }
  var loadingShown = true;
  final navigator = Navigator.of(context);
  fluent.showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const fluent.ContentDialog(
      content: Row(
        children: [
          fluent.ProgressRing(),
          SizedBox(width: 16),
          Expanded(child: Text('正在登录远程主机...')),
        ],
      ),
    ),
  );
  try {
    final session = await manager.browseHost(host);
    if (!context.mounted) return null;
    navigator.pop();
    loadingShown = false;
    try {
      return await navigator.push<String>(
        MaterialPageRoute(
          builder: (_) => RemoteDirectoryPicker(
            source: session,
            hostLabel: host.hostLabel,
            initialPath: initial,
          ),
        ),
      );
    } finally {
      await session.close();
    }
  } catch (error) {
    if (loadingShown && context.mounted) navigator.pop();
    if (context.mounted) showAppNotice(context, hostErrorText(error));
    return null;
  }
}

Future<String?> _askLocalPath(BuildContext context, String initial) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('本机工作目录'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: r'C:\Dev\project 或 /home/user/project',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('确定'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

class _HostDialog extends StatelessWidget {
  const _HostDialog({required this.hosts, this.current});

  final List<GatewayInfo> hosts;
  final GroupWorkspace? current;

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<ConnectionManager>();
    final colors = FluentColors.of(context);
    return SimpleDialog(
      title: const Text('选择主机'),
      children: [
        for (final host in hosts)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, host),
            child: Row(
              children: [
                HostStatusDot(state: manager.hostState(host)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(host.name.isEmpty ? host.hostLabel : host.name),
                      Text(
                        host.hostLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (current?.hostId == host.hostId)
                  Icon(Icons.check, size: 18, color: colors.accent),
              ],
            ),
          ),
        if (current != null && current!.isSet)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _clearChoice),
            child: Text(
              '不使用群聊目录',
              style: TextStyle(color: colors.danger),
            ),
          ),
      ],
    );
  }
}

class HostStatusDot extends StatelessWidget {
  const HostStatusDot({super.key, required this.state});

  final HostState state;

  @override
  Widget build(BuildContext context) {
    final colors = FluentColors.of(context);
    final color = switch (state.status) {
      HostStatus.online => colors.success,
      HostStatus.offline => colors.danger,
      HostStatus.checking => colors.info,
      HostStatus.unknown => colors.textTertiary,
    };
    return Tooltip(
      message: hostStatusText(state),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

String hostStatusText(HostState state) {
  switch (state.status) {
    case HostStatus.online:
      return '在线';
    case HostStatus.checking:
      return '正在检查…';
    case HostStatus.offline:
      return state.error == null ? '离线' : '离线：${state.error}';
    case HostStatus.unknown:
      return '未检查';
  }
}
