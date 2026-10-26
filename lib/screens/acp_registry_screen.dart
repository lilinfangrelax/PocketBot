import 'package:flutter/material.dart';
import 'package:pocket_bot/screens/custom_acp_agent_screen.dart';
import 'package:pocket_bot/services/acp_registry.dart';
import 'package:pocket_bot/services/custom_acp_agent.dart';

/// Pick an ACP agent from the public registry or from saved custom commands.
class AcpRegistryScreen extends StatefulWidget {
  final String? selectedId;

  const AcpRegistryScreen({super.key, this.selectedId});

  @override
  State<AcpRegistryScreen> createState() => _AcpRegistryScreenState();
}

class _AcpRegistryScreenState extends State<AcpRegistryScreen> {
  final TextEditingController _query = TextEditingController();
  List<AcpRegistryAgent> _agents = const [];
  List<CustomAcpAgent> _custom = const [];
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final custom = await CustomAcpCatalog.load();
    try {
      final agents = await AcpRegistryCatalog.load();
      if (!mounted) return;
      setState(() {
        _custom = custom;
        _agents = agents;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _custom = custom;
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _editCustom([CustomAcpAgent? agent]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomAcpAgentScreen(initial: agent),
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim().toLowerCase();
    final custom = _custom.where((agent) {
      if (query.isEmpty) return true;
      return agent.name.toLowerCase().contains(query) ||
          agent.id.contains(query) ||
          agent.program.toLowerCase().contains(query);
    }).toList();
    final visible = _agents.where((agent) {
      if (query.isEmpty) return true;
      return agent.name.toLowerCase().contains(query) ||
          agent.id.contains(query) ||
          agent.description.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ACP 代理'),
        actions: [
          IconButton(
            tooltip: '添加自定义代理',
            onPressed: () => _editCustom(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _query,
              decoration: const InputDecoration(
                hintText: '搜索 Cursor、Claude、Gemini…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Registry 来自 agentclientprotocol.com。自定义代理直接运行你填写的程序和参数。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: _body(custom, visible)),
        ],
      ),
    );
  }

  Widget _body(List<CustomAcpAgent> custom, List<AcpRegistryAgent> visible) {
    if (_loading && custom.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      children: [
        if (custom.isNotEmpty) ...[
          const ListTile(title: Text('自定义'), dense: true),
          for (final agent in custom) _customTile(agent),
          const Divider(height: 1),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text('$_error', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          )
        else if (visible.isEmpty && custom.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('没有匹配的代理')),
          )
        else ...[
          if (visible.isNotEmpty)
            const ListTile(title: Text('ACP Registry'), dense: true),
          for (final agent in visible) _registryTile(agent),
        ],
      ],
    );
  }

  Widget _customTile(CustomAcpAgent agent) {
    final selected = agent.selectionId == widget.selectedId;
    final command = [agent.program, ...agent.args].join(' ');
    return ListTile(
      selected: selected,
      title: Text(agent.name),
      subtitle: Text(command, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) const Icon(Icons.check),
          IconButton(
            tooltip: '编辑',
            onPressed: () => _editCustom(agent),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      onTap: () => Navigator.pop(
        context,
        AcpAgentSelection(id: agent.selectionId, label: agent.name),
      ),
    );
  }

  Widget _registryTile(AcpRegistryAgent agent) {
    final selected = agent.id == widget.selectedId;
    return ListTile(
      selected: selected,
      title: Text(agent.name),
      subtitle: Text(
        '${agent.distributionLabel} · ${agent.version}\n${agent.description}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: () => Navigator.pop(
        context,
        AcpAgentSelection(id: agent.id, label: agent.name),
      ),
    );
  }
}
