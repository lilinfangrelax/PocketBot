import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/screens/acp_registry_screen.dart';
import 'package:pocket_bot/services/acp_registry.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';

/// Which agent an AI contact talks to: a saved connection, a folder on that
/// machine, and an ACP registry agent.
class AgentBinding {
  final String gatewayId;
  final String workingDirectory;
  final String agentId;
  final String agentLabel;

  const AgentBinding({
    required this.gatewayId,
    required this.workingDirectory,
    required this.agentId,
    required this.agentLabel,
  });

  bool get isComplete => gatewayId.isNotEmpty && agentId.isNotEmpty;
}

class AgentBindingEditor extends StatefulWidget {
  const AgentBindingEditor({
    super.key,
    required this.onChanged,
    this.initial,
  });

  final AgentBinding? initial;
  final ValueChanged<AgentBinding?> onChanged;

  @override
  State<AgentBindingEditor> createState() => _AgentBindingEditorState();
}

class _AgentBindingEditorState extends State<AgentBindingEditor> {
  final _directory = TextEditingController();
  GatewayInfo? _gateway;
  String _agentId = '';
  String _agentLabel = '';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final gateways = context.read<ConnectionManager>().savedGateways;
    for (final gateway in gateways) {
      if (gateway.connectionId == initial?.gatewayId) _gateway = gateway;
    }
    _gateway ??= gateways.isEmpty ? null : gateways.first;
    _directory.text = initial?.workingDirectory.isNotEmpty == true
        ? initial!.workingDirectory
        : _gateway?.workingDirectory ?? '';
    _agentId = initial?.agentId.isNotEmpty == true
        ? initial!.agentId
        : _gateway?.agentId ?? '';
    _agentLabel = initial?.agentLabel.isNotEmpty == true
        ? initial!.agentLabel
        : _gateway?.agentLabel ?? '';
    if (_agentId.isEmpty) {
      _agentId = 'cursor';
      _agentLabel = 'Cursor';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _directory.dispose();
    super.dispose();
  }

  void _emit() {
    final gateway = _gateway;
    widget.onChanged(gateway == null
        ? null
        : AgentBinding(
            gatewayId: gateway.connectionId,
            workingDirectory: _directory.text.trim(),
            agentId: _agentId,
            agentLabel: _agentLabel,
          ));
  }

  Future<void> _pickAgent() async {
    final picked = await Navigator.push<AcpRegistryAgent>(
      context,
      MaterialPageRoute(
        builder: (_) => AcpRegistryScreen(selectedId: _agentId),
      ),
    );
    if (picked == null) return;
    setState(() {
      _agentId = picked.id;
      _agentLabel = picked.name;
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FluentColors.of(context);
    final gateways = context.watch<ConnectionManager>().savedGateways;
    if (gateways.isEmpty) {
      return Text(
        '还没有保存的连接。请先在「发现」页连接一次本机或 SSH 主机。',
        style: TextStyle(color: colors.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _gateway?.connectionId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '运行在',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final gateway in gateways)
              DropdownMenuItem(
                value: gateway.connectionId,
                child: Text(
                  '${gateway.name} · ${gateway.kind == AgentTransportKind.local ? '本机' : '${gateway.username}@${gateway.host}'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) {
            final gateway =
                gateways.firstWhere((item) => item.connectionId == id);
            setState(() {
              _gateway = gateway;
              _directory.text = gateway.workingDirectory;
            });
            _emit();
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _directory,
          decoration: const InputDecoration(
            labelText: '工作目录',
            hintText: '/home/me/project',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.smart_toy_outlined),
          title: Text(_agentLabel.isEmpty ? _agentId : _agentLabel),
          subtitle: const Text('ACP 代理，点按更换'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickAgent,
        ),
      ],
    );
  }
}
