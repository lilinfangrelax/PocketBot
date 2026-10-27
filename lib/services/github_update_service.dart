import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pocket_bot/config/update_config.dart';
import 'package:pocket_bot/services/asset_download.dart';
import 'package:pocket_bot/services/dev_update.dart';
import 'package:pocket_bot/services/dev_update_client.dart';
import 'package:pocket_bot/services/github_release_client.dart';
import 'package:pocket_bot/services/tailnet_suffix.dart';
import 'package:pocket_bot/services/update_proxy.dart';
import 'package:pocket_bot/services/update_transport.dart';
import 'package:pocket_bot/services/windows_setup_update.dart';
import 'package:pocket_bot/utils/logger.dart';
import 'package:pocket_bot/utils/version_utils.dart';
import 'package:url_launcher/url_launcher.dart';

export 'package:pocket_bot/services/github_release_client.dart';

Future<TailnetDiscovery> Function() _bindTailnetDiscovery({
  Future<String?> Function()? tailnetSuffix,
  Future<bool> Function()? tailscaleUp,
}) {
  if (tailnetSuffix == null && tailscaleUp == null) return discoverTailnet;
  return () async => TailnetDiscovery(
        suffix: tailnetSuffix == null ? null : await tailnetSuffix(),
        interfaceUp: tailscaleUp != null && await tailscaleUp(),
      );
}

class GithubUpdateService {
  GithubUpdateService({
    http.Client? httpClient,
    Dio? dio,
    String owner = UpdateConstants.githubOwner,
    String repo = UpdateConstants.githubRepo,
    String Function()? currentVersion,
    UpdatePlatform Function()? platform,
    Future<String?> Function()? tailnetSuffix,
    Future<bool> Function()? tailscaleUp,
    String? Function()? installedDevSha256,
  })  : _externalHttp = httpClient,
        _currentVersion = currentVersion ?? _defaultVersion,
        _platform = platform ?? currentPlatform,
        _discover = _bindTailnetDiscovery(
          tailnetSuffix: tailnetSuffix,
          tailscaleUp: tailscaleUp,
        ),
        _installedDevSha256 =
            installedDevSha256 ?? (() => UpdateConfig.installedDevSha256),
        _client = GithubReleaseClient(
          httpClient: httpClient,
          owner: owner,
          repo: repo,
          currentVersion: currentVersion ?? _defaultVersion,
          platform: platform ?? currentPlatform,
        ),
        _dio = dio ?? createUpdateDio(),
        _ownsDio = dio == null;

  final http.Client? _externalHttp;
  final String Function() _currentVersion;
  final UpdatePlatform Function() _platform;
  final Future<TailnetDiscovery> Function() _discover;
  final String? Function() _installedDevSha256;
  final GithubReleaseClient _client;
  final Dio _dio;
  final bool _ownsDio;

  static String _defaultVersion() => AppVersion.baseVersion;

  static UpdatePlatform currentPlatform() {
    if (Platform.isAndroid) return UpdatePlatform.android;
    if (Platform.isWindows) return UpdatePlatform.windows;
    return UpdatePlatform.other;
  }

  Future<UpdateCheckOutcome> checkForUpdates({
    UpdateChannel? channel,
  }) async {
    final selected = channel ?? UpdateConfig.channel;
    if (selected == UpdateChannel.dev) {
      return _checkDevChannel();
    }
    try {
      final result = await _client.checkForUpdates(channel: selected);
      if (result == null) {
        Logger.info('[Update] No releases for channel ${selected.id}');
        return UpdateCheckOutcome(
          channel: selected,
          failure: UpdateCheckFailure.emptyChannel,
        );
      }
      Logger.info(
        '[Update] channel=${selected.id} current=${result.currentVersion} '
        'latest=${result.release.version} available=${result.updateAvailable}',
      );
      return UpdateCheckOutcome(channel: selected, result: result);
    } catch (e) {
      final detail = formatUpdateError(e, maxLength: 500);
      Logger.warning('[Update] Check failed: $detail');
      return UpdateCheckOutcome(
        channel: selected,
        failure: UpdateCheckFailure.request,
        error: detail,
      );
    }
  }

