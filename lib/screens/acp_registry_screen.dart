import 'package:flutter/material.dart';
import 'package:pocket_bot/services/acp_registry.dart';
import 'package:pocket_bot/services/custom_acp.dart';

/// Pick an agent from the public ACP Registry or a saved custom command.
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
    final custom = await CustomAcpStore.load();
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

  Future<void> _reloadCustom() async {
    final custom = await CustomAcpStore.load();
    if (!mounted) return;
    setState(() => _custom = custom);
  }

  Future<void> _addCustom() async {
    final created = await Navigator.push<CustomAcpAgent>(
      context,
      MaterialPageRoute(builder: (_) => const CustomAcpEditor()),
    );
    if (created == null || !mounted) {
      await _reloadCustom();
      return;
    }
    Navigator.pop(
      context,
      AcpAgentChoice(id: created.id, name: created.name),
    );
  }

  Future<void> _editCustom(CustomAcpAgent agent) async {
    await Navigator.push<CustomAcpAgent>(
      context,
      MaterialPageRoute(builder: (_) => CustomAcpEditor(initial: agent)),
    );
    await _reloadCustom();
  }

  Future<void> _deleteCustom(CustomAcpAgent agent) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除自定义 ACP'),
        content: Text('删除「${agent.name}」？已保存的命令也会去掉。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await CustomAcpStore.remove(agent.id);
    await _reloadCustom();
  }

  void _select(AcpAgentChoice choice) {
    Navigator.pop(context, choice);
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim().toLowerCase();
    final custom = _custom.where((agent) {
      if (query.isEmpty) return true;
      return agent.name.toLowerCase().contains(query) ||
          agent.command.toLowerCase().contains(query) ||
          agent.id.contains(query);
    }).toList();
    final visible = _agents.where((agent) {
      if (query.isEmpty) return true;
      return agent.name.toLowerCase().contains(query) ||
          agent.id.contains(query) ||
          agent.description.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ACP Registry'),
        actions: [
          IconButton(
            tooltip: '添加自定义 ACP',
            onPressed: _addCustom,
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
                hintText: '搜索 Cursor、Claude，或自定义命令',
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
              '列表来自 agentclientprotocol.com。也可以添加自定义 ACP：填写本机或 SSH 主机上已经安装的命令。binary 会下载到这台电脑或 SSH 主机；npx 需要 Node.js，uvx 需要 uv。',
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
        const ListTile(
          dense: true,
          title: Text('自定义 ACP'),
          subtitle: Text('命令在启动代理的那台电脑上执行'),
        ),
        ListTile(
          leading: const Icon(Icons.add_circle_outline),
          title: const Text('添加自定义 ACP'),
          subtitle: const Text('名称、可执行文件和参数'),
          onTap: _addCustom,
        ),
        for (final agent in custom) _customTile(agent),
        const Divider(height: 1),
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
                ElevatedButton(onPressed: _load, child: const Text('重试 Registry')),
              ],
            ),
          )
        else if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('没有匹配的 Registry 代理')),
          )
        else
          for (final agent in visible) _registryTile(agent),
      ],
    );
  }

  Widget _customTile(CustomAcpAgent agent) {
    final selected = agent.id == widget.selectedId;
    return ListTile(
      selected: selected,
      leading: const Icon(Icons.terminal),
      title: Text(agent.name),
      subtitle: Text(agent.commandLine, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) const Icon(Icons.check),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'edit') _editCustom(agent);
              if (value == 'delete') _deleteCustom(agent);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('编辑')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
      onTap: () => _select(AcpAgentChoice(id: agent.id, name: agent.name)),
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
      onTap: () => _select(AcpAgentChoice(id: agent.id, name: agent.name)),
    );
  }
}

class CustomAcpEditor extends StatefulWidget {
  final CustomAcpAgent? initial;

  const CustomAcpEditor({super.key, this.initial});

  @override
  State<CustomAcpEditor> createState() => _CustomAcpEditorState();
}

class _CustomAcpEditorState extends State<CustomAcpEditor> {
  late final TextEditingController _name;
  late final TextEditingController _command;
  late final TextEditingController _args;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _command = TextEditingController(text: initial?.command ?? '');
    _args = TextEditingController(text: initial?.args.join(' ') ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _command.dispose();
    _args.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final command = _command.text.trim();
    if (command.isEmpty) {
      setState(() => _error = '请填写可执行文件，例如 teshi 或 C:\\Tools\\teshi.exe');
      return;
    }
    final name = _name.text.trim().isEmpty ? command : _name.text.trim();
    final agent = CustomAcpAgent(
      id: widget.initial?.id ?? newCustomAcpId(),
      name: name,
      command: command,
      args: splitAcpArgs(_args.text),
    );
    await CustomAcpStore.upsert(agent);
    if (!mounted) return;
    Navigator.pop(context, agent);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? '编辑自定义 ACP' : '添加自定义 ACP')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '这个命令会在启动代理的那台电脑上执行。本机启动用这台电脑的 PATH；SSH 启动用远程主机的 PATH。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: 'Teshi',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _command,
            decoration: const InputDecoration(
              labelText: '命令',
              hintText: 'teshi',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _args,
            decoration: const InputDecoration(
              labelText: '参数',
              hintText: 'acp',
              helperText: '用空格分开。带空格的参数请加引号。',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: Text(editing ? '保存' : '添加并使用'),
          ),
        ],
      ),
    );
  }
}
