import 'package:flutter/material.dart';
import 'package:pocket_bot/config/update_config.dart';
import 'package:pocket_bot/services/github_update_service.dart';
import 'package:pocket_bot/utils/logger.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings card for GitHub Release channel + manual check.
class UpdateSettingsCard extends StatefulWidget {
  const UpdateSettingsCard({super.key});

  @override
  State<UpdateSettingsCard> createState() => _UpdateSettingsCardState();
}

class _UpdateSettingsCardState extends State<UpdateSettingsCard> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final channel = UpdateConfig.channel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('更新'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.alt_route),
                title: const Text('更新通道'),
                subtitle: Text(channel.description),
                trailing: Text(
                  channel.displayName,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                onTap: () => _showChannelDialog(context),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.system_update),
                title: const Text('检查更新'),
                subtitle: Text(
                  _checking ? '正在检查...' : '从 GitHub Releases 检查新版本',
                ),
                trailing: _checking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: _checking ? null : () => _checkForUpdates(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title) {
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

  Future<void> _showChannelDialog(BuildContext context) async {
    final selected = await showDialog<UpdateChannel>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('更新通道'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final channel in UpdateChannel.values)
              RadioListTile<UpdateChannel>(
                title: Text(channel.displayName),
                subtitle: Text(channel.description),
                value: channel,
                groupValue: UpdateConfig.channel,
                onChanged: (value) => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );

    if (selected == null || selected == UpdateConfig.channel) return;
    await UpdateConfig.setChannel(selected);
    if (mounted) setState(() {});
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    setState(() => _checking = true);
    final service = GithubUpdateService();
    try {
      final result = await service.checkForUpdates();
      if (!context.mounted) return;
      if (result == null) {
        _snack(context, '检查更新失败');
        return;
      }
      if (!result.updateAvailable) {
        _snack(context, '已是最新版本');
        return;
      }
      await UpdateDialogs.showAvailable(context, result, service: service);
    } catch (e) {
      Logger.warning('[Update] Manual check failed: $e');
      if (context.mounted) _snack(context, '检查更新失败');
    } finally {
      service.close();
      if (mounted) setState(() => _checking = false);
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class UpdateDialogs {
  static Future<void> showAvailable(
    BuildContext context,
    UpdateCheckResult result, {
    GithubUpdateService? service,
  }) async {
    final ownsService = service == null;
    final updater = service ?? GithubUpdateService();
    try {
      final shouldDownload = await showDialog<bool>(
        context: context,
        builder: (context) {
          final asset = result.platformAsset;
          final changelog = result.release.body?.trim();
          return AlertDialog(
            title: const Text('发现新版本'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('新版本 ${result.release.version} 可用'),
                const SizedBox(height: 8),
                Text(
                  result.release.prerelease ? 'Beta 通道' : '正式版',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                if (changelog != null && changelog.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(child: Text(changelog)),
                  ),
                ],
                if (asset != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    '文件：${asset.name}（${asset.formattedSize}）',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('稍后'),
              ),
              if (result.canDownload)
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    result.platform == UpdatePlatform.android ? '下载并安装' : '下载',
                  ),
                )
              else
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('在浏览器中查看'),
                ),
            ],
          );
        },
      );

      if (shouldDownload != true || !context.mounted) return;

      if (!result.canDownload) {
        final opened = await updater.openReleasePage(result.release);
        if (!context.mounted) return;
        if (!opened) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法打开 GitHub 发布页')),
          );
        }
        return;
      }

      await _downloadAndInstall(context, result, updater);
    } finally {
      if (ownsService) updater.close();
    }
  }

  static Future<void> _downloadAndInstall(
    BuildContext context,
    UpdateCheckResult result,
    GithubUpdateService updater,
  ) async {
    final asset = result.platformAsset;
    if (asset == null) return;

    final progressNotifier = ValueNotifier<double>(0);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('正在下载'),
          content: ValueListenableBuilder<double>(
            valueListenable: progressNotifier,
            builder: (context, value, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: value <= 0 ? null : value),
                  const SizedBox(height: 12),
                  Text('${(value * 100).clamp(0, 100).toInt()}%'),
                ],
              );
            },
          ),
        );
      },
    );

    try {
      final file = await updater.downloadAsset(
        asset,
        onProgress: (value) {
          progressNotifier.value = value;
        },
      );

      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

      if (file == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('下载失败')),
          );
        }
        return;
      }

      final opened = await updater.installOrOpen(file);
      if (!context.mounted) return;
      if (!opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已保存：${file.path}')),
        );
        return;
      }

      if (result.platform == UpdatePlatform.windows) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已下载，请解压后替换当前安装目录')),
        );
      }
    } catch (e) {
      Logger.error('[Update] Download/install error: $e');
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('出错：$e')),
        );
      }
    } finally {
      progressNotifier.dispose();
    }
  }

  static Future<void> openRepo() async {
    final uri = Uri.parse(UpdateConfig.repoUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
