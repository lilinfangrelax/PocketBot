import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'agent_cache.dart';
import 'daemon.dart';
import 'paths.dart';

const pocketbotRemoteVersion = String.fromEnvironment(
  'POCKETBOT_VERSION',
  defaultValue: 'dev',
);

class RemoteRunOptions {
  final String home;
  final String session;
  final String cwd;
  final bool fresh;
  final String? archiveUrl;
  final String? sha256;
  final String? agentId;
  final String? agentVersion;
  final String? relativeCommand;
  final Map<String, String> env;
  final List<String> legacyArgv;
  final List<String> argv;

  const RemoteRunOptions({
    required this.home,
    required this.session,
    required this.cwd,
    required this.fresh,
    required this.argv,
    this.archiveUrl,
    this.sha256,
    this.agentId,
    this.agentVersion,
    this.relativeCommand,
    this.env = const {},
    this.legacyArgv = const [],
  });
}

RemoteRunOptions parseRunArgs(List<String> args, {String? home}) {
  final env = <String, String>{};
  final legacy = <String>[];
  String? session;
  String? cwd;
  String? archive;
  String? sha256;
  String? agentId;
  String? agentVersion;
  String? relativeCommand;
  var fresh = false;
  final argv = <String>[];
  var afterDash = false;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (afterDash) {
      argv.add(arg);
      continue;
    }
    switch (arg) {
      case '--':
        afterDash = true;
      case '--fresh':
        fresh = true;
      case '--session':
        session = args[++i];
      case '--cwd':
        cwd = args[++i];
      case '--home':
        home = args[++i];
      case '--archive':
        archive = args[++i];
      case '--sha256':
        sha256 = args[++i];
      case '--agent-id':
        agentId = args[++i];
      case '--agent-version':
        agentVersion = args[++i];
      case '--cmd':
        relativeCommand = args[++i];
      case '--env':
        final pair = args[++i];
        final eq = pair.indexOf('=');
        if (eq <= 0) throw FormatException('bad --env $pair');
        env[pair.substring(0, eq)] = pair.substring(eq + 1);
      case '--legacy':
        legacy.add(args[++i]);
      default:
        throw FormatException('unknown argument $arg');
    }
  }
  if (session == null || session.isEmpty) {
    throw const FormatException('missing --session');
  }
  if (cwd == null || cwd.isEmpty) {
    throw const FormatException('missing --cwd');
  }
  if (argv.isEmpty && (archive == null || archive.isEmpty)) {
    throw const FormatException('missing agent command');
  }
  return RemoteRunOptions(
    home: home ?? pocketbotHome(),
    session: session,
    cwd: cwd,
    fresh: fresh,
    archiveUrl: archive,
    sha256: sha256,
    agentId: agentId,
    agentVersion: agentVersion,
    relativeCommand: relativeCommand,
    env: env,
    legacyArgv: legacy,
    argv: argv,
  );
}

Future<int> runPocketbotRemote(List<String> args) async {
  if (args.isEmpty || args.first == 'version' || args.first == '--version') {
    stdout.writeln(pocketbotRemoteVersion);
    return 0;
  }
  if (args.first == 'daemon') {
    final home = _flag(args, '--home') ?? pocketbotHome();
    await _serveDaemon(home);
    return 0;
  }
  if (args.first == 'run') {
    final options = parseRunArgs(args.sublist(1));
    return _run(options);
  }
  stderr.writeln('usage: pocketbot-remote version|daemon|run');
  return 2;
}

String? _flag(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

Future<void> _serveDaemon(String home) async {
  Directory(home).createSync(recursive: true);
  final daemon = await RemoteDaemon.start(
    version: pocketbotRemoteVersion,
    spawn: spawnSystemAgent,
  );
  final endpoint = DaemonEndpoint(
    pid: pid,
    port: daemon.port,
    token: daemon.token,
    version: daemon.version,
  );
  final file = File('$home${Platform.pathSeparator}daemon.json');
  final tmp = File('${file.path}.tmp');
  tmp.writeAsStringSync(jsonEncode(endpoint.toJson()));
  tmp.renameSync(file.path);
  await Completer<void>().future;
}

Future<int> _run(RemoteRunOptions options) async {
  final argv = await resolveLaunchArgv(
    argv: options.argv,
    archiveUrl: options.archiveUrl,
    legacyArgv: options.legacyArgv,
    install: () => _install(options),
  );
  final endpoint = await _ensureDaemon(options.home);
  final socket = await Socket.connect(
    InternetAddress.loopbackIPv4,
    endpoint.port,
  );
  socket.write('${jsonEncode({
        'token': endpoint.token,
        'op': 'attach',
        'session': options.session,
        'cwd': options.cwd,
        'argv': argv,
        'env': options.env,
        'fresh': options.fresh,
      })}\n');
  final gate = _StdoutGate(socket);
  final line = await gate.line.timeout(const Duration(seconds: 30));
  final reply = jsonDecode(line);
  if (reply is! Map || reply['ok'] != true) {
    final error = reply is Map ? reply['error'] : reply;
    stderr.writeln('POCKETBOT error=$error');
    await socket.close();
    return 1;
  }
  stderr.writeln('POCKETBOT resumed=${reply['resumed'] == true}');
  await stderr.flush();
  if (gate.rest.isNotEmpty) stdout.add(gate.rest);
  final stdoutSub = gate.restOfStream.listen(stdout.add);
  final stdinSub = stdin.listen(socket.add);
  final code = Completer<int>();
  socket.done.then((_) {
    if (!code.isCompleted) code.complete(0);
  });
  await code.future;
  await stdoutSub.cancel();
  await stdinSub.cancel();
  return 0;
}