  Future<UpdateCheckOutcome> _checkDevChannel() async {
    final ownsClient = _externalHttp == null;
    final httpClient = _externalHttp ?? createUpdateHttpClient();
    final dev = DevUpdateClient(
      httpClient: httpClient,
      discover: _discover,
      currentVersion: _currentVersion,
      installedSha256: _installedDevSha256(),
      platform: _platform(),
    );
    try {
      final outcome = await dev.check();
      final result = outcome.result;
      if (result == null) {
        Logger.info('[Update] Dev check: ${outcome.notice}');
      } else {
        Logger.info(
          '[Update] channel=dev current=${result.currentVersion} '
          'latest=${result.release.version} available=${result.updateAvailable}',
        );
      }
      return outcome;
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  Future<File?> downloadAsset(
    GithubAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    final name = asset.name.split(RegExp(r'[/\\]')).last;
    if (name.isEmpty || asset.downloadUrl.isEmpty) return null;

    final directory = await _updateDirectory();
    final finished = File('${directory.path}/$name');
    final partial = File('${directory.path}/$name.partial');

    if (asset.size > 0 &&
        await finished.exists() &&
        await finished.length() == asset.size &&
        await _hasExpectedHeader(finished)) {
      onProgress?.call(1);
      return finished;
    }
    if (await finished.exists()) await finished.delete();

    Object? lastError;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        final file = await _downloadOnce(asset, finished, partial, onProgress);
        if (file != null) return file;
      } catch (error) {
        lastError = error;
        Logger.warning(
          '[Update] Download attempt ${attempt + 1} failed: '
          '${formatUpdateError(error, maxLength: 500)}',
        );
        if (attempt < 5) {
          await Future<void>.delayed(Duration(seconds: attempt + 1));
        }
      }
    }
    Logger.error(
      '[Update] Download failed: ${formatUpdateError(lastError, maxLength: 500)}',
    );
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
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        validateStatus: (code) => code == 200 || code == 206 || code == 416,
      ),
    );

    if (response.statusCode == 416) {
      if (await partial.exists()) await partial.delete();
      throw StateError('Range not satisfiable');
    }
    if (response.statusCode == 206 &&
        !contentRangeStartsAt(
          response.headers.value('content-range'),
          plan.offset,
        )) {
      if (await partial.exists()) await partial.delete();
      throw StateError('Unexpected content range');
    }

    final append =
        plan.offset > 0 && responseAppendsFromOffset(response.statusCode);
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
    if (!downloadSizeMatches(written: size, assetSize: asset.size) ||
        !await _hasExpectedHeader(partial)) {
      await partial.delete();
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
        if (!await _hasZipHeader(file)) {
          Logger.warning(
              '[Update] Refusing to install a file that is not an APK');
          return false;
        }
        try {
          final installed = await const MethodChannel('pocketbot/apk_install')
              .invokeMethod<bool>('install', {'path': file.path});
          if (installed == true) return true;
        } catch (error) {
          Logger.warning('[Update] PackageInstaller failed: $error');
        }
        final result = await OpenFilex.open(
          file.path,
          type: 'application/vnd.android.package-archive',
        );
        return result.type == ResultType.done;
      }

      if (Platform.isWindows) {
        return _installWindowsSetup(file);
      }

      final result = await OpenFilex.open(file.path);
      return result.type == ResultType.done;
    } catch (e) {
      Logger.error('[Update] Open/install failed: $e');
      return false;
    }
  }

  /// True when this process is the per-user Inno install and can be replaced
  /// silently. Portable and dev copies return false and open the wizard.
  Future<bool> runningFromInstalledCopy() async {
    try {
      if (!Platform.isWindows) return false;
      final registered = await queryInnoInstallLocation();
      return planWindowsSetupUpdate(
        executablePath: Platform.resolvedExecutable,
        registeredInstallDir: registered,
      ).silent;
    } catch (error) {
      Logger.warning('[Update] Install location check failed: $error');
      return false;
    }
  }

  Future<bool> _installWindowsSetup(File file) async {
    final name = file.path.split(RegExp(r'[/\\]')).last;
    if (!isWindowsSetupFileName(name) || !await _hasPeHeader(file)) {
      Logger.warning('[Update] Refusing to run a file that is not the setup');
      return false;
    }

    final plan = planWindowsSetupUpdate(
      executablePath: Platform.resolvedExecutable,
      registeredInstallDir: await queryInnoInstallLocation(),
    );
    if (plan.silent) {
      final installDir = plan.installDir;
      final relaunchExe = plan.relaunchExe;
      if (installDir == null || relaunchExe == null) return false;
      final started = await launchInstalledSetupUpdate(
        setup: file,
        installDir: installDir,
        relaunchExe: relaunchExe,
        waitingForPid: pid,
      );
      if (!started) return false;
      Logger.info('[Update] Setup helper started; exiting for install');
      exit(0);
    }

    final result = await OpenFilex.open(file.path);
    if (result.type == ResultType.done) return true;
    try {
      await Process.start(file.path, const [], mode: ProcessStartMode.detached);
      return true;
    } catch (error) {
      Logger.warning('[Update] Could not open setup: $error');
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
    if (_ownsDio) {
      _dio.close(force: true);
    }
  }

  Future<Directory> _updateDirectory() async {
    if (Platform.isAndroid) {
      final external = await getExternalStorageDirectory();
      if (external != null) {
        final directory = Directory('${external.path}/updates');
        await directory.create(recursive: true);
        return directory;
      }
    }
    return getTemporaryDirectory();
  }
}

Future<List<int>> _fileHeader(File file) async {
  if (!await file.exists() || await file.length() < 2) return const [];
  return file.openRead(0, 4).fold<List<int>>(
    <int>[],
    (previous, chunk) => previous..addAll(chunk),
  );
}

Future<bool> _hasZipHeader(File file) async {
  return looksLikeZipHeader(await _fileHeader(file));
}

Future<bool> _hasPeHeader(File file) async {
  return looksLikePeHeader(await _fileHeader(file));
}

Future<bool> _hasExpectedHeader(File file) async {
  final name = file.path.split(RegExp(r'[/\\]')).last;
  final header = await _fileHeader(file);
  if (isWindowsSetupFileName(name)) return looksLikePeHeader(header);
  return looksLikeZipHeader(header);
}
