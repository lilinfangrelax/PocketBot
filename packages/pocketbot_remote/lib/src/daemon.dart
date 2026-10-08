import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const remoteOutputBufferLimit = 1024 * 1024;

class ManagedAgent {
  final Stream<List<int>> stdout;
  final Stream<List<int>> stderr;
  final void Function(List<int> data) writeStdin;
  final Future<int> exitCode;
  final void Function() kill;

  const ManagedAgent({
    required this.stdout,
    required this.stderr,
    required this.writeStdin,
    required this.exitCode,
    required this.kill,
  });

  factory ManagedAgent.fromProcess(Process process) {
    return ManagedAgent(
      stdout: process.stdout,
      stderr: process.stderr,
      writeStdin: (data) {
        try {
          process.stdin.add(data);
        } catch (_) {}
      },
      exitCode: process.exitCode,
      kill: () {
        try {
          process.kill();
        } catch (_) {}
      },
    );
  }
}

class AgentLaunch {
  final String cwd;
  final List<String> argv;
  final Map<String, String> env;

  const AgentLaunch({
    required this.cwd,
    required this.argv,
    this.env = const {},
  });
}

typedef AgentSpawner = Future<ManagedAgent> Function(AgentLaunch launch);

class DaemonEndpoint {
  final int pid;
  final int port;
  final String token;
  final String version;

  const DaemonEndpoint({
    required this.pid,
    required this.port,
    required this.token,
    required this.version,
  });

  Map<String, dynamic> toJson() => {
        'pid': pid,
        'port': port,
        'token': token,
        'version': version,
      };

  static DaemonEndpoint? fromJson(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final pid = json['pid'];
      final port = json['port'];
      final token = json['token'];
      final version = json['version'];
      if (pid is! int || port is! int || token is! String || version is! String) {
        return null;
      }
      return DaemonEndpoint(pid: pid, port: port, token: token, version: version);
    } catch (_) {
      return null;
    }
  }
}

/// Loopback daemon. SSH sessions attach and detach; the agent process stays.
class RemoteDaemon {
  RemoteDaemon._(this.version, this.token, this._spawn, this._server);

  final String version;
  final String token;
  final AgentSpawner _spawn;
  final ServerSocket _server;
  final Map<String, _AgentSession> _sessions = {};

  int get port => _server.port;