Future<List<String>> _install(RemoteRunOptions options) {
  final id = options.agentId ?? 'agent';
  final version = options.agentVersion ?? '0';
  final command = options.relativeCommand ?? options.argv.first;
  return ensureCachedAgent(
    root: Directory(options.home),
    agentId: id,
    version: version,
    archiveUrl: options.archiveUrl!,
    sha256: options.sha256,
    command: command,
    args: options.argv,
    download: _download,
  ).then((cached) => cached.argv);
}

Future<List<int>> _download(Uri url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode} for $url');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  } finally {
    client.close();
  }
}

Future<DaemonEndpoint> _ensureDaemon(String home) async {
  Directory(home).createSync(recursive: true);
  final file = File('$home${Platform.pathSeparator}daemon.json');
  final existing = file.existsSync()
      ? DaemonEndpoint.fromJson(file.readAsStringSync())
      : null;
  if (existing != null &&
      existing.version == pocketbotRemoteVersion &&
      await _ping(existing)) {
    return existing;
  }
  if (existing != null) await _killPid(existing.pid);
  final starting = File('$home${Platform.pathSeparator}daemon.starting');
  try {
    starting.createSync(exclusive: true);
  } on FileSystemException {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final waited = file.existsSync()
          ? DaemonEndpoint.fromJson(file.readAsStringSync())
          : null;
      if (waited != null && await _ping(waited)) return waited;
    }
  }
  try {
    await _spawnDaemon(home);
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final started = file.existsSync()
          ? DaemonEndpoint.fromJson(file.readAsStringSync())
          : null;
      if (started != null &&
          started.version == pocketbotRemoteVersion &&
          await _ping(started)) {
        return started;
      }
    }
    throw Exception('remote daemon did not start');
  } finally {
    if (starting.existsSync()) starting.deleteSync();
  }
}

Future<void> _spawnDaemon(String home) async {
  final script = Platform.script.toFilePath();
  final compiled = !script.endsWith('.dart');
  final executable = Platform.resolvedExecutable;
  final args = compiled
      ? ['daemon', '--home', home]
      : [script, 'daemon', '--home', home];
  await Process.start(
    executable,
    args,
    mode: ProcessStartMode.detached,
  );
}

Future<bool> _ping(DaemonEndpoint endpoint) async {
  try {
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      endpoint.port,
      timeout: const Duration(milliseconds: 400),
    );
    socket.write('${jsonEncode({
          'token': endpoint.token,
          'op': 'ping',
        })}\n');
    final line = await socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(milliseconds: 400));
    await socket.close();
    final reply = jsonDecode(line);
    return reply is Map && reply['ok'] == true && reply['version'] == endpoint.version;
  } catch (_) {
    return false;
  }
}

Future<void> _killPid(int pid) async {
  if (pid <= 0) return;
  try {
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/F', '/PID', '$pid']);
    } else {
      Process.killPid(pid);
    }
  } catch (_) {}
}

class _StdoutGate {
  _StdoutGate(Socket socket) {
    final builder = BytesBuilder(copy: false);
    socket.listen(
      (chunk) {
        if (_line.isCompleted) {
          _pending.add(chunk);
          return;
        }
        builder.add(chunk);
        final bytes = builder.toBytes();
        final newline = bytes.indexOf(10);
        if (newline < 0) return;
        final text = utf8.decode(bytes.sublist(0, newline)).trimRight();
        final extra = bytes.sublist(newline + 1);
        if (extra.isNotEmpty) _rest.addAll(extra);
        _line.complete(text);
      },
      onDone: () {
        if (!_line.isCompleted) _line.completeError(StateError('closed'));
        _pending.close();
      },
      onError: (Object error) {
        if (!_line.isCompleted) _line.completeError(error);
        _pending.addError(error);
      },
    );
  }

  final _line = Completer<String>();
  final _rest = <int>[];
  final _pending = StreamController<List<int>>();

  Future<String> get line => _line.future;
  List<int> get rest => List<int>.from(_rest);
  Stream<List<int>> get restOfStream => _pending.stream;
}
