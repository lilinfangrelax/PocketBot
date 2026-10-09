import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pocketbot_remote/pocketbot_remote.dart';

import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/acp_registry.dart';
import 'package:pocket_bot/utils/logger.dart';

RemotePlatform localRemotePlatform() {
  final os = Platform.isWindows
      ? 'windows'
      : Platform.isMacOS
          ? 'darwin'
          : 'linux';
  final version = Platform.version;
  final arch = version.contains('arm64') || version.contains('aarch64')
      ? 'aarch64'
      : 'x86_64';
  return RemotePlatform(os: os, arch: arch);
}

Future<String> currentAppVersion() async {
  final info = await PackageInfo.fromPlatform();
  final version = info.version.trim();
  if (version.isEmpty) {
    throw Exception('HELPER_INSTALL_FAILED:无法读取应用版本');
  }
  return version;
}

String? readyHelperPath(String output) {
  for (final raw in output.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('READY ')) {
      final path = line.substring(6).trim();
      if (path.isNotEmpty) return path;
    }
  }
  return null;
}

/// Converts `/d:/Work` to `D:\Work`. Other paths are unchanged.
String opensshPathToWindows(String path) {
  final slash = path.replaceAll('\\', '/');
  final match = RegExp(r'^/([a-zA-Z]):/?(.*)$').firstMatch(slash);
  if (match == null) return path;
  final drive = match.group(1)!.toUpperCase();
  final rest = match.group(2)!;
  if (rest.isEmpty) return '$drive:\\';
  return '$drive:\\${rest.replaceAll('/', r'\')}';
}

/// Directory the remote helper should use. OpenSSH shows a Windows drive as
/// `/d:/Work`, which `cmd` and `Process.start` both reject.
String remoteLaunchDirectory(RemotePlatform platform, String path) {
  final trimmed = path.trim();
  final cwd = trimmed.isEmpty ? '.' : trimmed;
  if (!platform.isWindows) return cwd;
  return opensshPathToWindows(cwd);
}

/// Runs [script] through Windows OpenSSH without cmd.exe eating quotes.
///
/// A double-quoted `powershell -Command "..."` is parsed by cmd first, and
/// `""` collapses into one `"`. PowerShell then reports
/// `The string is missing the terminator`.
String powershellEncodedCommand(String script) {
  final units = script.codeUnits;
  final bytes = Uint8List(units.length * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < units.length; i++) {
    data.setUint16(i * 2, units[i], Endian.little);
  }
  return 'powershell -NoProfile -NonInteractive -EncodedCommand '
      '${base64Encode(bytes)}';
}

String _psSingleQuote(String value) => "'${value.replaceAll("'", "''")}'";

String _windowsProbeScript(String version) {
  final exe = _psSingleQuote('.pocketbot\\pocketbot-remote-$version.exe');
  final expected = _psSingleQuote(version);
  return "\$p = Join-Path \$env:USERPROFILE $exe; "
      "\$ver = ''; "
      'if (Test-Path -LiteralPath \$p) { '
      '\$ver = (& \$p version | Out-String).Trim() }; '
      "if (\$ver -eq $expected) { Write-Output ('READY ' + \$p) } "
      "else { Write-Output 'MISSING' }";
}

String _windowsDownloadScript({
  required String version,
  required String url,
}) {
  final dir = _psSingleQuote('.pocketbot');
  final exe = _psSingleQuote('pocketbot-remote-$version.exe');
  final uri = _psSingleQuote(url);
  return "\$d = Join-Path \$env:USERPROFILE $dir; "
      'New-Item -ItemType Directory -Force -Path \$d | Out-Null; '
      "\$p = Join-Path \$d $exe; "
      "Invoke-WebRequest -Uri $uri -OutFile \$p";
}

String helperProbeCommand(RemotePlatform platform, String version) {
  if (platform.isWindows) {
    return powershellEncodedCommand(_windowsProbeScript(version));
  }
  return "sh -c 'p=\"\$HOME/.pocketbot/pocketbot-remote-$version\"; "
      "ver=\"\"; if [ -x \"\$p\" ]; then ver=\$(\"\$p\" version 2>/dev/null || true); fi; "
      "if [ \"\$ver\" = \"$version\" ]; then echo READY \"\$p\"; else echo MISSING; fi'";
}