  static Future<RemoteDaemon> start({
    required String version,
    required AgentSpawner spawn,
    String? token,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final daemon = RemoteDaemon._(
      version,
      token ?? _randomToken(),
      spawn,
      server,
    );
    server.listen(daemon._onSocket);
    return daemon;
  }

  Future<void> close() async {
    for (final session in _sessions.values) {
      session.stop();
    }
    _sessions.clear();
    await _server.close();
  }

  Future<void> _onSocket(Socket socket) async {
    final gate = _LineGate(socket);
    try {
      final line = await gate.line.timeout(const Duration(seconds: 10));
      final message = jsonDecode(line);
      if (message is! Map) {
        await _reject(socket, 'invalid handshake');
        return;
      }
      if (message['token'] != token) {
        await _reject(socket, 'bad token');
        return;
      }
      final op = message['op'];
      if (op == 'ping') {
        socket.write('${jsonEncode({'ok': true, 'version': version})}\n');
        await socket.flush();
        await socket.close();
        return;
      }
      if (op != 'attach') {
        await _reject(socket, 'unknown op');
        return;
      }
      final sessionId = message['session'] as String? ?? '';
      if (sessionId.isEmpty) {
        await _reject(socket, 'missing session');
        return;
      }
      if (message['fresh'] == true) {
        _sessions.remove(sessionId)?.stop();
      }
      var session = _sessions[sessionId];
      final resumed = session != null && !session.exited;
      if (!resumed) {
        final argv = (message['argv'] as List? ?? const [])
            .map((item) => item.toString())
            .toList();
        if (argv.isEmpty) {
          await _reject(socket, 'missing argv');
          return;
        }
        final env = <String, String>{};
        final rawEnv = message['env'];
        if (rawEnv is Map) {
          rawEnv.forEach((key, value) => env['$key'] = '$value');
        }
        try {
          final agent = await _spawn(AgentLaunch(
            cwd: message['cwd'] as String? ?? '.',
            argv: argv,
            env: env,
          ));
          session = _AgentSession(agent);
          _sessions[sessionId] = session;
        } catch (error) {
          await _reject(socket, '$error');
          return;
        }
      }
      if (session.overflow) {
        await _reject(socket, 'agent output was lost while disconnected');
        return;
      }
      socket.write('${jsonEncode({'ok': true, 'resumed': resumed})}\n');
      await socket.flush();
      final attached = session;
      gate.onClosed = () => attached.detach(socket);
      attached.attach(socket, gate.rest);
      unawaited(gate.restOfStream.forEach(session.writeStdin));
    } catch (error) {
      await _reject(socket, '$error');
    }
  }

  Future<void> _reject(Socket socket, String error) async {
    try {
      socket.write('${jsonEncode({'ok': false, 'error': error})}\n');
      await socket.flush();
      await socket.close();
    } catch (_) {}
  }

  static String _randomToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _LineGate {
  _LineGate(Socket socket) {
    final builder = BytesBuilder(copy: false);
    _subscription = socket.listen(
      (chunk) {
        if (_line.isCompleted) {
          if (!_restReady.isCompleted) {
            _rest.add(chunk);
          } else {
            _pending.add(chunk);
          }
          return;
        }
        builder.add(chunk);
        final bytes = builder.toBytes();
        final newline = bytes.indexOf(10);
        if (newline < 0) return;
        final text = utf8.decode(bytes.sublist(0, newline)).trimRight();
        final extra = bytes.sublist(newline + 1);
        if (extra.isNotEmpty) _rest.add(extra);
        builder.clear();
        _line.complete(text);
        _restReady.complete();
      },
      onError: (Object error) {
        if (!_line.isCompleted) _line.completeError(error);
        if (!_restReady.isCompleted) _restReady.complete();
        if (!_pending.isClosed) _pending.addError(error);
      },
      onDone: () {
        if (!_line.isCompleted) _line.completeError(StateError('closed'));
        if (!_restReady.isCompleted) _restReady.complete();
        if (!_pending.isClosed) _pending.close();
        onClosed?.call();
      },
    );
    _restOfStream = _streamAfterLine();
  }

  void Function()? onClosed;

  final _line = Completer<String>();
  final _restReady = Completer<void>();
  final _rest = <List<int>>[];
  final _pending = StreamController<List<int>>();
  // Held so the socket subscription stays alive for the life of the gate.
  // ignore: unused_field
  late final StreamSubscription<List<int>> _subscription;
  late final Stream<List<int>> _restOfStream;

  Future<String> get line => _line.future;
  List<int> get rest => _rest.expand((chunk) => chunk).toList();
  Stream<List<int>> get restOfStream => _restOfStream;

  Stream<List<int>> _streamAfterLine() async* {
    await _restReady.future;
    yield* _pending.stream;
  }
}

class _AgentSession {
  _AgentSession(this.agent) {
    _stdoutSub = agent.stdout.listen(_onStdout, onDone: _onAgentDone);
    _stderrSub = agent.stderr.listen((data) {
      if (_stderr.length > 8000) return;
      _stderr.write(utf8.decode(data, allowMalformed: true));
    });
    agent.exitCode.then((_) => _onAgentDone());
  }

  final ManagedAgent agent;
  final List<int> _buffer = [];
  final StringBuffer _stderr = StringBuffer();
  Socket? _client;
  bool exited = false;
  bool overflow = false;
  Future<void> _sendLock = Future<void>.value();
  late final StreamSubscription<List<int>> _stdoutSub;
  late final StreamSubscription<List<int>> _stderrSub;

  String get stderrText => _stderr.toString();

  void detach(Socket socket) {
    if (identical(_client, socket)) _client = null;
  }

  void attach(Socket socket, List<int> alreadyRead) {
    _client?.destroy();
    _client = socket;
    if (_buffer.isNotEmpty) {
      socket.add(List<int>.from(_buffer));
      _buffer.clear();
    }
    if (alreadyRead.isNotEmpty) writeStdin(alreadyRead);
    socket.done.then((_) {
      if (identical(_client, socket)) _client = null;
    });
  }

  void writeStdin(List<int> data) {
    if (data.isEmpty || exited) return;
    agent.writeStdin(data);
  }

  void _onStdout(List<int> data) {
    _sendLock = _sendLock.then((_) => _send(data));
  }

  Future<void> _send(List<int> data) async {
    final client = _client;
    if (client == null || exited) {
      _remember(data);
      return;
    }
    try {
      client.add(data);
      await client.flush();
    } catch (_) {
      if (identical(_client, client)) _client = null;
      _remember(data);
    }
  }

  void _remember(List<int> data) {
    if (overflow || exited) return;
    if (_buffer.length + data.length > remoteOutputBufferLimit) {
      overflow = true;
      _buffer.clear();
      stop();
      return;
    }
    _buffer.addAll(data);
  }

  void _onAgentDone() {
    if (exited) return;
    exited = true;
    final client = _client;
    _client = null;
    client?.destroy();
  }

  void stop() {
    exited = true;
    agent.kill();
    _stdoutSub.cancel();
    _stderrSub.cancel();
    _client?.destroy();
    _client = null;
  }
}

/// Locate `command` on PATH, including Windows PATHEXT.
String resolveOnPath(String command) {
  if (command.contains('/') || command.contains('\\')) return command;
  final direct = File(command);
  if (direct.isAbsolute && direct.existsSync()) return command;
  final path = Platform.environment['PATH'] ?? '';
  if (path.isEmpty) return command;
  final separator = Platform.isWindows ? ';' : ':';
  final extensions = Platform.isWindows
      ? (Platform.environment['PATHEXT'] ?? '.COM;.EXE;.BAT;.CMD').split(';')
      : const <String>[''];
  for (final dir in path.split(separator)) {
    if (dir.isEmpty) continue;
    final plain = File('$dir${Platform.pathSeparator}$command');
    if (plain.existsSync()) return plain.path;
    for (final ext in extensions) {
      if (ext.isEmpty) continue;
      final candidate = File('$dir${Platform.pathSeparator}$command$ext');
      if (candidate.existsSync()) return candidate.path;
    }
  }
  return command;
}

Future<ManagedAgent> spawnSystemAgent(AgentLaunch launch) async {
  if (launch.argv.isEmpty) {
    throw Exception('missing agent command');
  }
  var executable = resolveOnPath(launch.argv.first);
  var args = launch.argv.sublist(1);
  if (Platform.isWindows && _isBatch(executable)) {
    final command = [executable, ...args].map(_cmdArg).join(' ');
    args = ['/d', '/s', '/c', 'call $command'];
    executable = Platform.environment['COMSPEC'] ?? 'cmd.exe';
  }
  final process = await Process.start(
    executable,
    args,
    workingDirectory: launch.cwd,
    environment: {
      ...Platform.environment,
      ...launch.env,
      'NO_COLOR': '1',
    },
  );
  return ManagedAgent.fromProcess(process);
}

bool _isBatch(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.cmd') || lower.endsWith('.bat');
}

String _cmdArg(String value) {
  if (value.isEmpty) return '""';
  if (RegExp(r'[\s"&|<>^]').hasMatch(value)) {
    return '"${value.replaceAll('"', '')}"';
  }
  return value;
}
