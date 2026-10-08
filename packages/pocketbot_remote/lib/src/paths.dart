import 'dart:io';

/// Operating system and CPU of the machine that will run the helper.
class RemotePlatform {
  final String os;
  final String arch;

  const RemotePlatform({required this.os, required this.arch});

  /// Registry key, for example `linux-x86_64`.
  String get registryKey => '$os-$arch';

  String get assetName {
    final archName = arch == 'aarch64' ? 'arm64' : 'x64';
    final ext = os == 'windows' ? '.exe' : '';
    return 'pocketbot-remote-$os-$archName$ext';
  }

  String get label => '$os/$arch';

  bool get isWindows => os == 'windows';

  static RemotePlatform? parseUname(String osName, String machine) {
    final osKey = switch (osName.trim().toLowerCase()) {
      'linux' => 'linux',
      'darwin' => 'darwin',
      _ => null,
    };
    if (osKey == null) return null;
    final arch = _arch(machine);
    if (arch == null) return null;
    return RemotePlatform(os: osKey, arch: arch);
  }

  static RemotePlatform? parseWindowsArchitecture(String raw) {
    final arch = _arch(raw);
    if (arch == null) return null;
    return RemotePlatform(os: 'windows', arch: arch);
  }

  static String? _arch(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'x86_64':
      case 'amd64':
      case 'x64':
        return 'x86_64';
      case 'aarch64':
      case 'arm64':
        return 'aarch64';
      default:
        return null;
    }
  }
}

String pocketbotHome() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  return '$home${Platform.pathSeparator}.pocketbot';
}

String helperFileName(RemotePlatform platform, String version) {
  final ext = platform.isWindows ? '.exe' : '';
  return 'pocketbot-remote-$version$ext';
}

String helperInstallPath({
  required RemotePlatform platform,
  required String homeDirectory,
  required String version,
}) {
  final separator = platform.isWindows ? '\\' : '/';
  final root = homeDirectory.endsWith(separator)
      ? homeDirectory.substring(0, homeDirectory.length - 1)
      : homeDirectory;
  return '$root$separator.pocketbot$separator${helperFileName(platform, version)}';
}

String releaseAssetUrl({
  required String version,
  required RemotePlatform platform,
  String owner = 'lilinfangrelax',
  String repo = 'PocketBot',
}) {
  final tag = 'v$version';
  return 'https://github.com/$owner/$repo/releases/download/$tag/${platform.assetName}';
}

/// Stable id for the agent process kept by the remote daemon.
String remoteAgentSessionId({
  required String connectionId,
  required String agentId,
  required String workingDirectory,
}) {
  final raw = '$connectionId|$agentId|$workingDirectory';
  final sanitized = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  if (sanitized.length <= 120) return sanitized;
  return sanitized.substring(sanitized.length - 120);
}
