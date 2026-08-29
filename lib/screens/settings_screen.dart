import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:pocket_bot/config/ota_config.dart';
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/config/user_config.dart';
import 'package:pocket_bot/main.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/ota_service.dart';
import 'package:pocket_bot/utils/logger.dart';
import 'package:pocket_bot/utils/version_utils.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings screen
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isChecking = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _pickAndSaveAvatar();
                },
                icon: const Icon(Icons.change_circle),
                label: const Text('更换照片'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showRemoveConfirmDialog();
                },
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text('移除', style: TextStyle(color: Colors.red)),
              ),
            ] else ...[
              SizedBox(
                width: 100,
                height: 100,
                child: CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: const Icon(Icons.person, size: 50, color: Colors.blue),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _pickAndSaveAvatar();
                },
                icon: const Icon(Icons.add_photo_alternate),
                label: const Text('选择照片'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Show remove confirmation dialog
  void _showRemoveConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除头像？'),
        content: const Text('确定要移除当前头像吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _removeAvatar();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // OTA Update Settings
          _buildSectionHeader('OTA 更新'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.update),
                  title: const Text('OTA 服务器'),
                  subtitle: Text(
                    OtaConfig.serverUrl.replaceAll('http://', ''),
                    style: TextStyle(
                      color: OtaConfig.enabled ? Colors.green : Colors.grey,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showOtaServerDialog(context),
                ),
                const Divider(),
                SwitchListTile(
                  secondary: const Icon(Icons.system_update),
                  title: const Text('启用 OTA 更新'),
                  subtitle: const Text('自动检查新版本'),
                  value: OtaConfig.enabled,
                  onChanged: (value) {
                    setState(() {
                      OtaConfig.enabled = value;
                    });
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.developer_mode),
                  title: const Text('OTA 通道'),
                  subtitle: Text(OtaConfig.channel.displayName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showOtaChannelDialog(context),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('检查更新'),
                  subtitle: _isChecking
                      ? const Text('正在检查...')
                      : const Text('立即检查是否有新版本'),
                  trailing: _isChecking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: _isChecking ? null : () => _checkForUpdates(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // App Settings
          _buildSectionHeader('应用'),
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
                              backgroundColor: Colors.blue.shade100,
                              child: const Icon(Icons.person, color: Colors.blue),
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
                const Divider(),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications),
                  title: const Text('通知'),
                  subtitle: const Text('显示新消息通知'),
                  value: true,
                  onChanged: (value) {
                    // TODO: Implement notifications
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.dark_mode),
                  title: const Text('主题'),
                  subtitle: Text(_getThemeName(currentMode)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showThemeDialog(context),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: const Text('语言'),
                  subtitle: const Text('简体中文'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // TODO: Implement language selection
                  },
                ),
                const Divider(),
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

          const SizedBox(height: 24),

          // About
          _buildSectionHeader('关于'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info),
                  title: const Text('PocketBot'),
                  subtitle: Text(AppVersion.displayVersion),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('开源'),
                  subtitle: const Text('在 GitHub 上查看'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () {
                    // TODO: Open GitHub link
                  },
                ),
                const Divider(),
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

          const SizedBox(height: 24),

          // Debug
          _buildSectionHeader('调试'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bug_report),
                  title: const Text('调试模式'),
                  subtitle: const Text('输出详细日志'),
                  trailing: Switch(
                    value: false,
                    onChanged: (value) {
                      // TODO: Toggle debug mode
                    },
                  ),
                ),
                const Divider(),
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择主题'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile(
              title: const Row(
                children: [
                  Icon(Icons.light_mode),
                  SizedBox(width: 8),
                  Text('浅色'),
                ],
              ),
              value: ThemeMode.light,
              groupValue: themeProvider.themeMode,
              onChanged: (value) {
                themeProvider.setThemeMode(ThemeMode.light);
                Navigator.pop(context);
              },
            ),
            RadioListTile(
              title: const Row(
                children: [
                  Icon(Icons.dark_mode),
                  SizedBox(width: 8),
                  Text('深色'),
                ],
              ),
              value: ThemeMode.dark,
              groupValue: themeProvider.themeMode,
              onChanged: (value) {
                themeProvider.setThemeMode(ThemeMode.dark);
                Navigator.pop(context);
              },
            ),
            RadioListTile(
              title: const Row(
                children: [
                  Icon(Icons.brightness_auto),
                  SizedBox(width: 8),
                  Text('跟随系统'),
                ],
              ),
              value: ThemeMode.system,
              groupValue: themeProvider.themeMode,
              onChanged: (value) {
                themeProvider.setThemeMode(ThemeMode.system);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showOtaChannelDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('OTA 通道'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile(
              title: const Row(
                children: [
                  Icon(Icons.tag),
                  SizedBox(width: 8),
                  Text('稳定版'),
                ],
              ),
              subtitle: const Text('正式发布版本（例如 1.0.0）'),
              value: OtaChannel.stable,
              groupValue: OtaConfig.channel,
              onChanged: (value) {
                OtaConfig.setChannel(OtaChannel.stable);
                Navigator.pop(context);
                _showSnackBar(context, '已选择稳定版通道');
              },
            ),
            RadioListTile(
              title: const Row(
                children: [
                  Icon(Icons.developer_mode),
                  SizedBox(width: 8),
                  Text('开发版'),
                ],
              ),
              subtitle: const Text('最新提交（需要 -dev.x 版本）'),
              value: OtaChannel.dev,
              groupValue: OtaConfig.channel,
              onChanged: (value) {
                OtaConfig.setChannel(OtaChannel.dev);
                Navigator.pop(context);
                _showSnackBar(context, '已选择开发版通道：${OtaConfig.versionSuffix}');
              },
            ),
            RadioListTile(
              title: const Row(
                children: [
                  Icon(Icons.auto_awesome),
                  SizedBox(width: 8),
                  Text('自动'),
                ],
              ),
              subtitle: const Text('自动选择最新版本（使用开发版通道）'),
              value: OtaChannel.auto,
              groupValue: OtaConfig.channel,
              onChanged: (value) {
                OtaConfig.setChannel(OtaChannel.auto);
                Navigator.pop(context);
                _showSnackBar(context, '已选择自动通道');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  void _clearAllSessions(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除全部会话'),
        content: const Text(
          '确定要删除本机保存的全部聊天记录吗？此操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              await SessionStorage.clearAllSessions();
              
              final wsService = context.read<ConnectionManager>().wsService;
              wsService.clearAllSessions();
              
              Navigator.pop(context);
              _showSnackBar(context, '已清除全部会话');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }

  void _showOtaServerDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController(
      text: OtaConfig.serverUrl.replaceAll('http://', ''),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('OTA 服务器'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '请输入 OTA 服务器的 IP 或主机名',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: '192.168.1.100:3000',
                prefixIcon: Icon(Icons.dns),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 8),
            const Text(
              '例如：192.168.1.100:3000 或 localhost:3000',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final address = controller.text.trim();
              if (address.isNotEmpty) {
                setState(() {
                  OtaConfig.configure(address);
                });
                Navigator.pop(context);
                _showSnackBar(context, 'OTA 服务器已更新');
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    setState(() => _isChecking = true);

    try {
      final update = await OtaService().checkForUpdates();

      if (update != null) {
        if (update.updateAvailable) {
          _showUpdateDialog(context, update);
        } else {
          _showSnackBar(context, '已是最新版本');
        }
      } else {
        _showSnackBar(context, '检查更新失败');
      }
    } catch (e) {
      _showSnackBar(context, '出错：$e');
    } finally {
      setState(() => _isChecking = false);
    }
  }

  void _showUpdateDialog(BuildContext context, OtaUpdateInfo update) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发现新版本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('新版本 ${update.latestVersion} 可用'),
            if (update.changelog != null) ...[
              const SizedBox(height: 16),
              Text(
                update.changelog!,
                style: const TextStyle(fontSize: 14),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              '文件大小：${update.formattedFileSize}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (_isDownloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _downloadProgress),
              const SizedBox(height: 8),
              Text(
                '正在下载 ${(_downloadProgress * 100).toInt()}%',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          if (update.isMandatory)
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('必须更新'),
            )
          else ...[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('稍后'),
            ),
            ElevatedButton(
              onPressed: _isDownloading
                  ? null
                  : () {
                      Navigator.pop(context);
                      _downloadAndInstall(context, update);
                    },
              child: _isDownloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('下载并安装'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _downloadAndInstall(BuildContext context, OtaUpdateInfo update) async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      // Request storage permission for Android
      if (Platform.isAndroid) {
        await Permission.requestInstallPackages.request();
      }

      // Download update with progress
      final otaService = OtaService();
      
      Logger.info('[Settings] Starting download for version: ${update.latestVersion}');
      
      final file = await otaService.downloadUpdate(
        version: update.latestVersion!,
        onProgress: (progress) {
          setState(() {
            _downloadProgress = progress;
          });
        },
      );

      if (file == null || !await file.exists()) {
        _showSnackBar(context, '下载失败');
        setState(() {
          _isDownloading = false;
        });
        return;
      }

      Logger.info('[Settings] Download complete: ${file.path}');

      // Update UI to show download done, now verifying
      setState(() {
        _downloadProgress = 1.0;
      });

      // Verify SHA256 if provided
      if (update.sha256 != null && update.sha256!.isNotEmpty) {
        _showSnackBar(context, '正在校验更新...');
        
        final isValid = await otaService.verifyUpdate(
          file,
          expectedSha256: update.sha256,
        );

        if (!isValid) {
          _showSnackBar(context, '校验失败');
          setState(() {
            _isDownloading = false;
          });
          return;
        }
      }

      // Download and verification complete, ready to install
      setState(() {
        _isDownloading = false;
      });

      _showSnackBar(context, '下载完成，正在打开安装程序…');
      
      // Open the APK file
      final filePath = file.path;
      final Uri uri = Uri.file(filePath);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showSnackBar(context, '安装包已保存：$filePath');
      }
    } catch (e) {
      Logger.error('[Settings] Download error: $e');
      _showSnackBar(context, '出错：${e.toString()}');
      setState(() {
        _isDownloading = false;
      });
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
