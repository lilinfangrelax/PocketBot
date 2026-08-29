import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/services/acp_transport.dart';

void main() {
  group('NdjsonBuffer', () {
    test('splits complete lines and keeps a partial line', () {
      final buffer = NdjsonBuffer();
      expect(buffer.add('{"a":1}\n{"b":'), ['{"a":1}']);
      expect(buffer.add('2}\n'), ['{"b":2}']);
    });

    test('ignores empty lines and accepts CRLF', () {
      final buffer = NdjsonBuffer();
      expect(buffer.add('{"ok":true}\r\n\n{"next":1}\r\n'), [
        '{"ok":true}',
        '{"next":1}',
      ]);
    });

    test('concatenates many small chunks without losing a partial line', () {
      final buffer = NdjsonBuffer();
      expect(buffer.add('{"a":'), isEmpty);
      expect(buffer.add('1'), isEmpty);
      expect(buffer.add('}\n{"b":2}\n'), ['{"a":1}', '{"b":2}']);
    });
  });

  group('AcpTextChunkCoalescer', () {
    Map<String, dynamic> chunk(String text, {String id = 'm1'}) {
      return {
        'jsonrpc': '2.0',
        'method': 'session/update',
        'params': {
          'sessionId': 's1',
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'messageId': id,
            'content': {'type': 'text', 'text': text},
          },
        },
      };
    }

    test('merges consecutive text chunks until flush', () {
      final frames = <Map<String, dynamic>>[];
      final coalescer = AcpTextChunkCoalescer(
        emit: frames.add,
        interval: const Duration(hours: 1),
      );
      coalescer.add(chunk('Hel'));
      coalescer.add(chunk('lo'));
      expect(frames, isEmpty);
      coalescer.flush();
      expect(
        (frames.single['params']['update']['content'] as Map)['text'],
        'Hello',
      );
    });

    test('flushes pending text before a non-chunk frame', () {
      final frames = <Map<String, dynamic>>[];
      final coalescer = AcpTextChunkCoalescer(
        emit: frames.add,
        interval: const Duration(hours: 1),
      );
      coalescer.add(chunk('Hi'));
      coalescer.add({
        'jsonrpc': '2.0',
        'id': 1,
        'result': {'stopReason': 'end_turn'},
      });
      expect(frames, hasLength(2));
      expect(
        (frames.first['params']['update']['content'] as Map)['text'],
        'Hi',
      );
      expect(frames.last['result']['stopReason'], 'end_turn');
    });
  });

  group('buildRemoteAgentCommand', () {
    test('quotes a Unix working directory and agent args', () {
      expect(
        buildRemoteAgentCommand(
          workingDirectory: "/home/user/my project",
          command: 'agent',
          args: const ['acp'],
        ),
        "cd '/home/user/my project' && 'agent' 'acp'",
      );
    });

    test('uses cmd /c for Windows remote paths', () {
      expect(
        buildRemoteAgentCommand(
          workingDirectory: r'C:\Dev\PocketBot',
          command: 'agent',
          args: const ['acp'],
        ),
        r'cmd /c "cd /d C:\Dev\PocketBot && agent acp"',
      );
    });
  });

  group('remote path helpers', () {
    test('joins and walks Unix paths', () {
      expect(joinRemotePath('/home/me', 'src'), '/home/me/src');
      expect(parentRemotePath('/home/me/src'), '/home/me');
      expect(parentRemotePath('/home'), '/');
      expect(isRemoteRoot('/'), isTrue);
      expect(isRemoteRoot('/home'), isFalse);
    });

    test('joins and walks Windows paths', () {
      expect(joinRemotePath(r'C:\Users\me', 'Dev'), r'C:\Users\me\Dev');
      expect(parentRemotePath(r'C:\Users\me\Dev'), r'C:\Users\me');
      expect(parentRemotePath(r'C:\Users'), r'C:\');
      expect(isRemoteRoot(r'C:\'), isTrue);
      expect(toSftpPath(r'C:\Users\me'), 'C:/Users/me');
    });
  });
}
