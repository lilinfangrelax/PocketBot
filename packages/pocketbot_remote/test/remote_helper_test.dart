import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pocketbot_remote/pocketbot_remote.dart';
import 'package:test/test.dart';

void main() {
  test('parses uname and windows architecture', () {
    expect(
      RemotePlatform.parseUname('Linux', 'x86_64')?.registryKey,
      'linux-x86_64',
    );
    expect(
      RemotePlatform.parseUname('Darwin', 'arm64')?.assetName,
      'pocketbot-remote-darwin-arm64',
    );
    expect(
      RemotePlatform.parseWindowsArchitecture('AMD64')?.assetName,
      'pocketbot-remote-windows-x64.exe',
    );
    expect(RemotePlatform.parseUname('Linux', 'mips'), isNull);
  });

  test('install path and release url include the app version', () {
    const platform = RemotePlatform(os: 'linux', arch: 'x86_64');
    expect(
      helperInstallPath(
        platform: platform,
        homeDirectory: '/home/me',
        version: '1.2.5-beta',
      ),
      '/home/me/.pocketbot/pocketbot-remote-1.2.5-beta',
    );
    expect(
      releaseAssetUrl(version: '1.2.5-beta', platform: platform),
      'https://github.com/lilinfangrelax/PocketBot/releases/download/v1.2.5-beta/pocketbot-remote-linux-x64',
    );
    expect(
      remoteAgentSessionId(
        connectionId: 'ssh|me@host:22',
        agentId: 'gemini',
        workingDirectory: r'D:\Dev\app',
      ),
      'ssh_me_host_22_gemini_D_Dev_app',
    );
    expect(
      remoteAgentSessionId(
        connectionId: 'ssh|me@host:22',
        agentId: 'gemini',
        workingDirectory: 'x' * 200,
      ),
      'x' * 120,
    );
  });

  test('quotes the helper command for Unix and Windows', () {
    const platform = RemotePlatform(os: 'windows', arch: 'x86_64');
    expect(
      buildRemoteHelperCommand(
        windows: false,
        helperPath: '/home/me/.pocketbot/pocketbot-remote-1.2.5-beta',
        sessionId: 'sess',
        workingDirectory: '/home/me/my project',
        argv: const ['npx', '-y', '@google/gemini-cli'],
        fresh: true,
      ),
      "'/home/me/.pocketbot/pocketbot-remote-1.2.5-beta' 'run' '--session' 'sess' "
      "'--cwd' '/home/me/my project' '--fresh' '--' 'npx' '-y' '@google/gemini-cli'",
    );
    expect(
      helperInstallPath(
        platform: platform,
        homeDirectory: r'C:\Users\me',
        version: '1.2.5-beta',
      ),
      r'C:\Users\me\.pocketbot\pocketbot-remote-1.2.5-beta.exe',
    );
    expect(
      buildRemoteHelperCommand(
        windows: true,
        helperPath: r'C:\Users\me\.pocketbot\pocketbot-remote-1.2.5-beta.exe',
        sessionId: 'sess',
        workingDirectory: r'D:\Dev\app',
        argv: const ['agent', 'acp'],
        fresh: false,
      ),
      r'cmd /d /s /c "C:\Users\me\.pocketbot\pocketbot-remote-1.2.5-beta.exe run --session sess --cwd D:\Dev\app -- agent acp"',
    );
  });

  test('parseRunArgs keeps the agent command after --', () {
    final options = parseRunArgs(const [
      '--session',
      's1',
      '--cwd',
      '/work',
      '--fresh',
      '--archive',
      'https://example.com/agent.tar.gz',
      '--agent-id',
      'cursor',
      '--agent-version',
      '2026.10.01',
      '--cmd',
      './dist-package/cursor-agent',
      '--env',
      'FOO=bar',
      '--legacy',
      'agent',
      '--legacy',
      'acp',
      '--',
      'acp',
    ]);
    expect(options.session, 's1');
    expect(options.cwd, '/work');
    expect(options.fresh, isTrue);
    expect(options.agentId, 'cursor');
    expect(options.relativeCommand, './dist-package/cursor-agent');
    expect(options.env['FOO'], 'bar');
    expect(options.legacyArgv, ['agent', 'acp']);
    expect(options.argv, ['acp']);
  });

  test('archive install is skipped when the cache is ready', () async {
    final root = await Directory.systemTemp.createTemp('pocketbot-agent');
    addTearDown(() => root.delete(recursive: true));
    final archive = Archive()
      ..addFile(ArchiveFile('bin/tool', 5, utf8.encode('hello')));
    final zip = ZipEncoder().encode(archive)!;

    final first = await ensureCachedAgent(
      root: root,
      agentId: 'tool',
      version: '1',
      archiveUrl: 'https://example.com/tool.zip',
      sha256: null,
      command: './bin/tool',
      args: const ['acp'],
      download: (_) async => zip,
    );
    expect(File(first.argv.first).readAsStringSync(), 'hello');

    final second = await ensureCachedAgent(
      root: root,
      agentId: 'tool',
      version: '1',
      archiveUrl: 'https://example.com/tool.zip',
      sha256: null,
      command: './bin/tool',
      args: const ['acp'],
      download: (_) async => throw Exception('should not download'),
    );
    expect(second.argv, first.argv);
  });

  test('rejects an archive whose sha256 does not match', () async {
    final root = await Directory.systemTemp.createTemp('pocketbot-agent');
    addTearDown(() => root.delete(recursive: true));
    final zip = _zip(Archive()..addFile(ArchiveFile('bin/tool', 2, utf8.encode('ok'))));
    expect(
      ensureCachedAgent(
        root: root,
        agentId: 'tool',
        version: '1',
        archiveUrl: 'https://example.com/tool.zip',
        sha256: '0' * 64,
        command: './bin/tool',
        args: const ['acp'],
        download: (_) async => zip,
      ),
      throwsA(predicate((error) => '$error'.contains('sha256 mismatch'))),
    );
  });

  test('ignores archive entries that leave the cache directory', () async {
    final root = await Directory.systemTemp.createTemp('pocketbot-agent');
    addTearDown(() => root.delete(recursive: true));
    final zip = _zip(Archive()
      ..addFile(ArchiveFile('../outside.txt', 3, utf8.encode('bad')))
      ..addFile(ArchiveFile('bin/tool', 2, utf8.encode('ok'))));
    final cached = await ensureCachedAgent(
      root: root,
      agentId: 'tool',
      version: '1',
      archiveUrl: 'https://example.com/tool.zip?download=1',
      sha256: crypto.sha256.convert(zip).toString(),
      command: './bin/tool',
      args: const ['acp'],
      download: (_) async => zip,
    );
    expect(File(cached.argv.first).readAsStringSync(), 'ok');
    expect(File('${root.path}/agents/tool/outside.txt').existsSync(), isFalse);
  });

  test('failed archive download can fall back to an installed command', () async {
    final argv = await resolveLaunchArgv(
      argv: const ['acp'],
      archiveUrl: 'https://example.com/missing.tar.gz',
      install: () async => throw Exception('offline'),
      legacyArgv: const ['agent', 'acp'],
    );
    expect(argv, ['agent', 'acp']);
    expect(
      resolveLaunchArgv(
        argv: const ['acp'],
        archiveUrl: 'https://example.com/missing.tar.gz',
        install: () async => throw Exception('offline'),
      ),
      throwsA(predicate((error) => '$error'.contains('无法下载代理'))),
    );
  });

  test('daemon rejects a bad token and forwards the launch environment', () async {
    final launches = <AgentLaunch>[];
    final daemon = await RemoteDaemon.start(
      version: 'test',
      token: 'secret',
      spawn: (launch) async {
        launches.add(launch);
        return _FakeAgent().handle;
      },
    );
    addTearDown(daemon.close);

    final rejected = await _handshake(daemon, token: 'nope');
    expect(rejected['ok'], isFalse);
    expect(rejected['error'], 'bad token');

    final attached = await _attach(
      daemon,
      session: 'env',
      argv: ['agent', 'acp'],
      env: const {'FOO': 'bar'},
    );
    expect(launches.single.env['FOO'], 'bar');
    expect(launches.single.cwd, '/work');
    await attached.close();
  });

  test('daemon keeps the agent alive across attach and reattach', () async {
    final launches = <AgentLaunch>[];
    final agents = <_FakeAgent>[];
    final daemon = await RemoteDaemon.start(
      version: 'test',
      token: 'secret',
      spawn: (launch) async {
        launches.add(launch);
        final agent = _FakeAgent();
        agents.add(agent);
        return agent.handle;
      },
    );
    addTearDown(daemon.close);

    final first = await _attach(daemon, session: 's', argv: ['agent', 'acp']);
    expect(first.resumed, isFalse);
    agents.single.stdout.add(utf8.encode('hello'));
    expect(await first.nextChunk(), utf8.encode('hello'));
    await first.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    agents.single.stdout.add(utf8.encode('again'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final second = await _attach(daemon, session: 's', argv: ['agent', 'acp']);
    expect(second.resumed, isTrue);
    expect(launches, hasLength(1));
    expect(await second.nextChunk(), utf8.encode('again'));
    second.socket.add(utf8.encode('ping'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(utf8.decode(agents.single.stdin), 'ping');

    final third = await _attach(
      daemon,
      session: 's',
      argv: ['other'],
      fresh: true,
    );
    expect(third.resumed, isFalse);
    expect(launches, hasLength(2));
    expect(agents.first.killed, isTrue);
    await second.close();
    await third.close();
  });
}

List<int> _zip(Archive archive) => ZipEncoder().encode(archive)!;

Future<Map<String, dynamic>> _handshake(
  RemoteDaemon daemon, {
  required String token,
}) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, daemon.port);
  socket.write('${jsonEncode({'token': token, 'op': 'attach'})}\n');
  final line = await socket
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first
      .timeout(const Duration(seconds: 2));
  await socket.close();
  return jsonDecode(line) as Map<String, dynamic>;
}

class _FakeAgent {
  final stdout = StreamController<List<int>>();
  final stderr = StreamController<List<int>>.broadcast();
  final stdin = <int>[];
  final exit = Completer<int>();
  var killed = false;

  ManagedAgent get handle => ManagedAgent(
        stdout: stdout.stream,
        stderr: stderr.stream,
        writeStdin: stdin.addAll,
        exitCode: exit.future,
        kill: () {
          killed = true;
          if (!exit.isCompleted) exit.complete(-1);
        },
      );
}

class _Attached {
  _Attached(this.socket, this.resumed, this._chunks);

  final Socket socket;
  final bool resumed;
  final Stream<List<int>> _chunks;

  Future<List<int>> nextChunk() => _chunks.first.timeout(const Duration(seconds: 2));
  Future<void> close() => socket.close();
}

Future<_Attached> _attach(
  RemoteDaemon daemon, {
  required String session,
  required List<String> argv,
  bool fresh = false,
  Map<String, String> env = const {},
}) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, daemon.port);
  socket.write('${jsonEncode({
        'token': 'secret',
        'op': 'attach',
        'session': session,
        'cwd': '/work',
        'argv': argv,
        'env': env,
        'fresh': fresh,
      })}\n');
  final lineDone = Completer<String>();
  final chunks = StreamController<List<int>>();
  final builder = BytesBuilder(copy: false);
  socket.listen((chunk) {
    if (lineDone.isCompleted) {
      chunks.add(chunk);
      return;
    }
    builder.add(chunk);
    final bytes = builder.toBytes();
    final newline = bytes.indexOf(10);
    if (newline < 0) return;
    lineDone.complete(utf8.decode(bytes.sublist(0, newline)));
    final rest = bytes.sublist(newline + 1);
    if (rest.isNotEmpty) chunks.add(rest);
  });
  final reply = jsonDecode(await lineDone.future) as Map<String, dynamic>;
  expect(reply['ok'], isTrue, reason: '$reply');
  return _Attached(socket, reply['resumed'] == true, chunks.stream);
}