String helperRemoteDownloadCommand({
  required RemotePlatform platform,
  required String version,
  required String url,
}) {
  if (platform.isWindows) {
    return powershellEncodedCommand(
      _windowsDownloadScript(version: version, url: url),
    );
  }
  return "sh -c 'mkdir -p \"\$HOME/.pocketbot\" && "
      "(curl -fsSL -o \"\$HOME/.pocketbot/pocketbot-remote-$version.partial\" \"$url\" "
      "|| wget -q -O \"\$HOME/.pocketbot/pocketbot-remote-$version.partial\" \"$url\") && "
      "mv \"\$HOME/.pocketbot/pocketbot-remote-$version.partial\" "
      "\"\$HOME/.pocketbot/pocketbot-remote-$version\" && "
      "chmod +x \"\$HOME/.pocketbot/pocketbot-remote-$version\"'";
}

/// Install `pocketbot-remote` for [version] and return its remote path.
Future<String> ensureRemoteHelper({
  required RemotePlatform platform,
  required String version,
  required Future<String> Function(String command) exec,
  required Future<void> Function(String remotePath, List<int> bytes) upload,
  required Future<List<int>> Function(Uri url) download,
}) async {
  final probe = helperProbeCommand(platform, version);
  final existing = readyHelperPath(await exec(probe));
  if (existing != null) return existing;

  final url = releaseAssetUrl(version: version, platform: platform);
  try {
    await exec(helperRemoteDownloadCommand(
      platform: platform,
      version: version,
      url: url,
    ));
  } catch (error) {
    Logger.warning('[remote] remote download failed: $error');
  }
  final downloaded = readyHelperPath(await exec(probe));
  if (downloaded != null) return downloaded;

  final bytes = await download(Uri.parse(url));
  if (bytes.isEmpty) {
    throw Exception('HELPER_INSTALL_FAILED:远程服务安装包是空的');
  }
  final remotePath = await _uploadedHelperPath(
    platform: platform,
    version: version,
    exec: exec,
    upload: upload,
    bytes: bytes,
  );
  if (!platform.isWindows) {
    await exec("chmod +x ${_shQuote(remotePath)}");
  }
  final installed = readyHelperPath(await exec(probe));
  if (installed != null) return installed;
  throw Exception('HELPER_INSTALL_FAILED:远程服务已上传，但版本校验没有通过');
}

Future<String> _uploadedHelperPath({
  required RemotePlatform platform,
  required String version,
  required Future<String> Function(String command) exec,
  required Future<void> Function(String remotePath, List<int> bytes) upload,
  required List<int> bytes,
}) async {
  final home = (await exec(platform.isWindows
          ? r'cmd /c echo %USERPROFILE%'
          : 'printf %s "\$HOME"'))
      .trim();
  if (home.isEmpty) {
    throw Exception('HELPER_INSTALL_FAILED:无法确定远程用户目录');
  }
  final remotePath = helperInstallPath(
    platform: platform,
    homeDirectory: home,
    version: version,
  );
  final directory = platform.isWindows
      ? remotePath.substring(0, remotePath.lastIndexOf('\\'))
      : remotePath.substring(0, remotePath.lastIndexOf('/'));
  if (platform.isWindows) {
    await exec('cmd /c mkdir "$directory"');
  } else {
    await exec('mkdir -p ${_shQuote(directory)}');
  }
  await upload(remotePath, bytes);
  return remotePath;
}

String _sftpUploadPath(String path) {
  final slash = path.replaceAll('\\', '/');
  final drive = RegExp(r'^([a-zA-Z]):/(.*)$').firstMatch(slash);
  if (drive == null) return slash;
  return '/${drive.group(1)!.toLowerCase()}:/${drive.group(2)}';
}

