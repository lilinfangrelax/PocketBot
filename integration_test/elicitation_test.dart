import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/widgets/elicitation_dialog.dart';

import 'e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('填写 ACP elicitation 表单并授权外部链接', (tester) async {
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    elicitationUrlLauncherOverride = (uri) async => true;
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);

      await sendChatMessage(tester, 'e2e-elicit-form');
      await pumpUntil(
        tester,
        () => isShowing('需要你的输入'),
        description: '显示 elicitation 表单',
      );
      expect(find.text('请填写 E2E 表单'), findsOneWidget);
      expect(find.text('名称 *'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, 'pocketbot');
      await tester.pump();
      await tester.tap(find.text('提交'));
      await pumpUntil(
        tester,
        () => isShowing(
          'MOCK_ELICIT: accept pocketbot|3000|true|balanced',
          findRichText: true,
        ),
        description: '提交 elicitation 内容',
      );

      await sendChatMessage(tester, 'e2e-elicit-url');
      await pumpUntil(
        tester,
        () => isShowing('需要你的授权'),
        description: '显示 URL 授权',
      );
      expect(find.text('目标网站：example.com'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data == 'https://example.com/authorize',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('打开链接'));
      await pumpUntil(
        tester,
        () => isShowing('MOCK_ELICIT_URL: accept', findRichText: true),
        description: '授权后代理继续',
      );
      await pumpUntil(
        tester,
        () => isShowing('外部授权流程已完成。'),
        description: '显示授权完成通知',
      );
    } finally {
      elicitationUrlLauncherOverride = null;
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
