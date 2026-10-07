import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pocket_bot/config/update_config.dart';
import 'package:pocket_bot/services/asset_download.dart';
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
    final name = asset.name.split(RegExp(r'[/\\]')).last;
    if (name.isEmpty || asset.downloadUrl.isEmpty) return null;

    final directory = await getTemporaryDirectory();
    final finished = File('${directory.path}/$name');
    final partial = File('${directory.path}/$name.partial');

    if (asset.size > 0 &&
        await finished.exists() &&
        await finished.length() == asset.size) {
      onProgress?.call(1);
      return finished;
    }

    Object? lastError;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        final file = await _downloadOnce(asset, finished, partial, onProgress);
        if (file != null) return file;
      } catch (error) {
        lastError = error;
        Logger.warning(
          '[Update] Download attempt ${attempt + 1} failed: $error',
        );
        if (attempt < 5) {
          await Future<void>.delayed(Duration(seconds: attempt + 1));
        }
      }
    }
    Logger.error('[Update] Download failed: $lastError');
    return null;
  }

  Future<File?> _downloadOnce(
    GithubAsset asset,
    File finished,
    File partial,
    void Function(double progress)? onProgress,
  ) async {
    final localBytes = await partial.exists() ? await partial.length() : 0;
    final plan = planAssetDownload(
      localBytes: localBytes,
      assetSize: asset.size,
    );
    if (plan.complete) {
      onProgress?.call(1);
      if (await finished.exists()) await finished.delete();
      return partial.rename(finished.path);
    }
    if (plan.offset == 0 && localBytes > 0 && await partial.exists()) {
      await partial.delete();
    }
    if (plan.offset > 0) {
      final total = asset.size;
      if (onProgress != null && total > 0) onProgress(plan.offset / total);
    }

    final headers = <String, dynamic>{
      'User-Agent': 'PocketBot',
      'Accept': 'application/octet-stream',
    };
    if (plan.offset > 0) {
      headers['Range'] = 'bytes=${plan.offset}-';
    }

    final response = await _dio.get<ResponseBody>(
      asset.downloadUrl,
      options: Options(
        headers: headers,
        responseType: ResponseType.stream,
        followRedirects: true,
        maxRedirects: 5,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 40),
        validateStatus: (code) => code == 200 || code == 206 || code == 416,
      ),
    );

    if (response.statusCode == 416) {
      if (await partial.exists()) await partial.delete();
      throw StateError('Range not satisfiable');
    }

    final append = plan.offset > 0 && responseAppendsFromOffset(response.statusCode);
    final body = response.data;
    if (body == null) {
      throw StateError('Empty download response');
    }

    var written = append ? plan.offset : 0;
    final output = await partial.open(
      mode: append ? FileMode.append : FileMode.write,
    );
    try {
      await for (final chunk in body.stream) {
        await output.writeFrom(chunk);
        written += chunk.length;
        final total = asset.size > 0 ? asset.size : written;
        if (onProgress != null && total > 0) {
          onProgress((written / total).clamp(0, 1).toDouble());
        }
      }
    } finally {
      await output.close();
    }

    final size = await partial.length();
    if (asset.size > 0 && size < asset.size) {
      throw StateError('Incomplete download $size/${asset.size}');
    }
    if (await finished.exists()) await finished.delete();
    final saved = await partial.rename(finished.path);
    Logger.info('[Update] Downloaded ${saved.path}');
    return saved;
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
