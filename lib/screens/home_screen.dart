import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/screens/chat_screen.dart';
import 'package:pocket_bot/screens/remote_directory_picker.dart';
import 'package:pocket_bot/screens/settings_screen.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/cursor_agent.dart';
import 'package:pocket_bot/services/ssh_remote_session.dart';
import 'package:pocket_bot/services/websocket_service.dart' as ws;

typedef ConnectionState = ws.ConnectionState;

/// 首页 - 本地 / SSH 启动 Cursor Agent
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController =
      TextEditingController(text: '22');
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _privateKeyController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _workingDirectoryController =
      TextEditingController();

  String _manualHost = '';
  int _manualPort = 22;
  String _manualUsername = '';
  String _manualToken = '';
  String _manualPrivateKey = '';
  String _manualName = '';
  String _sshWorkingDirectory = '.';

  bool get _canLaunchLocal =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    _workingDirectoryController.text =
        _canLaunchLocal ? CursorAgent.defaultWorkingDirectory() : '.';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ConnectionManager>().checkGatewaysStatus();
    });
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _tokenController.dispose();
    _privateKeyController.dispose();
    _nameController.dispose();
    _workingDirectoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<ConnectionManager, ConnectionState>(
      selector: (_, manager) => manager.state,
      builder: (context, state, child) {
        final manager = context.read<ConnectionManager>();
        return Scaffold(
          appBar: AppBar(
            title: const Text('PocketBot'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新状态',
                onPressed: manager.isCheckingStatus
                    ? null
                    : () => manager.checkGatewaysStatus(),
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
            ],
          ),
          body: _buildBody(manager),
        );
      },
    );
  }

  Widget _buildBody(ConnectionManager manager) {
    switch (manager.state) {
      case ConnectionState.connected:
        return _buildConnectedView(manager);
      case ConnectionState.connecting:
        return _buildConnectingView(manager);
      case ConnectionState.error:
        return _buildErrorView(manager);
      case ConnectionState.disconnected:
        return _buildDisconnectedView(manager);
    }
  }

  Widget _buildConnectedView(ConnectionManager manager) {
    final gateway = manager.gateway;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatusBar(
          icon: Icons.check_circle,
          color: Colors.green,
          text: '已连接到 ${gateway?.name ?? 'Agent'}',
          subText: gateway?.displayLabel,
          actions: [
            TextButton.icon(
              onPressed: () {
                if (manager.wsService.activeSessionKey == null) {
                  manager.wsService.createNewSession();
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChatScreen()),
                );
              },
              icon: const Icon(Icons.chat, size: 18),
              label: const Text('开始聊天'),
            ),
            TextButton.icon(
              onPressed: () => manager.disconnect(),
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text('断开'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildGatewayList(manager),
      ],
    );
  }

  Widget _buildConnectingView(ConnectionManager manager) {
    final gateway = manager.gateway;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatusBar(
          icon: Icons.sync,
          color: Colors.blue,
          text: '正在启动 ${gateway?.name ?? 'Agent'}...',
          subText: gateway?.displayLabel,
          showProgress: true,
        ),
        const SizedBox(height: 24),
        _buildGatewayList(manager),
      ],
    );
  }

  Widget _buildErrorView(ConnectionManager manager) {
    final gateway = manager.gateway;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatusBar(
          icon: Icons.error_outline,
          color: Colors.red,
          text: '连接失败',
          subText: gateway?.displayLabel,
        ),
        const SizedBox(height: 8),
        Card(
          color: Colors.red.shade50,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _simplifyError(manager.errorMessage),
                    style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildLaunchLocal(manager),
        const SizedBox(height: 16),
        _buildGatewayList(manager),
        const SizedBox(height: 16),
        _buildSshConnection(manager),
      ],
    );
  }

  Widget _buildDisconnectedView(ConnectionManager manager) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatusBar(
          icon: Icons.computer,
          color: Colors.grey,
          text: '未连接',
          subText: '本机或 SSH 启动 Cursor Agent（agent acp）',
        ),
        const SizedBox(height: 24),
        _buildLaunchLocal(manager),
        const SizedBox(height: 24),
        _buildGatewayList(manager),
        const SizedBox(height: 24),
        _buildSshConnection(manager),
      ],
    );
  }

  Widget _buildLaunchLocal(ConnectionManager manager) {
    if (!_canLaunchLocal) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '本机 Cursor Agent 仅支持桌面端。手机请用下方 SSH 连接到已安装 agent 的电脑。',
            style: TextStyle(color: Colors.grey[700]),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本机 Cursor Agent',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '在这台电脑上启动 `agent acp`，通过 stdio 会话。请先运行 agent login。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _workingDirectoryController,
              decoration: const InputDecoration(
                labelText: '工作目录',
                hintText: r'C:\Dev\project 或 /home/user/project',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: manager.state == ConnectionState.connecting
                    ? null
                    : () => manager.connectLocal(
                          workingDirectory: _workingDirectoryController.text,
                        ),
                icon: const Icon(Icons.play_arrow),
                label: const Text('启动本机 Agent'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _simplifyError(String? error) {
    if (error == null) return '请检查配置后重试';

    if (error.contains(':')) {
      final parts = error.split(':');
      final errorType = parts[0].toUpperCase();
      final errorMessage = parts.length > 1 ? parts.sublist(1).join(':') : '';

      switch (errorType) {
        case 'AUTH_FAILED':
          return errorMessage.isEmpty
              ? '认证失败。本机请运行 agent login；SSH 请检查用户名、密码或私钥'
              : errorMessage;
        case 'PERMISSION_DENIED':
          return '没有权限访问此 Agent';
        case 'CONNECTION_REFUSED':
          return '连接被拒绝，请检查 SSH 主机和端口';
        case 'CONNECTION_TIMEOUT':
          return '连接超时，请确认主机在线且已安装 Cursor Agent';
        case 'CONNECTION_ERROR':
          return '连接失败，请检查网络或 Agent 是否已退出';
        case 'CONNECTION_CLOSED':
          return '连接意外断开，Agent 可能已关闭';
        case 'CURSOR_AGENT_NOT_FOUND':
          return '找不到 Cursor Agent。请安装 Cursor 并确保 `agent` 在 PATH 中，然后运行 agent login。';
        case 'AGENT_SPAWN_FAILED':
          return errorMessage.isEmpty ? '无法启动本机 Agent' : errorMessage;
        case 'CONNECTION_FAILED':
          return errorMessage.isEmpty ? '连接失败' : errorMessage;
        default:
          break;
      }
    }

    final lowerError = error.toLowerCase();
    if (lowerError.contains('timeout') || lowerError.contains('超时')) {
      return '连接超时';
    }
    if (lowerError.contains('refused') || lowerError.contains('拒绝')) {
      return '连接被拒绝';
    }
    if (lowerError.contains('auth') || lowerError.contains('认证')) {
      return '认证失败，请运行 agent login 或检查 SSH 凭据';
    }
    return '连接失败: $error';
  }

  Widget _buildStatusBar({
    required IconData icon,
    required Color color,
    required String text,
    String? subText,
    List<Widget>? actions,
    bool showProgress = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          if (showProgress)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text,
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.w500)),
                if (subText != null)
                  Text(subText,
                      style: TextStyle(
                          color: color.withOpacity(0.7), fontSize: 12)),
              ],
            ),
          ),
          if (actions != null) ...actions,
        ],
      ),
    );
  }

  Widget _buildGatewayList(ConnectionManager manager) {
    final saved = manager.savedGateways;
    final allGateways = <GatewayInfo>[];

    if (manager.gateway != null) {
      allGateways.add(manager.gateway!);
    }

    for (final gw in saved) {
      if (manager.gateway == null ||
          gw.connectionId != manager.gateway!.connectionId) {
        allGateways.add(gw);
      }
    }

    if (allGateways.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已保存的连接',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ...allGateways.map((gw) {
          final isConnected = manager.gateway != null &&
              manager.gateway!.connectionId == gw.connectionId;
          final status = manager.getGatewayStatus(gw);
          final isOnline = status?.isOnline ?? false;

          return _GatewayListTile(
            gateway: gw,
            isConnected: isConnected,
            isOnline: isOnline,
            isConnecting: manager.state == ConnectionState.connecting &&
                manager.gateway?.connectionId == gw.connectionId,
            onConnect: () {
              if (gw.kind == AgentTransportKind.ssh) {
                _startSshFlow(manager, existing: gw);
              } else {
                manager.connectTo(gw);
              }
            },
            onEdit: () => _showConnectionDialog(context, gw),
            onDelete: () => _confirmDeleteGateway(context, manager, gw),
          );
        }),
      ],
    );
  }

  Widget _buildSshConnection(ConnectionManager manager) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SSH 远程 Agent',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '登录远程主机后选择工作目录，再启动 `agent acp`。协议仍是 stdio JSON-RPC。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '名称（可选）',
                hintText: '家里的电脑',
                isDense: true,
              ),
              onChanged: (value) => _manualName = value.trim(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _hostController,
                    decoration: const InputDecoration(
                      labelText: '主机',
                      hintText: '192.168.1.100',
                      isDense: true,
                    ),
                    onChanged: (value) {
                      _manualHost = value.trim();
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: _portController,
                    decoration: const InputDecoration(
                      labelText: '端口',
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) =>
                        _manualPort = int.tryParse(value) ?? 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '用户名',
                hintText: 'ubuntu',
                isDense: true,
              ),
              onChanged: (value) {
                _manualUsername = value.trim();
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: '密码（可选）',
                isDense: true,
              ),
              obscureText: true,
              onChanged: (value) => _manualToken = value,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _privateKeyController,
              decoration: const InputDecoration(
                labelText: '私钥 PEM（可选）',
                hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                isDense: true,
              ),
              maxLines: 4,
              onChanged: (value) => _manualPrivateKey = value,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _manualHost.isNotEmpty && _manualUsername.isNotEmpty
                    ? () => _startSshFlow(manager)
                    : null,
                child: const Text('登录并选择目录'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startSshFlow(
    ConnectionManager manager, {
    GatewayInfo? existing,
  }) async {
    final target = existing ?? _buildSshTarget();
    if (target.requiresAuth) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写 SSH 密码或私钥')),
      );
      return;
    }

    var loadingShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('正在登录远程主机...')),
          ],
        ),
      ),
    );

    SshRemoteSession? session;
    try {
      session = await SshRemoteSession.connect(target);
      if (!mounted) {
        await session.close();
        return;
      }
      Navigator.pop(context);
      loadingShown = false;

      final cwd = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => RemoteDirectoryPicker(
            source: session!,
            hostLabel: '${target.username}@${target.host}:${target.port}',
            initialPath: target.workingDirectory,
          ),
        ),
      );
      if (cwd == null || cwd.trim().isEmpty) {
        await session.close();
        return;
      }

      final updated = target.copyWith(workingDirectory: cwd);
      await manager.connectWithSshSession(updated, session);
    } catch (error) {
      await session?.close();
      if (!mounted) return;
      if (loadingShown) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_simplifyError(error.toString()))),
      );
    }
  }

  GatewayInfo _buildSshTarget() {
    return GatewayInfo.ssh(
      host: _manualHost,
      port: _manualPort,
      username: _manualUsername,
      password: _manualToken,
      privateKey: _manualPrivateKey,
      name: _manualName.isNotEmpty ? _manualName : 'SSH 远程',
      workingDirectory:
          _sshWorkingDirectory.isEmpty ? '.' : _sshWorkingDirectory,
    );
  }

  void _showConnectionDialog(BuildContext context, GatewayInfo gateway) {
    if (gateway.kind == AgentTransportKind.local) {
      _workingDirectoryController.text = gateway.workingDirectory;
      context.read<ConnectionManager>().connectTo(gateway);
      return;
    }
    _hostController.text = gateway.host;
    _portController.text = gateway.port.toString();
    _usernameController.text = gateway.username;
    _tokenController.text = gateway.token;
    _privateKeyController.text = gateway.privateKey;
    _nameController.text = gateway.name;
    _manualHost = gateway.host;
    _manualPort = gateway.port;
    _manualUsername = gateway.username;
    _manualToken = gateway.token;
    _manualPrivateKey = gateway.privateKey;
    _manualName = gateway.name;
    _sshWorkingDirectory = gateway.workingDirectory;

    showDialog(
      context: context,
      builder: (_) => _buildConnectionDialog(context, gateway),
    );
  }

  void _confirmDeleteGateway(
      BuildContext context, ConnectionManager manager, GatewayInfo gateway) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除连接'),
        content: Text('确定要删除 "${gateway.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              manager.removeSavedGateway(gateway);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionDialog(
      BuildContext context, GatewayInfo? existingGateway) {
    final isEditing = existingGateway != null;

    return StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: Text(isEditing ? '编辑 SSH 连接' : '添加 SSH 连接'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    hintText: '家里的电脑',
                  ),
                  onChanged: (value) => _manualName = value.trim(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _hostController,
                  decoration: const InputDecoration(
                    labelText: '主机',
                    hintText: '192.168.1.100',
                  ),
                  onChanged: (value) {
                    _manualHost = value.trim();
                    setDialogState(() {});
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _portController,
                  decoration: const InputDecoration(labelText: '端口'),
                  keyboardType: TextInputType.number,
                  onChanged: (value) =>
                      _manualPort = int.tryParse(value) ?? 22,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: '用户名'),
                  onChanged: (value) {
                    _manualUsername = value.trim();
                    setDialogState(() {});
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tokenController,
                  decoration: const InputDecoration(labelText: '密码（可选）'),
                  obscureText: true,
                  onChanged: (value) => _manualToken = value,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _privateKeyController,
                  decoration: const InputDecoration(labelText: '私钥 PEM（可选）'),
                  maxLines: 4,
                  onChanged: (value) => _manualPrivateKey = value,
                ),
              ],
            ),
          ),
          actions: [
            if (isEditing)
              TextButton(
                onPressed: () {
                  final manager = context.read<ConnectionManager>();
                  if (manager.gateway?.connectionId ==
                      existingGateway.connectionId) {
                    manager.disconnect();
                  }
                  manager.removeSavedGateway(existingGateway);
                  Navigator.pop(context);
                },
                child: const Text('删除', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed:
                  _manualHost.isNotEmpty && _manualUsername.isNotEmpty
                      ? () {
                          final manager = context.read<ConnectionManager>();
                          final gateway = _buildSshTarget();
                          if (isEditing) {
                            manager.removeSavedGateway(existingGateway);
                          }
                          manager.addSavedGateway(gateway);
                          Navigator.pop(context);
                          _startSshFlow(manager, existing: gateway);
                        }
                      : null,
              child: Text(isEditing ? '保存并选择目录' : '添加并选择目录'),
            ),
          ],
        );
      },
    );
  }
}

class _GatewayListTile extends StatelessWidget {
  final GatewayInfo gateway;
  final bool isConnected;
  final bool isOnline;
  final bool isConnecting;
  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GatewayListTile({
    required this.gateway,
    required this.isConnected,
    required this.isOnline,
    required this.isConnecting,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isConnected
                      ? Colors.green
                      : (isOnline ? Colors.blue : Colors.grey),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  gateway.kind == AgentTransportKind.local
                      ? Icons.computer
                      : Icons.lan,
                  size: 18,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gateway.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      gateway.displayLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              ),
              if (isConnected)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '已连接',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                )
              else if (isConnecting)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              const SizedBox(width: 8),
              if (!isConnected && !isConnecting)
                TextButton(
                  onPressed: onConnect,
                  child: const Text('连接'),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onDelete,
                color: Colors.grey,
                tooltip: '删除',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
