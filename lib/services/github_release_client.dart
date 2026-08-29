import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pocket_bot/config/update_channel.dart';
import 'package:pocket_bot/utils/semver.dart';

enum UpdatePlatform { android, windows, other }

class GithubAsset {
  final String name;
  final String downloadUrl;
  final int size;

  const GithubAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  factory GithubAsset.fromJson(Map<String, dynamic> json) {
    return GithubAsset(
      name: json['name'] as String? ?? '',
      downloadUrl: json['browser_download_url'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }

  String get formattedSize {
    if (size <= 0) return '未知大小';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class GithubRelease {
  final String tagName;
  final String? name;
  final String? body;
  final bool prerelease;
  final bool draft;
  final String htmlUrl;
  final List<GithubAsset> assets;
  final SemVer? version;

  const GithubRelease({
    required this.tagName,
    required this.prerelease,
    required this.draft,
    required this.htmlUrl,
    required this.assets,
    this.name,
    this.body,
    this.version,
  });

  factory GithubRelease.fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String? ?? '';
    final rawAssets = json['assets'];
    final assets = <GithubAsset>[];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is Map) {
          assets.add(GithubAsset.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return GithubRelease(
      tagName: tag,
      name: json['name'] as String?,
      body: json['body'] as String?,
      prerelease: json['prerelease'] == true,
      draft: json['draft'] == true,
      htmlUrl: json['html_url'] as String? ?? '',
      assets: assets,
      version: SemVer.tryParse(tag),
    );
  }

  GithubAsset? assetFor(UpdatePlatform platform) {
    switch (platform) {
      case UpdatePlatform.android:
        return _firstWhereName(
          (name) => name.toLowerCase().endsWith('.apk'),
        );
      case UpdatePlatform.windows:
        return _firstWhereName((name) {
              final lower = name.toLowerCase();
              return lower.endsWith('.zip') && lower.contains('windows');
            }) ??
            _firstWhereName((name) => name.toLowerCase().endsWith('.zip'));
      case UpdatePlatform.other:
        return null;
    }
  }

  GithubAsset? _firstWhereName(bool Function(String name) test) {
    for (final asset in assets) {
      if (test(asset.name)) return asset;
    }
    return null;
  }

  static GithubRelease? pickLatest(
    List<GithubRelease> releases, {
    required UpdateChannel channel,
  }) {
    GithubRelease? best;
    for (final release in releases) {
      if (release.draft || release.version == null) continue;
      if (channel == UpdateChannel.stable && release.prerelease) continue;
      if (best == null || release.version! > best.version!) {
        best = release;
      }
    }
    return best;
  }
}

class UpdateCheckResult {
  final GithubRelease release;
  final String currentVersion;
  final bool updateAvailable;
  final UpdatePlatform platform;

  const UpdateCheckResult({
    required this.release,
    required this.currentVersion,
    required this.updateAvailable,
    required this.platform,
  });

  GithubAsset? get platformAsset => release.assetFor(platform);

  bool get canDownload => platformAsset != null;
}

class GithubReleaseClient {
  GithubReleaseClient({
    http.Client? httpClient,
    this.owner = UpdateConstants.githubOwner,
    this.repo = UpdateConstants.githubRepo,
    required String Function() currentVersion,
    required UpdatePlatform Function() platform,
  })  : _http = httpClient ?? http.Client(),
        _currentVersion = currentVersion,
        _platform = platform,
        _ownsHttp = httpClient == null;

  final http.Client _http;
  final String owner;
  final String repo;
  final String Function() _currentVersion;
  final UpdatePlatform Function() _platform;
  final bool _ownsHttp;

  static const headers = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'PocketBot',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  Future<UpdateCheckResult?> checkForUpdates({
    required UpdateChannel channel,
  }) async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/releases?per_page=100',
    );
    final response = await _http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw GithubReleaseException(
        'GitHub API ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return null;

    final releases = <GithubRelease>[];
    for (final item in decoded) {
      if (item is Map) {
        releases.add(GithubRelease.fromJson(Map<String, dynamic>.from(item)));
      }
    }

    final latest = GithubRelease.pickLatest(releases, channel: channel);
    final latestVersion = latest?.version;
    if (latest == null || latestVersion == null) return null;

    final currentText = _currentVersion();
    final current = SemVer.tryParse(currentText);
    final available = current == null || latestVersion > current;

    return UpdateCheckResult(
      release: latest,
      currentVersion: currentText,
      updateAvailable: available,
      platform: _platform(),
    );
  }

  void close() {
    if (_ownsHttp) {
      _http.close();
    }
  }
}

class GithubReleaseException implements Exception {
  GithubReleaseException(this.message);
  final String message;

  @override
  String toString() => message;
}
