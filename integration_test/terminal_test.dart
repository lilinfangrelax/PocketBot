import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/services/connection_manager.dart';

import 'e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('代理通过 terminal 能力执行命令并读取输出', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);

      await sendChatMessage(tester, 'e2e-terminal');
      await pumpUntil(
        tester,
        () => isShowing(
          'MOCK_TERMINAL: exit=0 output=terminal-e2e released=true',
          findRichText: true,
        ),
        description: '终端命令往返',
      );
    } finally {
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