String _shQuote(String value) {
  if (value.isEmpty) return "''";
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

Future<RemotePlatform> detectRemotePlatform(
  Future<String> Function(String command) exec,
) async {
  try {
    final uname = await exec('uname -sm');
    final parts = uname.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      final parsed = RemotePlatform.parseUname(parts[0], parts[1]);
      if (parsed != null) return parsed;
    }
  } catch (error) {
    Logger.info('[remote] uname failed, trying Windows: $error');
  }
  final arch = await exec(r'cmd /c echo %PROCESSOR_ARCHITECTURE%');
  final parsed = RemotePlatform.parseWindowsArchitecture(arch);
  if (parsed == null) {
    throw Exception('HELPER_INSTALL_FAILED:无法识别远程系统架构');
  }
  return parsed;
}

Future<List<int>> downloadReleaseAsset(Uri url) async {
  final response = await Dio().get<List<int>>(
    url.toString(),
    options: Options(
      responseType: ResponseType.bytes,
      followRedirects: true,
      receiveTimeout: const Duration(minutes: 2),
    ),
  );
  final bytes = response.data;
  if (response.statusCode != 200 || bytes == null) {
    throw Exception('HELPER_INSTALL_FAILED:下载远程服务失败 (${response.statusCode})');
  }
  return bytes;
}

/// SSH exec that returns stdout. A non-zero exit with empty stdout throws.
Future<String> execRemote(SSHClient client, String command) async {
  final session = await client.execute(command);
  final stdout = StringBuffer();
  final stderr = StringBuffer();
  await Future.wait([
    session.stdout
        .cast<List<int>>()
        .transform(utf8.decoder)
        .forEach(stdout.write),
    session.stderr
        .cast<List<int>>()
        .transform(utf8.decoder)
        .forEach(stderr.write),
  ]);
  await session.done;
  final out = stdout.toString();
  if ((session.exitCode ?? 1) != 0 && out.trim().isEmpty) {
    final err = stderr.toString().trim();
    throw Exception(err.isEmpty ? '远程命令失败' : err);
  }
  return out;
}

Future<void> uploadRemoteFile(
  SSHClient client,
  String remotePath,
  List<int> bytes,
) async {
  final sftp = await client.sftp();
  final file = await sftp.open(
    _sftpUploadPath(remotePath),
    mode: SftpFileOpenMode.write |
        SftpFileOpenMode.create |
        SftpFileOpenMode.truncate,
  );
  try {
    await file.write(Stream.value(Uint8List.fromList(bytes)));
  } finally {
    await file.close();
  }
}

Future<String> installHelperOnClient({
  required SSHClient client,
  required RemotePlatform platform,
  required String version,
}) {
  return ensureRemoteHelper(
    platform: platform,
    version: version,
    exec: (command) => execRemote(client, command),
    upload: (path, bytes) => uploadRemoteFile(client, path, bytes),
    download: downloadReleaseAsset,
  );
}

/// Command line the SSH session should execute for this gateway.
Future<String> remoteHelperCommand({
  required SSHClient client,
  required GatewayInfo target,
}) async {
  final exec = (String command) => execRemote(client, command);
  final platform = await detectRemotePlatform(exec);
  final prepared = await prepareGatewayLaunch(target, platform);
  final version = await currentAppVersion();
  final helperPath = await installHelperOnClient(
    client: client,
    platform: platform,
    version: version,
  );
  final archived =
      prepared.archiveUrl != null && prepared.archiveUrl!.isNotEmpty;
  final cwd = remoteLaunchDirectory(platform, prepared.workingDirectory);
  return buildRemoteHelperCommand(
    windows: platform.isWindows,
    helperPath: helperPath,
    sessionId: remoteAgentSessionId(
      connectionId: prepared.instanceTag.isEmpty
          ? prepared.connectionId
          : '${prepared.connectionId}|${prepared.instanceTag}',
      agentId: prepared.agentId,
      workingDirectory: cwd,
    ),
    workingDirectory: cwd,
    argv: archived ? prepared.args : [prepared.command, ...prepared.args],
    fresh: !prepared.resumeAgent,
    archiveUrl: prepared.archiveUrl,
    sha256: prepared.archiveSha256,
    agentId: prepared.agentId,
    agentVersion: prepared.agentVersion,
    relativeCommand: archived ? prepared.command : null,
    env: prepared.launchEnv,
    legacyArgv: prepared.legacyArgv,
  );
}
