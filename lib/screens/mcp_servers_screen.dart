import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pocket_bot/models/mcp_server_config.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';
import 'package:pocket_bot/widgets/fluent_page.dart';

class McpServersScreen extends StatelessWidget {
  const McpServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<ConnectionManager>();
    final servers = manager.mcpServers;
    final colors = FluentColors.of(context);

    Future<void> edit([McpServerConfig? existing]) async {
      final result = await showDialog<McpServerConfig>(
        context: context,
        builder: (_) => _McpServerDialog(existing: existing),
      );
      if (result == null) return;
      final next = [...manager.mcpServers];
      final index = next.indexWhere((server) => server.id == result.id);
      if (index >= 0) {
        next[index] = result;
      } else {
        next.add(result);
      }
      await manager.saveMcpServers(next);
    }

    return FluentScreen(
      title: const Text('MCP 服务器'),
      content: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '新建或恢复会话时会把这些服务器交给代理。stdio 服务器在代理所在的机器上运行；'
            '通过 SSH 连接时，命令需要在远程主机上可用。',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: 12),
          if (servers.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text('还没有 MCP 服务器',
                      style: TextStyle(color: colors.textSecondary)),
                ),
              ),
            ),
          for (final server in servers)
            Card(
              child: ListTile(
                leading: Icon(
                  server.transport == McpTransport.stdio
                      ? Icons.terminal
                      : Icons.public,
                ),
                title: Text(server.name),
                subtitle: Text(
                  server.transport == McpTransport.stdio
                      ? [server.command, ...server.args].join(' ')
                      : '${server.transport.name.toUpperCase()} ${server.url}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => edit(server),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: server.enabled,
                      onChanged: (value) => manager.saveMcpServers([
                        for (final item in manager.mcpServers)
                          item.id == server.id
                              ? item.copyWith(enabled: value)
                              : item,
                      ]),
                    ),
                    IconButton(
                      tooltip: '删除',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => manager.saveMcpServers([
                        for (final item in manager.mcpServers)
                          if (item.id != server.id) item,
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: edit,
            icon: const Icon(Icons.add),
            label: const Text('添加 MCP 服务器'),
          ),
        ],
      ),
    );
  }
}

class _McpServerDialog extends StatefulWidget {
  const _McpServerDialog({this.existing});

  final McpServerConfig? existing;

  @override
  State<_McpServerDialog> createState() => _McpServerDialogState();
}

class _McpServerDialogState extends State<_McpServerDialog> {
  late final TextEditingController _name;
  late final TextEditingController _command;
  late final TextEditingController _args;
  late final TextEditingController _env;
  late final TextEditingController _url;
  late final TextEditingController _headers;
  late McpTransport _transport;

  @override
  void initState() {
    super.initState();
    final server = widget.existing;
    _transport = server?.transport ?? McpTransport.stdio;
    _name = TextEditingController(text: server?.name ?? '');
    _command = TextEditingController(text: server?.command ?? '');
    _args = TextEditingController(text: server?.args.join('\n') ?? '');
    _env = TextEditingController(
        text: McpKeyValue.formatLines(server?.env ?? const []));
    _url = TextEditingController(text: server?.url ?? '');
    _headers = TextEditingController(
      text: McpKeyValue.formatLines(server?.headers ?? const [],
          separator: ': '),
    );
  }

  @override
  void dispose() {
    for (final controller in [_name, _command, _args, _env, _url, _headers]) {
      controller.dispose();
    }
    super.dispose();
  }

  McpServerConfig _build() => McpServerConfig(
        id: widget.existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text.trim(),
        transport: _transport,
        enabled: widget.existing?.enabled ?? true,
        command: _command.text.trim(),
        args: _args.text
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList(),
        env: McpKeyValue.parseLines(_env.text),
        url: _url.text.trim(),
        headers: McpKeyValue.parseLines(_headers.text, separator: ':'),
      );

  @override
  Widget build(BuildContext context) {
    final stdio = _transport == McpTransport.stdio;
    return AlertDialog(
      title: Text(widget.existing == null ? '添加 MCP 服务器' : '编辑 MCP 服务器'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: '名称'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              SegmentedButton<McpTransport>(
                segments: const [
                  ButtonSegment(value: McpTransport.stdio, label: Text('stdio')),
                  ButtonSegment(value: McpTransport.http, label: Text('HTTP')),
                  ButtonSegment(value: McpTransport.sse, label: Text('SSE')),
                ],
                selected: {_transport},
                onSelectionChanged: (value) =>
                    setState(() => _transport = value.first),
              ),
              const SizedBox(height: 12),
              if (stdio) ...[
                TextField(
                  controller: _command,
                  decoration: const InputDecoration(
                    labelText: '命令',
                    hintText: 'npx',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _args,
                  decoration: const InputDecoration(
                    labelText: '参数（每行一个）',
                    hintText: '-y\n@modelcontextprotocol/server-filesystem',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _env,
                  decoration: const InputDecoration(
                    labelText: '环境变量（每行 KEY=value）',
                  ),
                  maxLines: 3,
                ),
              ] else ...[
                TextField(
                  controller: _url,
                  decoration: const InputDecoration(
                    labelText: 'URL',
                    hintText: 'https://example.com/mcp',
                  ),
                  keyboardType: TextInputType.url,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _headers,
                  decoration: const InputDecoration(
                    labelText: '请求头（每行 Name: value）',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                Text(
                  '只有声明支持 ${_transport.name.toUpperCase()} MCP 的代理才会收到这个服务器。',
                  style: TextStyle(
                    fontSize: 12,
                    color: FluentColors.of(context).textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _build().isValid
              ? () => Navigator.pop(context, _build())
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
