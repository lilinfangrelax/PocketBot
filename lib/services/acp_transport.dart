import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/cursor_agent.dart';
import 'package:pocket_bot/utils/logger.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Byte/text pipe that carries ACP JSON-RPC frames.
abstract class AcpTransport {
  Stream<dynamic> get incoming;

  void send(String jsonFrame);

  Future<void> close();
}

/// Splits stdio ACP traffic into one JSON object per line.
class NdjsonBuffer {
  String _pending = '';

  List<String> add(String chunk) {
    if (chunk.isEmpty) return const [];
    var text = chunk;
    if (text.contains('\r')) {
      text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    }
    final combined = _pending.isEmpty ? text : '$_pending$text';
    final lines = <String>[];
    var start = 0;
    while (true) {
      final index = combined.indexOf('\n', start);
      if (index < 0) break;
      final line = combined.substring(start, index).trim();
      start = index + 1;
      if (line.isNotEmpty) lines.add(line);
    }
    _pending = combined.substring(start);
    return lines;
  }
}

/// Merges high-frequency `agent_message_chunk` / `agent_thought_chunk`
/// frames so the UI isolate is not flooded with one-token JSON maps.
class AcpTextChunkCoalescer {
  AcpTextChunkCoalescer({
    required this.emit,
    this.interval = const Duration(milliseconds: 32),
  });

  final void Function(Map<String, dynamic>) emit;
  final Duration interval;
  Timer? _timer;
  Map<String, dynamic>? _pending;
  final StringBuffer _text = StringBuffer();

  void add(dynamic decoded) {
    if (decoded is Map) {
      final message = Map<String, dynamic>.from(decoded);
      if (_isTextChunk(message)) {
        final text = _chunkText(message);
        if (_pending != null && _sameStream(_pending!, message)) {
          _text.write(text);
        } else {
          flush();
          _pending = message;
          _text.write(text);
        }
        _timer ??= Timer(interval, flush);
        return;
      }
      flush();
      emit(message);
      return;
    }
    flush();
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    final pending = _pending;
    if (pending == null) return;
    _setChunkText(pending, _text.toString());
    _pending = null;
    _text.clear();
    emit(pending);
  }

  static bool _isTextChunk(Map<String, dynamic> message) {
    if (message['method'] != 'session/update') return false;
    final params = message['params'];
    if (params is! Map) return false;
    final update = params['update'];
    if (update is! Map) return false;
    final kind = update['sessionUpdate'];
    if (kind != 'agent_message_chunk' && kind != 'agent_thought_chunk') {
      return false;
    }
    final content = update['content'];
    if (content is! Map) return false;
    final type = content['type'];
    return type == 'text' || type == null;
  }

  static String _chunkText(Map<String, dynamic> message) {
    final params = message['params'];
    if (params is! Map) return '';
    final update = params['update'];
    if (update is! Map) return '';
    final content = update['content'];
    if (content is! Map) return '';
    return content['text'] as String? ?? '';
  }

  static void _setChunkText(Map<String, dynamic> message, String text) {
    final params = message['params'];
    if (params is! Map) return;
    final update = params['update'];
    if (update is! Map) return;
    final content = update['content'];
    if (content is! Map) return;
    content['text'] = text;
  }

  static bool _sameStream(Map<String, dynamic> a, Map<String, dynamic> b) {
    final paramsA = a['params'];
    final paramsB = b['params'];
    if (paramsA is! Map || paramsB is! Map) return false;
    if (paramsA['sessionId'] != paramsB['sessionId']) return false;
    final updateA = paramsA['update'];
    final updateB = paramsB['update'];
    if (updateA is! Map || updateB is! Map) return false;
    if (updateA['sessionUpdate'] != updateB['sessionUpdate']) return false;
    return updateA['messageId'] == updateB['messageId'];
  }
}

bool looksLikeWindowsPath(String path) {
  return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) || path.startsWith(r'\\');
}

