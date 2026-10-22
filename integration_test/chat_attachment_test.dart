import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pocket_bot/models/attachment.dart';
import 'package:pocket_bot/services/attachment_service.dart';
import 'package:pocket_bot/services/connection_manager.dart';

import 'e2e_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('发送图片附件并确认代理收到 image block', (tester) async {
    // 1x1 transparent PNG.
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
      'z8BQDwAFgwJ/lY2mAAAAAElFTkSuQmCC',
    );
    final snapshot = await AppStateSnapshot.capture();
    ConnectionManager? manager;
    AttachmentService.pickImageOverride = () async => Attachment(
          id: 'e2e-image',
          filename: 'e2e.png',
          mimeType: 'image/png',
          size: pngBytes.length,
          data: base64Encode(pngBytes),
        );
    try {
      await snapshot.clear();
      await resetE2eDatabase();
      requireMockAgentCommand();
      manager = await startMockChat(tester);

      final attachButton = find.byKey(const ValueKey('chat-attach-image'));
      await pumpUntil(
        tester,
        () => attachButton.evaluate().isNotEmpty,
        description: '输入区显示图片附件按钮',
      );
      await tester.tap(attachButton);
      await pumpUntil(
        tester,
        () => isShowing('e2e.png'),
        description: '输入区显示待发送图片',
      );

      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '发送',
        ),
      );
      await pumpUntil(
        tester,
        () => isShowing('MOCK_IMAGES: 1', findRichText: true),
        description: '代理确认收到图片附件',
      );

      final messages = manager.wsService.activeSession?.messages ?? [];
      expect(
        messages.any(
          (message) => message.attachments.any(
            (attachment) => attachment.filename == 'e2e.png',
          ),
        ),
        isTrue,
      );
    } finally {
      AttachmentService.pickImageOverride = null;
      await disposePocketBotApp(tester, manager);
      await snapshot.restore();
    }
  });
}
