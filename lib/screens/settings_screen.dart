import 'dart:convert';
import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/config/user_config.dart';
import 'package:pocket_bot/main.dart';
import 'package:pocket_bot/screens/mcp_servers_screen.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/utils/logger.dart';
import 'package:pocket_bot/utils/version_utils.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';
import 'package:pocket_bot/widgets/fluent_page.dart';
import 'package:pocket_bot/widgets/update_settings_card.dart';

/// Settings screen
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _userAvatarBase64;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadUserAvatar();
  }

  Future<void> _loadUserAvatar() async {
    final avatar = await UserConfigStorage.getUserAvatar();
    if (mounted) {
      setState(() {
        _userAvatarBase64 = avatar;
      });
    }
  }

  /// Pick and save user avatar
  Future<void> _pickAndSaveAvatar() async {
    try {
      // Request photo library permission
      if (Platform.isIOS) {
        final status = await Permission.photos.request();
        if (status.isDenied || status.isPermanentlyDenied) {
          _showSnackBar(context, '请在系统设置中允许访问相册');
          return;
        }
      }

      // Pick image
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image == null) {
        Logger.info('[Settings] Avatar selection cancelled');
        return;
      }

      // Read and encode image
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Save to storage
      await UserConfigStorage.saveUserAvatar(base64Image);

      // Notify other screens to refresh
      context.read<UserConfigProvider>().notifyConfigChanged();

      if (mounted) {
        setState(() {
          _userAvatarBase64 = base64Image;
        });
        _showSnackBar(context, '头像已更新');
      }

      Logger.info('[Settings] Avatar saved (${bytes.length} bytes)');
    } catch (e) {
      Logger.error('[Settings] Error saving avatar: $e');
      _showSnackBar(context, '保存头像失败');
    }
  }

  /// Remove user avatar
  Future<void> _removeAvatar() async {
    await UserConfigStorage.clearUserAvatar();

    // Notify other screens to refresh
    context.read<UserConfigProvider>().notifyConfigChanged();

    if (mounted) {
      setState(() {
        _userAvatarBase64 = null;
      });
      _showSnackBar(context, '头像已移除');
    }
  }

  /// Show avatar options dialog
  void _showAvatarOptions() {
    fluent.showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => fluent.ContentDialog(
        title: const Text('头像'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_userAvatarBase64 != null) ...[
              SizedBox(
                width: 120,
                height: 120,
                child: ClipOval(
                  child: Image.memory(
                    base64Decode(_userAvatarBase64!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              fluent.FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  _pickAndSaveAvatar();
                },
                child: const Text('更换照片'),
              ),
              const SizedBox(height: 8),
              fluent.Button(
                onPressed: () {
                  Navigator.pop(context);
                  _showRemoveConfirmDialog();
                },
                child: Text(
                  '移除',
                  style: TextStyle(color: FluentColors.of(context).danger),
                ),
              ),
            ] else ...[
              SizedBox(
                width: 100,
                height: 100,
                child: CircleAvatar(
                  backgroundColor: FluentColors.of(context).accentSubtle,
                  child: Icon(Icons.person,
                      size: 50, color: FluentColors.of(context).accent),
                ),
              ),
              const SizedBox(height: 16),
              fluent.FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  _pickAndSaveAvatar();
                },
                child: const Text('选择照片'),
              ),
            ],
          ],
        ),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// Show remove confirmation dialog
  void _showRemoveConfirmDialog() {
    fluent.showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => fluent.ContentDialog(
        title: const Text('移除头像？'),
        content: const Text('确定要移除当前头像吗？'),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          fluent.FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _removeAvatar();
            },
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final currentMode = themeProvider.themeMode;

    return FluentScreen(
      title: const Text('设置'),
      content: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const UpdateSettingsCard(),

          const SizedBox(height: 20),

          // App Settings
          const FluentSectionHeader('应用'),
          Card(
            child: Column(
              children: [
                // Profile Picture Section
                ListTile(
                  leading: GestureDetector(
                    onTap: _showAvatarOptions,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: _userAvatarBase64 != null
                          ? ClipOval(
                              child: Image.memory(
                                base64Decode(_userAvatarBase64!),
                                fit: BoxFit.cover,
                              ),
                            )
                          : CircleAvatar(
                              backgroundColor:
                                  FluentColors.of(context).accentSubtle,
                              child: Icon(Icons.person,
                                  color: FluentColors.of(context).accent),
                            ),
                    ),
                  ),
                  title: const Text('头像'),
                  subtitle: _userAvatarBase64 != null
                      ? const Text('点击更换')
                      : const Text('未设置'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showAvatarOptions,
                ),
                const Divider(indent: 54),
                ListTile(
                  leading: const Icon(Icons.notifications),
                  title: const Text('通知'),
                  subtitle: const Text('显示新消息通知'),
                  trailing: fluent.ToggleSwitch(
                    checked: true,
                    onChanged: (value) {
                      // TODO: Implement notifications
                    },
                  ),
                ),
                const Divider(indent: 54),
                ListTile(
                  leading: const Icon(Icons.dark_mode),
                  title: const Text('主题'),
                  subtitle: Text(_getThemeName(currentMode)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showThemeDialog(context),
                ),
                const Divider(indent: 54),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: const Text('语言'),
                  subtitle: const Text('简体中文'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // TODO: Implement language selection
                  },
                ),
                const Divider(indent: 54),
                ListTile(
                  leading: const Icon(Icons.delete_forever),
                  title: const Text('清除全部会话'),
                  subtitle: const Text('删除本机保存的聊天记录'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _clearAllSessions(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          const FluentSectionHeader('代理'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: const Text('自动允许代理操作'),
                  subtitle: const Text('关闭时，运行命令、改文件等操作需要你逐个确认'),
                  trailing: fluent.ToggleSwitch(
                    checked: context
                        .watch<ConnectionManager>()
                        .wsService
                        .autoApprovePermissions,
                    onChanged: (value) => context
                        .read<ConnectionManager>()
                        .setAutoApprovePermissions(value),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.extension_outlined),
                  title: const Text('MCP 服务器'),
                  subtitle: Text(
                    '${context.watch<ConnectionManager>().mcpServers.where((s) => s.enabled).length} 个已启用',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const McpServersScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // About
          const FluentSectionHeader('关于'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info),
                  title: const Text('PocketBot'),
                  subtitle: Text(AppVersion.displayVersion),
                ),
                const Divider(indent: 54),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('开源'),
                  subtitle: const Text('在 GitHub 上查看'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => UpdateDialogs.openRepo(),
                ),
                const Divider(indent: 54),
                ListTile(
                  leading: const Icon(Icons.description),
                  title: const Text('隐私政策'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () {
                    // TODO: Open privacy policy
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Debug
          const FluentSectionHeader('调试'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bug_report),
                  title: const Text('调试模式'),
                  subtitle: const Text('输出详细日志'),
                  trailing: fluent.ToggleSwitch(
                    checked: false,
                    onChanged: (value) {
                      // TODO: Toggle debug mode
                    },
                  ),
                ),
                const Divider(indent: 54),
                ListTile(
                  leading: const Icon(Icons.terminal),
                  title: const Text('查看日志'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // TODO: View logs
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getThemeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  void _showThemeDialog(BuildContext context) {
    final themeProvider = context.read<ThemeProvider>();

    fluent.showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => fluent.ContentDialog(
        title: const Text('选择主题'),
        content: RadioGroup<ThemeMode>(
          groupValue: themeProvider.themeMode,
          onChanged: (value) {
            if (value == null) return;
            themeProvider.setThemeMode(value);
            Navigator.pop(context);
          },
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              fluent.RadioButton<ThemeMode>(
                value: ThemeMode.light,
                content: Text('浅色'),
              ),
              SizedBox(height: 12),
              fluent.RadioButton<ThemeMode>(
                value: ThemeMode.dark,
                content: Text('深色'),
              ),
              SizedBox(height: 12),
              fluent.RadioButton<ThemeMode>(
                value: ThemeMode.system,
                content: Text('跟随系统'),
              ),
            ],
          ),
        ),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _clearAllSessions(BuildContext context) {
    fluent.showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => fluent.ContentDialog(
        title: const Text('清除全部会话'),
        content: const Text(
          '确定要删除本机保存的全部聊天记录吗？此操作无法撤销。',
        ),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          fluent.FilledButton(
            onPressed: () async {
              await SessionStorage.clearAllSessions();

              final wsService = context.read<ConnectionManager>().wsService;
              wsService.clearAllSessions();

              if (!context.mounted) return;
              Navigator.pop(context);
              _showSnackBar(context, '已清除全部会话');
            },
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(BuildContext context, String message) {
    showAppNotice(context, message);
  }
}
