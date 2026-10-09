import 'package:fluent_ui/fluent_ui.dart';
import 'package:pocket_bot/services/ssh_host_keys.dart';

/// Lets the user confirm an SSH host key, like OpenSSH's first-connect prompt.
HostKeyPrompt hostKeyPromptFor(GlobalKey<NavigatorState> navigatorKey) {
  return (check) async {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return !check.changed;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => HostKeyDialog(check: check),
    );
    return accepted == true;
  };
}

class HostKeyDialog extends StatelessWidget {
  const HostKeyDialog({super.key, required this.check});

  final HostKeyCheck check;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final mono = theme.typography.body?.copyWith(fontFamily: 'monospace');
    final address = '${check.host}:${check.port}';
    return ContentDialog(
      title: Text(check.changed ? '主机密钥已变化' : '首次连接此主机'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (check.changed) ...[
            InfoBar(
              title: const Text('可能存在中间人攻击'),
              content: Text(
                '$address 提供的密钥和上次不同。除非你确认服务器重装过或更换了密钥，否则请取消。',
              ),
              severity: InfoBarSeverity.error,
              isLong: true,
            ),
            const SizedBox(height: 12),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('请确认 $address 的主机密钥指纹与服务器一致。'),
            ),
          Text('${check.keyType} 指纹'),
          const SizedBox(height: 4),
          SelectableText(check.fingerprint, style: mono),
          if (check.changed) ...[
            const SizedBox(height: 12),
            const Text('之前记住的指纹'),
            const SizedBox(height: 4),
            SelectableText(check.previousFingerprint!, style: mono),
          ],
          const SizedBox(height: 12),
          Text(
            '可在服务器上运行 ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub 核对。',
            style: theme.typography.caption,
          ),
        ],
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(check.changed ? '仍然信任' : '信任并连接'),
        ),
      ],
    );
  }
}
