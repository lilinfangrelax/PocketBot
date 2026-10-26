import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pocket_bot/config/update_channel.dart';
import 'package:pocket_bot/services/dev_update.dart';
import 'package:pocket_bot/services/github_release_client.dart';
import 'package:pocket_bot/utils/semver.dart';

class DevUpdateClient {
  DevUpdateClient({
    required http.Client httpClient,
    required this.tailnetSuffix,
    required this.currentVersion,
    required this.installedSha256,
    required this.platform,
  }) : _http = httpClient;

  final http.Client _http;
  final Future<String?> Function() tailnetSuffix;
  final String Function() currentVersion;
  final String? installedSha256;
  final UpdatePlatform platform;

  Future<UpdateCheckOutcome> check() async {
    if (platform != UpdatePlatform.android) {
      return const UpdateCheckOutcome(
        channel: UpdateChannel.dev,
        failure: UpdateCheckFailure.request,
        error: '开发机通道要在手机上安装',
      );
    }

    final suffix = tailnetSuffixFromText(await tailnetSuffix() ?? '');
    if (suffix == null) {
      return const UpdateCheckOutcome(
        channel: UpdateChannel.dev,
        failure: UpdateCheckFailure.emptyChannel,
        error: '手机没有连上 Tailscale',
      );
    }

    try {
      final manifestUri = devUpdateManifestUri(suffix);
      final response = await _http.get(manifestUri, headers: const {
        'Accept': 'application/json',
        'User-Agent': 'PocketBot',
      }).timeout(const Duration(seconds: 15));
      if (response.statusCode == 404) {
        return const UpdateCheckOutcome(
          channel: UpdateChannel.dev,
          failure: UpdateCheckFailure.emptyChannel,
        );
      }
      if (response.statusCode != 200) {
        return UpdateCheckOutcome(
          channel: UpdateChannel.dev,
          failure: UpdateCheckFailure.request,
          error: '开发机返回 ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      final manifest = parseDevUpdateManifest(decoded);
      final version = SemVer.tryParse(manifest?.version);
      if (manifest == null || version == null) {
        return const UpdateCheckOutcome(
          channel: UpdateChannel.dev,
          failure: UpdateCheckFailure.emptyChannel,
        );
      }
      final apkUri = manifestUri.resolve(manifest.file);
      final current = currentVersion();
      return UpdateCheckOutcome(
        channel: UpdateChannel.dev,
        result: UpdateCheckResult(
          release: GithubRelease(
            tagName: manifest.version,
            name: manifest.version,
            body: '来自当前这台电脑编译的安装包',
            prerelease: true,
            draft: false,
            htmlUrl: manifestUri.toString(),
            assets: [
              GithubAsset(
                name: manifest.file,
                downloadUrl: apkUri.toString(),
                size: manifest.size,
              ),
            ],
            version: version,
          ),
          currentVersion: current,
          updateAvailable: devBuildAvailable(
            sha256: manifest.sha256,
            installedSha256: installedSha256,
          ),
          platform: platform,
          sourceLabel: '开发机',
          devSha256: manifest.sha256,
        ),
      );
    } catch (error) {
      if (_unreachable(error)) {
        return const UpdateCheckOutcome(
          channel: UpdateChannel.dev,
          failure: UpdateCheckFailure.emptyChannel,
        );
      }
      return UpdateCheckOutcome(
        channel: UpdateChannel.dev,
        failure: UpdateCheckFailure.request,
        error: '$error',
      );
    }
  }
}

bool _unreachable(Object error) {
  return error is TimeoutException ||
      error is SocketException ||
      error is TlsException ||
      error is http.ClientException;
}
