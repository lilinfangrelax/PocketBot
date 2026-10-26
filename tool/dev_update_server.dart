import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pocket_bot/services/dev_update.dart';

/// Publishes the current release APK on this computer's Tailscale HTTPS name.
///
/// Run from `PocketBot/dev`:
///   dart run tool/dev_update_server.dart
///   dart run tool/dev_update_server.dart --build
Future<void> main(List<String> args) async {
  final build = args.contains('--build');
  String? apkArg;
  for (final arg in args) {
    if (!arg.startsWith('-')) {
      apkArg = arg;
      break;
    }
  }
  if (build) {
    final flutter = await Process.run(
      'flutter',
      const ['build', 'apk', '--release'],
      runInShell: true,
    );
    stdout.write(flutter.stdout);
    stderr.write(flutter.stderr);
    if (flutter.exitCode != 0) {
      exit(flutter.exitCode);
    }
  }

  final apk = File(apkArg ?? 'build/app/outputs/flutter-apk/app-release.apk');
  if (!await apk.exists()) {
    stderr.writeln('找不到安装包：${apk.path}');
    stderr.writeln('先编译：flutter build apk --release');
    stderr.writeln('或直接：dart run tool/dev_update_server.dart --build');
    exit(1);
  }

  final pubspec = File('pubspec.yaml');
  final version = await pubspec.exists()
      ? readPubspecVersion(await pubspec.readAsString())
      : null;
  if (version == null) {
    stderr.writeln('pubspec.yaml 里没有 version');
    exit(1);
  }

  final digest = await sha256.bind(apk.openRead()).first;
  final length = await apk.length();
  final manifest = DevUpdateManifest(
    version: version,
    sha256: digest.toString(),
    size: length,
    file: devUpdateApkName,
  );
  final manifestBytes = utf8.encode(jsonEncode(manifest.toJson()));

  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    devUpdateLocalPort,
  );
  server.listen((request) {
    unawaited(_handle(request, apk, length, manifestBytes));
  });

  stdout.writeln('已发布 $version（${apk.path}）');
  stdout.writeln('本机 http://127.0.0.1:$devUpdateLocalPort/update.json');

  final serve = await Process.run('tailscale', [
    'serve',
    '--bg',
    '--https=443',
    '--yes',
    'http://127.0.0.1:$devUpdateLocalPort',
  ]);
  final shortName = await Process.run('tailscale', [
    'serve',
    '--bg',
    '--http=80',
    '--yes',
    'http://127.0.0.1:$devUpdateLocalPort',
  ]);
  stdout.write(shortName.stdout);
  stderr.write(shortName.stderr);
  stdout.write(serve.stdout);
  stderr.write(serve.stderr);
  if (serve.exitCode != 0 || shortName.exitCode != 0) {
    stderr.writeln('Tailscale 地址没有全部挂上。确认管理后台已打开 HTTPS Certificates。');
  } else {
    stdout.writeln('短地址：http://$devUpdateServiceName/PocketBot.apk');
    stdout.writeln(
      '手机连着 Tailscale 时，在「开发机」通道检查更新即可，不用填写地址。',
    );
  }
  stdout.writeln('按 Ctrl+C 停止。');

  await _waitUntilStopped();
  await server.close(force: true);
  for (final args in [
    ['serve', '--https=443', 'off'],
    ['serve', '--http=80', 'off'],
  ]) {
    final clear = await Process.run('tailscale', args);
    stdout.write(clear.stdout);
    stderr.write(clear.stderr);
  }
}

Future<void> _waitUntilStopped() async {
  try {
    await ProcessSignal.sigint.watch().first;
  } on Object {
    await Completer<void>().future;
  }
}

Future<void> _handle(
  HttpRequest request,
  File apk,
  int length,
  List<int> manifestBytes,
) async {
  final response = request.response;
  try {
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      return;
    }
    final path = request.uri.path;
    if (path == '/update.json') {
      response.headers.contentType = ContentType.json;
      response.contentLength = manifestBytes.length;
      if (request.method != 'HEAD') response.add(manifestBytes);
      return;
    }
    if (path != '/$devUpdateApkName') {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final range = byteRangeForRequest(
      request.headers.value(HttpHeaders.rangeHeader),
      length,
    );
    if (range == null) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
      return;
    }
    final partial = range.start > 0 || range.end < length;
    if (partial) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.start}-${range.end - 1}/$length',
      );
    }
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = ContentType(
      'application',
      'vnd.android.package-archive',
    );
    response.contentLength = range.length;
    if (request.method != 'HEAD') {
      await response.addStream(apk.openRead(range.start, range.end));
    }
  } catch (error) {
    stderr.writeln('发布请求失败：$error');
    response.statusCode = HttpStatus.internalServerError;
  } finally {
    await response.close();
  }
}
