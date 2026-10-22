import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/widgets/elicitation_dialog.dart';

void main() {
  testWidgets('form elicitation validates required fields and returns types',
      (tester) async {
    Map<String, dynamic>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showElicitationDialog(context, {
                  'mode': 'form',
                  'message': 'Name this function',
                  'requestedSchema': {
                    'type': 'object',
                    'properties': {
                      'name': {
                        'type': 'string',
                        'title': 'Function Name',
                        'minLength': 1,
                      },
                      'port': {
                        'type': 'integer',
                        'title': 'Port',
                        'minimum': 1024,
                        'maximum': 65535,
                        'default': 3000,
                      },
                      'enableLogging': {
                        'type': 'boolean',
                        'title': 'Enable Logging',
                        'default': true,
                      },
                      'strategy': {
                        'type': 'string',
                        'title': 'Strategy',
                        'oneOf': [
                          {'const': 'conservative', 'title': 'Conservative'},
                          {'const': 'balanced', 'title': 'Balanced'},
                        ],
                        'default': 'balanced',
                      },
                      'colors': {
                        'type': 'array',
                        'title': 'Colors',
                        'items': {
                          'type': 'string',
                          'enum': ['Red', 'Green', 'Blue'],
                        },
                        'default': ['Red'],
                      },
                    },
                    'required': ['name'],
                  },
                });
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('需要你的输入'), findsOneWidget);
    expect(find.text('Name this function'), findsOneWidget);
    expect(find.text('Conservative'), findsNothing);

    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(find.text('请输入Function Name'), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(find.byType(TextFormField).first, 'processData');
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();

    expect(result, {
      'action': 'accept',
      'content': {
        'name': 'processData',
        'port': 3000,
        'enableLogging': true,
        'strategy': 'balanced',
        'colors': ['Red'],
      },
    });
  });

  testWidgets('form elicitation reports a decline', (tester) async {
    Map<String, dynamic>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showElicitationDialog(context, {
                  'mode': 'form',
                  'message': 'Continue?',
                  'requestedSchema': {
                    'type': 'object',
                    'properties': {
                      'name': {'type': 'string', 'title': 'Name'},
                    },
                  },
                });
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('拒绝'));
    await tester.pumpAndSettle();

    expect(result, {'action': 'decline'});
  });

  testWidgets('url elicitation shows the full URL and opens it on consent',
      (tester) async {
    Uri? opened;
    elicitationUrlLauncherOverride = (uri) async {
      opened = uri;
      return true;
    };
    addTearDown(() => elicitationUrlLauncherOverride = null);

    Map<String, dynamic>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showElicitationDialog(context, {
                  'mode': 'url',
                  'elicitationId': 'github-oauth-1',
                  'url': 'https://example.com/connect?elicitationId=1',
                  'message': 'Authorize GitHub access.',
                });
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('需要你的授权'), findsOneWidget);
    expect(find.text('目标网站：example.com'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.data == 'https://example.com/connect?elicitationId=1',
      ),
      findsOneWidget,
    );
    expect(opened, isNull);
    expect(result, isNull);

    await tester.tap(find.text('打开链接'));
    await tester.pumpAndSettle();

    expect(opened.toString(), 'https://example.com/connect?elicitationId=1');
    expect(result, {'action': 'accept'});
  });

  testWidgets('url elicitation blocks non-http links', (tester) async {
    elicitationUrlLauncherOverride = (uri) async => true;
    addTearDown(() => elicitationUrlLauncherOverride = null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showElicitationDialog(context, {
                  'mode': 'url',
                  'url': 'javascript:alert(1)',
                  'message': 'Suspicious',
                });
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('目标网站：无效链接'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '打开链接'),
    );
    expect(button.onPressed, isNull);
  });
}
