import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:pocket_bot/config/update_config.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';
import 'package:pocket_bot/services/github_update_service.dart';
import 'package:pocket_bot/utils/logger.dart';
import 'package:pocket_bot/widgets/fluent_page.dart';
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
        const FluentSectionHeader('更新'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.alt_route),
                title: const Text('更新通道'),
                subtitle: Text(channel.description),
                trailing: Text(channel.displayName),
                onTap: () => _showChannelDialog(context),
              ),
              const Divider(indent: 54),
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
                        child: fluent.ProgressRing(strokeWidth: 2),
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
    showAppNotice(context, message);
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
                  style: TextStyle(
                      fontSize: 12,
                      color: FluentColors.of(context).textSecondary),
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
                    style: TextStyle(
                        fontSize: 12,
                        color: FluentColors.of(context).textSecondary),
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
          showAppNotice(context, '无法打开 GitHub 发布页');
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

    fluent.showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return fluent.ContentDialog(
          title: const Text('正在下载'),
          content: ValueListenableBuilder<double>(
            valueListenable: progressNotifier,
            builder: (context, value, _) {
              final percent = (value * 100).clamp(0, 100).toDouble();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  fluent.ProgressBar(value: percent <= 0 ? null : percent),
                  const SizedBox(height: 12),
                  Text('${percent.toInt()}%'),
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
          showAppNotice(context, '下载中断，再次检查更新会接着下载');
        }
        return;
      }

      final opened = await updater.installOrOpen(file);
      if (!context.mounted) return;
      if (!opened) {
        showAppNotice(context, '已保存：${file.path}');
        return;
      }

      if (result.platform == UpdatePlatform.windows) {
        showAppNotice(context, '已下载，请解压后替换当前安装目录');
      }
    } catch (e) {
      Logger.error('[Update] Download/install error: $e');
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        showAppNotice(context, '出错：$e');
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