/// SFTP on Windows OpenSSH prefers forward slashes (`C:/Users`).
String toSftpPath(String path) => path.replaceAll('\\', '/');

String joinRemotePath(String parent, String name) {
  if (name.isEmpty || name == '.') return parent;
  if (name == '..') return parentRemotePath(parent);
  if (parent.isEmpty || parent == '/') return '/$name';
  if (looksLikeWindowsPath(parent) || parent.contains('\\')) {
    final trimmed = parent.replaceAll(RegExp(r'[\\/]+$'), '');
    return '$trimmed\\$name';
  }
  return '${parent.replaceAll(RegExp(r'/+$'), '')}/$name';
}

String parentRemotePath(String path) {
  final normalized = path.replaceAll(RegExp(r'[\\/]+$'), '');
  if (normalized.isEmpty) return '/';
  if (RegExp(r'^[a-zA-Z]:$').hasMatch(normalized)) {
    return '$normalized\\';
  }
  if (looksLikeWindowsPath(path) || path.contains('\\')) {
    final index = normalized.lastIndexOf('\\');
    if (index < 0) return normalized;
    if (index <= 2 && RegExp(r'^[a-zA-Z]:').hasMatch(normalized)) {
      return '${normalized.substring(0, 2)}\\';
    }
    return normalized.substring(0, index);
  }
  final index = normalized.lastIndexOf('/');
  if (index <= 0) return '/';
  return normalized.substring(0, index);
}

bool isRemoteRoot(String path) {
  final trimmed = path.trim();
  return trimmed.isEmpty ||
      trimmed == '/' ||
      trimmed == '.' ||
      RegExp(r'^[a-zA-Z]:[\\/]?$').hasMatch(trimmed);
}

