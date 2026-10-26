import 'package:flutter/material.dart';
import 'package:pocket_bot/services/custom_acp_agent.dart';

/// Create or replace a custom ACP command.
class CustomAcpAgentScreen extends StatefulWidget {
  const CustomAcpAgentScreen({super.key, this.initial});

  final CustomAcpAgent? initial;

  @override
  State<CustomAcpAgentScreen> createState() => _CustomAcpAgentScreenState();
}

class _CustomAcpAgentScreenState extends State<CustomAcpAgentScreen> {
  late final TextEditingController _name;
  late final TextEditingController _id;
  late final TextEditingController _program;
  late final TextEditingController _args;
  late final TextEditingController _env;
  var _idEdited = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _id = TextEditingController(text: initial?.id ?? '');
    _program = TextEditingController(text: initial?.program ?? '');
    _args = TextEditingController(text: initial?.args.join('\n') ?? '');
    _env = TextEditingController(
      text: initial == null
          ? ''
          : [
              for (final entry in initial.env.entries)
                '${entry.key}=${entry.value}',
            ].join('\n'),
    );
    _idEdited = initial != null;
  }

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    _program.dispose();
    _args.dispose();
    _env.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = _id.text.trim().isEmpty
        ? suggestCustomAcpId(_name.text)
        : _id.text.trim();
    Map<String, String> env;
    try {
      env = parseCustomAcpEnv(_env.text);
    } on FormatException catch (error) {
      _show(error.message);
      return;
    }
    final agent = CustomAcpAgent(
      id: id,
      name: _name.text.trim(),
      program: _program.text.trim(),
      args: parseCustomAcpArgs(_args.text),
      env: env,
    );
    final error = validateCustomAcpAgent(agent);
    if (error != null) {
      _show(error);
      return;
    }
    setState(() => _saving = true);
    try {
      await CustomAcpCatalog.upsert(agent);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      _show('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final initial = widget.initial;
    if (initial == null) return;
    await CustomAcpCatalog.remove(initial.id);
    if (mounted) Navigator.pop(context, true);
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '编辑自定义代理' : '添加自定义代理'),
        actions: [
          if (editing)
            IconButton(
              tooltip: '删除',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '直接启动本机或 SSH 主机上的程序，不从 ACP Registry 下载。参数每行一个，例如 chrys 的 acp。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '名称',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              if (_idEdited) return;
              _id.text = suggestCustomAcpId(value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _id,
            decoration: const InputDecoration(
              labelText: 'ID',
              helperText: '字母、数字、短横线和下划线',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _idEdited = true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _program,
            decoration: const InputDecoration(
              labelText: '程序',
              hintText: r'chrys 或 C:\Tools\chrys.exe',
              helperText: 'PATH 上的名字，或可执行文件的完整路径',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _args,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: '参数',
              hintText: 'acp',
              helperText: '每行一个参数，不会按空格拆开',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _env,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: '环境变量',
              hintText: 'KEY=value',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '正在保存...' : '保存'),
          ),
        ],
      ),
    );
  }
}
