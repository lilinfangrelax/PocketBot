import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/screens/debug_log_screen.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';
import 'package:pocket_bot/utils/debug_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('lists, filters and enables debug logging', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final log = DebugLog();
    log.add(LogLevel.info, '[SSH] host online');
    log.add(LogLevel.error, '[Pool] start failed');

    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(Brightness.dark),
        builder: (context, child) => material.Theme(
          data: buildMaterialTheme(Brightness.dark),
          child: material.Material(
            type: material.MaterialType.transparency,
            child: child!,
          ),
        ),
        home: DebugLogScreen(log: log),
      ),
    );

    expect(find.text('[SSH] host online'), findsOneWidget);
    expect(find.text('[Pool] start failed'), findsOneWidget);
    expect(find.text('调试模式未开启'), findsOneWidget);

    await tester.enterText(find.byType(TextBox), 'pool');
    await tester.pump();
    expect(find.text('[SSH] host online'), findsNothing);
    expect(find.text('[Pool] start failed'), findsOneWidget);

    await tester.tap(find.text('开启'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(log.enabled, isTrue);
    expect(find.text('调试模式未开启'), findsNothing);
  });
}
