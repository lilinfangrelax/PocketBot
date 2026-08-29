import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pocket_bot/config/update_config.dart';
import 'package:pocket_bot/services/github_release_client.dart';
import 'package:pocket_bot/utils/logger.dart';
import 'package:pocket_bot/utils/version_utils.dart';
import 'package:url_launcher/url_launcher.dart';

export 'package:pocket_bot/services/github_release_client.dart';

class GithubUpdateService {
  GithubUpdateService({
    http.Client? httpClient,
    Dio? dio,
    String owner = UpdateConstants.githubOwner,
    String repo = UpdateConstants.githubRepo,
    String Function()? currentVersion,
    UpdatePlatform Function()? platform,
  })  : _client = GithubReleaseClient(
          httpClient: httpClient,
          owner: owner,
          repo: repo,
          currentVersion: currentVersion ?? (() => AppVersion.baseVersion),
          platform: platform ?? currentPlatform,
        ),
        _dio = dio ?? Dio();

  final GithubReleaseClient _client;
  final Dio _dio;

  static UpdatePlatform currentPlatform() {
    if (Platform.isAndroid) return UpdatePlatform.android;
    if (Platform.isWindows) return UpdatePlatform.windows;
    return UpdatePlatform.other;
  }

  Future<UpdateCheckResult?> checkForUpdates({
    UpdateChannel? channel,
  }) async {
    final selected = channel ?? UpdateConfig.channel;
    try {
      final result = await _client.checkForUpdates(channel: selected);
      if (result == null) {
        Logger.info('[Update] No releases for channel ${selected.id}');
        return null;
      }
      Logger.info(
        '[Update] channel=${selected.id} current=${result.currentVersion} '
        'latest=${result.release.version} available=${result.updateAvailable}',
      );
      return result;
    } catch (e) {
      Logger.warning('[Update] Check failed: $e');
      return null;
    }
  }

  Future<File?> downloadAsset(
    GithubAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/${asset.name}');
      if (await file.exists()) {
        await file.delete();
      }

      await _dio.download(
        asset.downloadUrl,
        file.path,
        onReceiveProgress: (received, total) {
          if (onProgress == null) return;
          if (total > 0) {
            onProgress(received / total);
          }
        },
        options: Options(
          headers: {
            'User-Agent': 'PocketBot',
            'Accept': 'application/octet-stream',
          },
          followRedirects: true,
        ),
      );

      if (!await file.exists()) return null;
      Logger.info('[Update] Downloaded ${file.path}');
      return file;
    } catch (e) {
      Logger.error('[Update] Download failed: $e');
      return null;
    }
  }

  Future<bool> installOrOpen(File file) async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.requestInstallPackages.request();
        if (status.isDenied || status.isPermanentlyDenied) {
          Logger.warning('[Update] Install permission denied');
          return false;
        }
        final result = await OpenFilex.open(
          file.path,
          type: 'application/vnd.android.package-archive',
        );
        return result.type == ResultType.done;
      }

      if (Platform.isWindows) {
        final result = await OpenFilex.open(file.path);
        if (result.type == ResultType.done) return true;
        await Process.run('explorer.exe', ['/select,${file.path}']);
        return true;
      }

      final result = await OpenFilex.open(file.path);
      return result.type == ResultType.done;
    } catch (e) {
      Logger.error('[Update] Open/install failed: $e');
      return false;
    }
  }

  Future<bool> openReleasePage(GithubRelease release) {
    return openReleasePageFor(Uri.tryParse(release.htmlUrl));
  }

  Future<bool> openReleasePageFor(Uri? uri) async {
    if (uri == null) return false;
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  void close() {
    _client.close();
  }
}
