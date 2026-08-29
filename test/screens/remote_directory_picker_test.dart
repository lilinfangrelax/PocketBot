import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/screens/remote_directory_picker.dart';
import 'package:pocket_bot/services/ssh_remote_session.dart';

class _FakeRemoteDirs implements RemoteDirectorySource {
  @override
  Future<String> resolveStartPath(String preferred) async {
    if (preferred.trim().isNotEmpty && preferred != '.') {
      return preferred;
    }
    return '/home/me';
  }

  @override
  Future<List<SshRemoteEntry>> listDirectory(String path) async {
    switch (path) {
      case '/home/me':
        return const [
          SshRemoteEntry(name: 'project', isDirectory: true),
          SshRemoteEntry(name: 'tmp', isDirectory: true),
        ];
      case '/home/me/project':
        return const [
          SshRemoteEntry(name: 'src', isDirectory: true),
        ];
      default:
        return const [];
    }
  }
}

void main() {
  testWidgets('SSH directory picker returns the chosen folder', (tester) async {
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                chosen = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RemoteDirectoryPicker(
                      source: _FakeRemoteDirs(),
                      hostLabel: 'user@host:22',
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('选择工作目录'), findsOneWidget);
    expect(find.text('project'), findsOneWidget);
    expect(find.text('tmp'), findsOneWidget);

    await tester.tap(find.text('project'));
    await tester.pumpAndSettle();
    expect(find.text('src'), findsOneWidget);

    await tester.tap(find.text('在此目录启动 Agent'));
    await tester.pumpAndSettle();
    expect(chosen, '/home/me/project');
  });
}