String shQuote(String value) {
  if (value.isEmpty) return "''";
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

/// Remote command used after SSH login: same ACP agent, stdio unchanged.
String buildRemoteAgentCommand({
  required String workingDirectory,
  required String command,
  required List<String> args,
}) {
  final cwd = workingDirectory.trim().isEmpty ? '.' : workingDirectory;
  if (looksLikeWindowsPath(cwd)) {
    final joined = [command, ...args].join(' ');
    final escaped = cwd.replaceAll('"', '');
    return 'cmd /c "cd /d $escaped && $joined"';
  }
  final quotedArgs = [command, ...args].map(shQuote).join(' ');
  return 'cd ${shQuote(cwd)} && $quotedArgs';
}

Future<SSHClient> openSshClient(GatewayInfo target) async {
  if (target.host.trim().isEmpty) {
    throw Exception('CONNECTION_FAILED:请填写 SSH 主机地址');
  }
  if (target.username.trim().isEmpty) {
    throw Exception('AUTH_FAILED:请填写 SSH 用户名');
  }
  if (target.token.isEmpty && target.privateKey.trim().isEmpty) {
    throw Exception('AUTH_FAILED:请提供 SSH 密码或私钥');
  }

  Logger.info(
    '[ACP] SSH ${target.username}@${target.host}:${target.port}',
  );

  SSHClient? client;
  try {
    final socket = await SSHSocket.connect(
      target.host,
      target.port,
      timeout: const Duration(seconds: 15),
    );
    client = SSHClient(
      socket,
      username: target.username,
      identities: target.privateKey.trim().isEmpty
          ? null
          : SSHKeyPair.fromPem(target.privateKey),
      onPasswordRequest: target.token.isEmpty ? null : () => target.token,
    );
    await client.authenticated.timeout(const Duration(seconds: 20));
    return client;
  } catch (error) {
    client?.close();
    final text = error.toString().toLowerCase();
    if (text.contains('auth') ||
        text.contains('password') ||
        text.contains('permission denied') ||
        text.contains('pem')) {
      throw Exception('AUTH_FAILED:SSH 认证失败，请检查用户名、密码或私钥');
    }
    if (text.contains('timeout')) {
      throw Exception('CONNECTION_TIMEOUT:SSH 连接超时');
    }
    if (text.contains('refused') || text.contains('unreachable')) {
      throw Exception(
        'CONNECTION_REFUSED:无法连接到 SSH 主机 ${target.host}:${target.port}',
      );
    }
    throw Exception('CONNECTION_FAILED:SSH 连接失败: $error');
  }
}

class AcpTransportFactory {
  static Future<AcpTransport> open(GatewayInfo target) {
    switch (target.kind) {
      case AgentTransportKind.local:
        return LocalStdioTransport.start(target);
      case AgentTransportKind.ssh:
        return SshStdioTransport.start(target);
    }
  }
}

class LocalStdioTransport implements AcpTransport {
  LocalStdioTransport._({
    required ReceivePort receivePort,
    required SendPort commandPort,
    required Isolate isolate,
    required StreamController<dynamic> incoming,
  })  : _receivePort = receivePort,
        _commandPort = commandPort,
        _isolate = isolate,
        _incoming = incoming;

  final ReceivePort _receivePort;
  final SendPort _commandPort;
  final Isolate _isolate;
  final StreamController<dynamic> _incoming;
  bool _closed = false;

  static Future<LocalStdioTransport> start(GatewayInfo target) async {
    final cwd = CursorAgent.resolveWorkingDirectory(target.workingDirectory);
    final directory = Directory(cwd);
    if (!directory.existsSync()) {
      throw Exception('AGENT_SPAWN_FAILED:工作目录不存在: $cwd');
    }

    final resolved = await CursorAgent.resolve(target.command);
    Logger.info(
      '[ACP] Spawning ${resolved.executable} ${[...resolved.prefixArgs, ...target.args].join(' ')} in $cwd',
    );

    final receivePort = ReceivePort();
    final ready = Completer<SendPort>();
    final incoming = StreamController<dynamic>.broadcast();
    Isolate? isolate;

    receivePort.listen((message) {
      if (message is! Map) return;
      switch (message['type']) {
        case 'ready':
          if (!ready.isCompleted) {
            ready.complete(message['sendPort'] as SendPort);
          }
        case 'frame':
          if (!incoming.isClosed) incoming.add(message['payload']);
        case 'stderr':
          final text = (message['text'] as String?)?.trim() ?? '';
          if (text.isNotEmpty) Logger.warning('[ACP agent] $text');
        case 'exit':
          final code = message['code'] as int? ?? -1;
          Logger.warning('[ACP] Local agent exited with code $code');
          if (!incoming.isClosed) {
            incoming.addError(Exception('Agent exited with code $code'));
            incoming.close();
          }
        case 'error':
          final error = Exception(
            message['message'] as String? ?? 'ACP isolate error',
          );
          if (!ready.isCompleted) {
            ready.completeError(error);
          } else if (!incoming.isClosed) {
            incoming.addError(error);
          }
        case 'done':
          if (!incoming.isClosed) incoming.close();
      }
    });

    try {
      isolate = await Isolate.spawn(
        acpStdioIsolateMain,
        <String, dynamic>{
          'replyPort': receivePort.sendPort,
          'executable': resolved.executable,
          'args': <String>[...resolved.prefixArgs, ...target.args],
          'workingDirectory': cwd,
          'runInShell': resolved.runInShell,
          'environment': <String, String>{
            ...Platform.environment,
            'NO_COLOR': '1',
          },
        },
        debugName: 'acp-stdio',
        errorsAreFatal: false,
      );
      final commandPort = await ready.future.timeout(
        const Duration(seconds: 30),
      );
      return LocalStdioTransport._(
        receivePort: receivePort,
        commandPort: commandPort,
        isolate: isolate,
        incoming: incoming,
      );
    } catch (error) {
      receivePort.close();
      isolate?.kill(priority: Isolate.immediate);
      throw Exception('AGENT_SPAWN_FAILED:无法启动 Cursor Agent: $error');
    }
  }

  @override
  Stream<dynamic> get incoming => _incoming.stream;

  @override
  void send(String jsonFrame) {
    try {
      _commandPort.send(<String, dynamic>{
        'type': 'send',
        'frame': jsonFrame,
      });
    } catch (error) {
      Logger.error('[ACP] Failed to write to agent stdin: $error');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _commandPort.send(const <String, dynamic>{'type': 'close'});
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _isolate.kill(priority: Isolate.immediate);
    _receivePort.close();
    if (!_incoming.isClosed) await _incoming.close();
  }
}

/// Owns the ACP child process, UTF-8 decode, NDJSON split, and jsonDecode
/// so the UI isolate only receives already-parsed maps.
@pragma('vm:entry-point')
void acpStdioIsolateMain(dynamic raw) {
  final args = Map<String, dynamic>.from(raw as Map);
  final replyPort = args['replyPort'] as SendPort;
  final commandPort = ReceivePort();
  replyPort.send(<String, dynamic>{
    'type': 'ready',
    'sendPort': commandPort.sendPort,
  });

  () async {
    Process? process;
    try {
      process = await Process.start(
        args['executable'] as String,
        List<String>.from(args['args'] as List),
        workingDirectory: args['workingDirectory'] as String?,
        runInShell: args['runInShell'] as bool? ?? false,
        environment: Map<String, String>.from(args['environment'] as Map),
      );
    } catch (error) {
      replyPort.send(<String, dynamic>{
        'type': 'error',
        'message': '$error',
      });
      commandPort.close();
      return;
    }

    final coalescer = AcpTextChunkCoalescer(
      emit: (frame) => replyPort.send(<String, dynamic>{
        'type': 'frame',
        'payload': frame,
      }),
    );
    final buffer = NdjsonBuffer();

    process.stdout.transform(utf8.decoder).listen(
      (chunk) {
        for (final line in buffer.add(chunk)) {
          try {
            coalescer.add(jsonDecode(line));
          } catch (error) {
            coalescer.flush();
            replyPort.send(<String, dynamic>{
              'type': 'error',
              'message': 'Invalid ACP JSON: $error',
            });
          }
        }
      },
      onError: (Object error) {
        coalescer.flush();
        replyPort.send(<String, dynamic>{
          'type': 'error',
          'message': '$error',
        });
      },
      onDone: () {
        coalescer.flush();
        replyPort.send(const <String, dynamic>{'type': 'done'});
      },
    );
    process.stderr.transform(utf8.decoder).listen((chunk) {
      final text = chunk.trim();
      if (text.isNotEmpty) {
        replyPort.send(<String, dynamic>{'type': 'stderr', 'text': text});
      }
    });
    process.exitCode.then((code) {
      coalescer.flush();
      replyPort.send(<String, dynamic>{'type': 'exit', 'code': code});
    });

    await for (final cmd in commandPort) {
      if (cmd is! Map) continue;
      final type = cmd['type'];
      if (type == 'send') {
        try {
          process.stdin.add(utf8.encode('${cmd['frame']}\n'));
        } catch (error) {
          replyPort.send(<String, dynamic>{
            'type': 'error',
            'message': 'stdin: $error',
          });
        }
      } else if (type == 'close') {
        coalescer.flush();
        try {
          process.kill();
        } catch (_) {}
        commandPort.close();
        break;
      }
    }
  }();
}

class SshStdioTransport implements AcpTransport {
  SshStdioTransport._(this._client, this._session, this._incoming);

  final SSHClient _client;
  final SSHSession _session;
  final StreamController<dynamic> _incoming;
  final NdjsonBuffer _buffer = NdjsonBuffer();
  bool _closed = false;

  static Future<SshStdioTransport> start(GatewayInfo target) async {
    final client = await openSshClient(target);
    try {
      return await attach(client: client, target: target);
    } catch (error) {
      client.close();
      rethrow;
    }
  }

  static Future<SshStdioTransport> attach({
    required SSHClient client,
    required GatewayInfo target,
  }) async {
    final cwd = target.workingDirectory.trim().isEmpty
        ? '.'
        : target.workingDirectory;
    final remoteCommand = buildRemoteAgentCommand(
      workingDirectory: cwd,
      command: target.command,
      args: target.args,
    );
    Logger.info(
      '[ACP] SSH ${target.username}@${target.host}:${target.port} → $remoteCommand',
    );

    try {
      final session = await client.execute(remoteCommand);
      final incoming = StreamController<dynamic>.broadcast();
      final transport = SshStdioTransport._(client, session, incoming);

      session.stdout.cast<List<int>>().transform(utf8.decoder).listen(
        transport._onStdout,
        onError: incoming.addError,
        onDone: () {
          if (!incoming.isClosed) incoming.close();
        },
      );
      session.stderr.cast<List<int>>().transform(utf8.decoder).listen((chunk) {
        final text = chunk.trim();
        if (text.isNotEmpty) Logger.warning('[ACP ssh] $text');
      });
      session.done.then((_) {
        if (transport._closed) return;
        Logger.warning('[ACP] Remote agent session closed');
        if (!incoming.isClosed) {
          incoming.addError(Exception('SSH agent session closed'));
          incoming.close();
        }
      });
      return transport;
    } catch (error) {
      throw Exception('CONNECTION_FAILED:无法在远程主机启动 Agent: $error');
    }
  }

  void _onStdout(String chunk) {
    for (final line in _buffer.add(chunk)) {
      if (!_incoming.isClosed) _incoming.add(line);
    }
  }

  @override
  Stream<dynamic> get incoming => _incoming.stream;

  @override
  void send(String jsonFrame) {
    _session.stdin.add(Uint8List.fromList(utf8.encode('$jsonFrame\n')));
  }

  @override
  Future<void> close() async {
    _closed = true;
    try {
      _session.close();
    } catch (_) {}
    try {
      _client.close();
    } catch (_) {}
    if (!_incoming.isClosed) await _incoming.close();
  }
}

class WebSocketAcpTransport implements AcpTransport {
  WebSocketAcpTransport._(this._channel, this._incoming);

  final WebSocketChannel _channel;
  final StreamController<dynamic> _incoming;

  static Future<WebSocketAcpTransport> connect({
    required String host,
    required int port,
    required String token,
    String endpointPath = '/acp',
    bool secure = false,
    WebSocketChannel Function(Uri)? connectionFactory,
  }) async {
    final trimmed = endpointPath.trim();
    final path = trimmed.isEmpty
        ? '/acp'
        : (trimmed.startsWith('/') ? trimmed : '/$trimmed');
    final uri = Uri(
      scheme: secure ? 'wss' : 'ws',
      host: host,
      port: port,
      path: path,
    );
    Logger.info('[ACP] Connecting to $uri');
    final channel = connectionFactory?.call(uri) ??
        IOWebSocketChannel.connect(
          uri,
          headers: token.isEmpty
              ? null
              : <String, dynamic>{'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 10),
        );
    await channel.ready.timeout(const Duration(seconds: 10));
    final incoming = StreamController<dynamic>.broadcast();
    channel.stream.listen(
      (data) {
        if (data is String && data.trim().isNotEmpty && !incoming.isClosed) {
          incoming.add(data);
        }
      },
      onError: incoming.addError,
      onDone: incoming.close,
    );
    return WebSocketAcpTransport._(channel, incoming);
  }

  @override
  Stream<dynamic> get incoming => _incoming.stream;

  @override
  void send(String jsonFrame) {
    _channel.sink.add(jsonFrame);
  }

  @override
  Future<void> close() async {
    await _channel.sink.close();
    if (!_incoming.isClosed) await _incoming.close();
  }
}
