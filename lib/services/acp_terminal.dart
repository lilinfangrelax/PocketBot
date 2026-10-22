import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Number of output bytes retained when the agent omits `outputByteLimit`.
const int defaultTerminalOutputLimit = 1024 * 1024;

/// Runs agent-requested `terminal/*` commands.
///
/// The capability is advertised only when a host is available so commands
/// always run in the same environment as the agent.
abstract class AcpTerminalHost {
  Future<AcpTerminal> create({
    required String command,
    required List<String> args,
    required Map<String, String> environment,
    String? cwd,
    int? outputByteLimit,
  });

  Future<void> dispose();
}

abstract class AcpTerminal {
  String get output;

  bool get truncated;

  bool get hasExited;

  int? get exitCode;

  String? get signal;

  /// Completes once the process exited and both output streams are drained.
  Future<void> get exited;

  Future<void> kill();

  Future<void> release();
}

class LocalAcpTerminalHost implements AcpTerminalHost {
  final Set<LocalAcpTerminal> _terminals = {};
  bool _disposed = false;

  @override
  Future<AcpTerminal> create({
    required String command,
    required List<String> args,
    required Map<String, String> environment,
    String? cwd,
    int? outputByteLimit,
  }) async {
    if (_disposed) {
      throw StateError('Terminal host is closed');
    }
    final process = await Process.start(
      command,
      args,
      workingDirectory: cwd,
      environment: environment.isEmpty ? null : environment,
      includeParentEnvironment: true,
    );
    // dispose() may have run while the process was starting; never leak it.
    if (_disposed) {
      process.kill();
      throw StateError('Terminal host is closed');
    }
    final limit = outputByteLimit == null || outputByteLimit < 0
        ? defaultTerminalOutputLimit
        : outputByteLimit;
    late final LocalAcpTerminal terminal;
    terminal = LocalAcpTerminal(
      process,
      outputByteLimit: limit,
      onDone: () => _terminals.remove(terminal),
    );
    _terminals.add(terminal);
    return terminal;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final terminals = _terminals.toList();
    _terminals.clear();
    for (final terminal in terminals) {
      await terminal.kill();
    }
  }
}

class LocalAcpTerminal implements AcpTerminal {
  LocalAcpTerminal(
    this._process, {
    required int outputByteLimit,
    required void Function() onDone,
  })  : _limit = outputByteLimit,
        _onDone = onDone {
    _stdoutSubscription = _process.stdout.listen(
      _append,
      onError: (_) => _completeOnce(_stdoutDone),
      onDone: () => _completeOnce(_stdoutDone),
    );
    _stderrSubscription = _process.stderr.listen(
      _append,
      onError: (_) => _completeOnce(_stderrDone),
      onDone: () => _completeOnce(_stderrDone),
    );
    _exitedFuture = _process.exitCode.then((code) async {
      _exitCode = code;
      _hasExited = true;
      _onDone();
      // A surviving child can hold the inherited pipes open after the direct
      // process exits (Windows `cmd /c ...`); wait_for_exit must not hang on it.
      await Future.wait<void>([
        _stdoutDone.future.timeout(_drainGrace, onTimeout: () {}),
        _stderrDone.future.timeout(_drainGrace, onTimeout: () {}),
      ]);
    });
  }

  /// Bound on draining pipes that a surviving grandchild may still hold.
  static const _drainGrace = Duration(milliseconds: 200);

  final Process _process;
  final int _limit;
  final void Function() _onDone;
  final List<int> _bytes = [];
  final _stdoutDone = Completer<void>();
  final _stderrDone = Completer<void>();
  late final Future<void> _exitedFuture;
  late final StreamSubscription<List<int>> _stdoutSubscription;
  late final StreamSubscription<List<int>> _stderrSubscription;
  bool _hasExited = false;
  bool _released = false;
  bool _truncated = false;
  int? _exitCode;

  @override
  String get output {
    _trim();
    return utf8.decode(_bytes, allowMalformed: true);
  }

  @override
  bool get truncated => _truncated;

  @override
  bool get hasExited => _hasExited;

  @override
  int? get exitCode {
    final code = _exitCode;
    if (code == null) return null;
    return !Platform.isWindows && code < 0 ? null : code;
  }

  @override
  String? get signal {
    final code = _exitCode;
    if (Platform.isWindows || code == null || code >= 0) return null;
    return switch (-code) {
      2 => 'SIGINT',
      9 => 'SIGKILL',
      15 => 'SIGTERM',
      final value => 'SIG$value',
    };
  }

  @override
  Future<void> get exited => _exitedFuture;

  @override
  Future<void> kill() async {
    if (_hasExited || _released) return;
    await _terminate(force: false);
  }

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    if (!_hasExited) {
      await _terminate(force: true);
    }
    _onDone();
    // Cancelling subscriptions skips their onDone callbacks, so settle both
    // stream completers before `exited` waits on them.
    _completeOnce(_stdoutDone);
    _completeOnce(_stderrDone);
    await _stdoutSubscription.cancel();
    await _stderrSubscription.cancel();
  }

  /// Process.kill() only reaches the direct child on Windows, leaving e.g. the
  /// real command of `cmd /c ...` alive with the inherited pipes open.
  Future<void> _terminate({required bool force}) async {
    if (Platform.isWindows) {
      try {
        await Process.run(
          'taskkill',
          ['/PID', '${_process.pid}', '/T', '/F'],
        );
      } catch (_) {
        // Fall through to the direct-child handle.
      }
      if (!_hasExited) _process.kill();
      return;
    }
    _process.kill(force ? ProcessSignal.sigkill : ProcessSignal.sigterm);
  }

  void _append(List<int> data) {
    if (data.isEmpty) return;
    if (_limit <= 0) {
      _truncated = true;
      return;
    }
    _bytes.addAll(data);
    if (_bytes.length > _limit) {
      _truncated = true;
      if (_bytes.length > _limit * 2) _trim();
    }
  }

  void _trim() {
    if (_limit <= 0) {
      if (_bytes.isNotEmpty) {
        _bytes.clear();
        _truncated = true;
      }
      return;
    }
    if (_bytes.length > _limit) {
      _bytes.removeRange(0, _bytes.length - _limit);
      _truncated = true;
    }
  }

  static void _completeOnce(Completer<void> completer) {
    if (!completer.isCompleted) completer.complete();
  }
}
