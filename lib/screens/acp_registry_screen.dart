import 'package:flutter/material.dart';
import 'package:pocket_bot/services/acp_registry.dart';

/// Pick an agent from the public ACP Registry.
class AcpRegistryScreen extends StatefulWidget {
  final String? selectedId;

  const AcpRegistryScreen({super.key, this.selectedId});

  @override
  State<AcpRegistryScreen> createState() => _AcpRegistryScreenState();
}

class _AcpRegistryScreenState extends State<AcpRegistryScreen> {
  final TextEditingController _query = TextEditingController();
  List<AcpRegistryAgent> _agents = const [];
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
    try {
      final agents = await AcpRegistryCatalog.load();
      if (!mounted) return;
      setState(() {
        _agents = agents;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim().toLowerCase();
    final visible = _agents.where((agent) {
      if (query.isEmpty) return true;
      return agent.name.toLowerCase().contains(query) ||
          agent.id.contains(query) ||
          agent.description.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('ACP Registry')),
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
              '列表来自 agentclientprotocol.com。binary 会下载到这台电脑或 SSH 主机；npx 需要 Node.js，uvx 需要 uv。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: _body(visible)),
        ],
      ),
    );
  }

  Widget _body(List<AcpRegistryAgent> visible) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (visible.isEmpty) {
      return const Center(child: Text('没有匹配的代理'));
    }
    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final agent = visible[index];
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
          onTap: () => Navigator.pop(context, agent),
        );
      },
    );
  }
}
