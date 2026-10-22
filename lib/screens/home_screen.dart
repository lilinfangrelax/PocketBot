import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/screens/acp_registry_screen.dart';
import 'package:pocket_bot/screens/chat_screen.dart';
import 'package:pocket_bot/screens/remote_directory_picker.dart';
import 'package:pocket_bot/screens/settings_screen.dart';
import 'package:pocket_bot/services/acp_registry.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/cursor_agent.dart';
import 'package:pocket_bot/services/ssh_host_keys.dart';
import 'package:pocket_bot/services/ssh_host_pool.dart';
import 'package:pocket_bot/services/ssh_remote_session.dart';
import 'package:pocket_bot/services/websocket_service.dart' as ws;
import 'package:pocket_bot/theme/fluent_theme.dart';
import 'package:pocket_bot/widgets/fluent_page.dart';
import 'package:pocket_bot/widgets/workspace_picker.dart';

typedef ConnectionState = ws.ConnectionState;

/// 首页 - 从 ACP Registry 选择代理，本机或 SSH 启动。
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
  final TextEditingController _passphraseController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _workingDirectoryController =
      TextEditingController();

  String _manualHost = '';
  int _manualPort = 22;
  String _manualUsername = '';
  String _manualToken = '';
  String _manualPrivateKey = '';
  String _manualPassphrase = '';
  String _manualName = '';
  String _sshWorkingDirectory = '.';
  String _agentId = 'cursor';
  String _agentLabel = 'Cursor';

  bool get _canLaunchLocal =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    _workingDirectoryController.text =
        _canLaunchLocal ? CursorAgent.defaultWorkingDirectory() : '.';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ConnectionManager>().checkGatewaysStatus();
    });
    _loadSelectedAgent();
  }

  Future<void> _loadSelectedAgent() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('acp_agent_id') ?? 'cursor';
    final label = prefs.getString('acp_agent_label') ?? 'Cursor';
    if (!mounted) return;
    setState(() {
      _agentId = id;
      _agentLabel = label;
    });
  }

  Future<void> _pickAgent() async {
    final picked = await Navigator.push<AcpRegistryAgent>(
      context,
      MaterialPageRoute(
        builder: (_) => AcpRegistryScreen(selectedId: _agentId),
      ),
    );
    if (picked == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('acp_agent_id', picked.id);
    await prefs.setString('acp_agent_label', picked.name);
    if (!mounted) return;
    setState(() {
      _agentId = picked.id;
      _agentLabel = picked.name;
    });
  }

  GatewayInfo _withSelectedAgent(GatewayInfo gateway) {
    if (gateway.agentId.isNotEmpty) return gateway;
    return gateway.copyWith(agentId: _agentId, agentLabel: _agentLabel);
  }

  Widget _buildAgentPicker() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.smart_toy_outlined),
        title: Text(_agentLabel),
        subtitle: const Text('ACP Registry，点按更换代理'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _pickAgent,
      ),
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _tokenController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
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
        return FluentScreen(
          title: const Text('PocketBot'),
          commands: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              fluent.Tooltip(
                message: '刷新状态',
                child: fluent.IconButton(
                  icon: const Icon(fluent.WindowsIcons.refresh),
                  onPressed: manager.isCheckingStatus
                      ? null
                      : () => manager.checkGatewaysStatus(),
                ),
              ),
              fluent.IconButton(
                icon: const Icon(fluent.WindowsIcons.settings),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
            ],
          ),
          content: _buildBody(manager),
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
          color: FluentColors.of(context).success,
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
              style: TextButton.styleFrom(
                  foregroundColor: FluentColors.of(context).danger),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildGatewayList(),
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
          color: FluentColors.of(context).info,
          text: '正在启动 ${gateway?.name ?? 'Agent'}...',
          subText: gateway?.displayLabel,
          showProgress: true,
        ),
        const SizedBox(height: 16),
        _buildGatewayList(),
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
          color: FluentColors.of(context).danger,
          text: '连接失败',
          subText: gateway?.displayLabel,
        ),
        const SizedBox(height: 8),
        Card(
          color: FluentColors.of(context).dangerSurface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 18, color: FluentColors.of(context).danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _simplifyError(manager.errorMessage),
                    style: TextStyle(
                      color: FluentColors.of(context).danger,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildGatewayList(),
        _buildAgentPicker(),
        const SizedBox(height: 16),
        _buildLaunchLocal(manager),
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
          color: FluentColors.of(context).textSecondary,
          text: '未连接',
          subText: '从 ACP Registry 选择代理，本机或 SSH 启动',
        ),
        const SizedBox(height: 16),
        _buildGatewayList(),
        _buildAgentPicker(),
        const SizedBox(height: 16),
        _buildLaunchLocal(manager),
        const SizedBox(height: 16),
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
            style: TextStyle(color: FluentColors.of(context).textSecondary),
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
              '本机 $_agentLabel',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '在这台电脑上启动所选 ACP 代理。Cursor 需要先运行 agent login。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: FluentColors.of(context).textSecondary,
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
              child: fluent.FilledButton(
                onPressed: manager.state == ConnectionState.connecting
                    ? null
                    : () => manager.connectTo(GatewayInfo.local(
                          name: _agentLabel,
                          workingDirectory: _workingDirectoryController.text,
                          agentId: _agentId,
                          agentLabel: _agentLabel,
                        )),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.play_arrow, size: 16),
                    const SizedBox(width: 8),
                    Text('启动 $_agentLabel'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _simplifyError(String? raw) {
    if (raw == null) return '请检查配置后重试';
    final error = raw.replaceFirst(RegExp(r'^(Exception: )+'), '');

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
        case 'AGENT_EXIT':
          return errorMessage.isEmpty ? '远程 Agent 已退出' : errorMessage;
        case 'HELPER_INSTALL_FAILED':
          return errorMessage.isEmpty ? '远程服务安装失败' : errorMessage;
        case 'REGISTRY_UNAVAILABLE':
          return errorMessage.isEmpty ? '无法获取 ACP Registry' : errorMessage;
        case 'AGENT_NOT_IN_REGISTRY':
          return errorMessage.isEmpty ? 'Registry 里没有这个代理' : errorMessage;
        case 'AGENT_UNSUPPORTED_PLATFORM':
          return errorMessage.isEmpty ? '这个代理不支持当前系统' : errorMessage;
        case 'CONNECTION_FAILED':
          return errorMessage.isEmpty ? '连接失败' : errorMessage;
        case 'HOST_KEY_REJECTED':
          return errorMessage.isEmpty ? '主机密钥未被信任' : errorMessage;
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
    final colors = FluentColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(FluentColors.overlayRadius),
        border: Border.all(color: colors.stroke),
      ),
      child: Row(
        children: [
          if (showProgress)
            SizedBox(
              width: 20,
              height: 20,
              child: fluent.ProgressRing(strokeWidth: 2, activeColor: color),
            )
          else
            Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subText,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (actions != null) ...actions,
        ],
      ),
    );
  }

  /// Watches the manager itself: the page body only rebuilds on connection
  /// state, but saved hosts and their online status change independently.
  Widget _buildGatewayList() {
    return Consumer<ConnectionManager>(
      builder: (context, manager, _) => _buildGatewayColumn(manager),
    );
  }

  Widget _buildGatewayColumn(ConnectionManager manager) {
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
        FluentSectionHeader(_gatewayListTitle(manager, allGateways)),
        ...allGateways.map((gw) {
          final isConnected = manager.gateway != null &&
              manager.gateway!.connectionId == gw.connectionId;
          return _GatewayListTile(
            gateway: gw,
            isConnected: isConnected,
            hostState: manager.hostState(gw),
            isConnecting: manager.state == ConnectionState.connecting &&
                manager.gateway?.connectionId == gw.connectionId,
            onLogin: () => _loginHost(manager, gw),
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
        const SizedBox(height: 8),
      ],
    );
  }

  String _gatewayListTitle(
    ConnectionManager manager,
    List<GatewayInfo> gateways,
  ) {
    final ssh = gateways
        .where((gw) => gw.kind == AgentTransportKind.ssh)
        .map((gw) => gw.hostId)
        .toSet();
    if (ssh.isEmpty) return '已保存的连接';
    final online = gateways
        .where((gw) =>
            gw.kind == AgentTransportKind.ssh && manager.hostState(gw).isOnline)
        .map((gw) => gw.hostId)
        .toSet();
    return '已保存的连接 · SSH 在线 ${online.length}/${ssh.length}';
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
              '登录后会把 pocketbot-remote 装到远程的 ~/.pocketbot，再启动 $_agentLabel。断线后代理进程还在，重连会接回去。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: FluentColors.of(context).textSecondary,
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
            const SizedBox(height: 8),
            TextFormField(
              controller: _passphraseController,
              decoration: const InputDecoration(
                labelText: '私钥密码（私钥加密时填写）',
                isDense: true,
              ),
              obscureText: true,
              onChanged: (value) => _manualPassphrase = value,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: fluent.FilledButton(
                onPressed: _manualHost.isNotEmpty && _manualUsername.isNotEmpty
                    ? () => _loginHost(manager, _buildSshTarget())
                    : null,
                child: const Text('保存并登录'),
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
    final target = _withSelectedAgent(existing ?? _buildSshTarget());
    if (target.requiresAuth) {
      showAppNotice(context, '请填写 SSH 密码或私钥');
      return;
    }

    var loadingShown = true;
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

    SshRemoteSession? session;
    try {
      session = await manager.browseHost(target);
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
      await session.close();
      if (cwd == null || cwd.trim().isEmpty) return;

      await manager.connectTo(target.copyWith(workingDirectory: cwd));
    } catch (error) {
      await session?.close();
      if (!mounted) return;
      if (loadingShown) Navigator.pop(context);
      showAppNotice(context, _simplifyError(error.toString()));
    }
  }

  /// Saves [target] and logs in. Picking a folder and starting an agent are
  /// separate steps.
  Future<void> _loginHost(ConnectionManager manager, GatewayInfo target) async {
    if (target.kind != AgentTransportKind.ssh) {
      await manager.checkGatewaysStatus();
      return;
    }
    if (target.requiresAuth) {
      showAppNotice(context, '请填写 SSH 密码或私钥');
      return;
    }
    await manager.addSavedGateway(target);
    final online = await manager.hosts.check(target);
    if (!mounted) return;
    final state = manager.hostState(target);
    showAppNotice(
      context,
      online
          ? '${target.hostLabel} 已在线'
          : _simplifyError(state.error ?? '无法登录 ${target.hostLabel}'),
    );
  }

  GatewayInfo _buildSshTarget() {
    return GatewayInfo.ssh(
      host: _manualHost,
      port: _manualPort,
      username: _manualUsername,
      password: _manualToken,
      privateKey: _manualPrivateKey,
      keyPassphrase: _manualPassphrase,
      name: _manualName.isNotEmpty ? _manualName : 'SSH 远程',
      workingDirectory:
          _sshWorkingDirectory.isEmpty ? '.' : _sshWorkingDirectory,
    ).copyWith(agentId: _agentId, agentLabel: _agentLabel);
  }

  void _showConnectionDialog(BuildContext context, GatewayInfo gateway) {
    if (gateway.kind == AgentTransportKind.local) {
      _workingDirectoryController.text = gateway.workingDirectory;
      context.read<ConnectionManager>().connectTo(_withSelectedAgent(gateway));
      return;
    }
    _hostController.text = gateway.host;
    _portController.text = gateway.port.toString();
    _usernameController.text = gateway.username;
    _tokenController.text = gateway.token;
    _privateKeyController.text = gateway.privateKey;
    _passphraseController.text = gateway.keyPassphrase;
    _nameController.text = gateway.name;
    _manualHost = gateway.host;
    _manualPort = gateway.port;
    _manualUsername = gateway.username;
    _manualToken = gateway.token;
    _manualPrivateKey = gateway.privateKey;
    _manualPassphrase = gateway.keyPassphrase;
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
                  onChanged: (value) => _manualPort = int.tryParse(value) ?? 22,
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
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passphraseController,
                  decoration:
                      const InputDecoration(labelText: '私钥密码（可选）'),
                  obscureText: true,
                  onChanged: (value) => _manualPassphrase = value,
                ),
                if (isEditing) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.key_off_outlined, size: 18),
                      label: const Text('清除已记住的主机密钥'),
                      onPressed: () async {
                        await SshHostKeys.forget(
                          existingGateway.host,
                          existingGateway.port,
                        );
                        if (context.mounted) {
                          showAppNotice(context, '下次连接时会重新确认主机密钥');
                        }
                      },
                    ),
                  ),
                ],
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
              onPressed: _manualHost.isNotEmpty && _manualUsername.isNotEmpty
                  ? () {
                      final manager = context.read<ConnectionManager>();
                      final gateway = _buildSshTarget();
                      Navigator.pop(context);
                      () async {
                        if (isEditing) {
                          await manager.removeSavedGateway(existingGateway);
                        }
                        if (!mounted) return;
                        await _loginHost(manager, gateway);
                      }();
                    }
                  : null,
              child: Text(isEditing ? '保存并登录' : '添加并登录'),
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
  final HostState hostState;
  final bool isConnecting;
  final VoidCallback onLogin;
  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GatewayListTile({
    required this.gateway,
    required this.isConnected,
    required this.hostState,
    required this.isConnecting,
    required this.onLogin,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
  });

  bool get _needsLogin =>
      gateway.kind == AgentTransportKind.ssh && !hostState.isOnline;

  @override
  Widget build(BuildContext context) {
    final colors = FluentColors.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(FluentColors.overlayRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              HostStatusDot(state: hostState),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.accentSubtle,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  gateway.kind == AgentTransportKind.local
                      ? Icons.computer
                      : Icons.lan,
                  size: 18,
                  color: colors.accent,
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
                            color: colors.textSecondary,
                          ),
                    ),
                    Text(
                      hostStatusText(hostState),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: hostState.status == HostStatus.offline
                                ? colors.danger
                                : colors.textSecondary,
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
                    color: colors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(FluentColors.radius),
                  ),
                  child: Text(
                    '已连接',
                    style: TextStyle(fontSize: 12, color: colors.success),
                  ),
                )
              else if (isConnecting)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: fluent.ProgressRing(strokeWidth: 2),
                ),
              const SizedBox(width: 8),
              if (!isConnected && !isConnecting && _needsLogin)
                TextButton(
                  onPressed:
                      hostState.status == HostStatus.checking ? null : onLogin,
                  child: const Text('登录'),
                )
              else if (!isConnected && !isConnecting)
                TextButton(
                  onPressed: onConnect,
                  child: Text(
                    gateway.kind == AgentTransportKind.ssh ? '选目录启动' : '启动',
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onDelete,
                color: colors.textSecondary,
                tooltip: '删除',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
