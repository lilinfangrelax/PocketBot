import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';
import 'package:pocket_bot/widgets/fluent_page.dart';

void main() {
  test('buildFluentTheme returns a fluent_ui theme', () {
    final light = buildFluentTheme(Brightness.light);
    final dark = buildFluentTheme(Brightness.dark);

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.accentColor.normal, const Color(0xFF007C67));
    expect(dark.accentColor, Colors.teal);
  });

  testWidgets('FluentScreen uses ScaffoldPage and PageHeader', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(Brightness.light),
        home: const FluentScreen(
          title: Text('消息'),
          content: Text('会话列表'),
        ),
      ),
    );

    expect(find.byType(ScaffoldPage), findsOneWidget);
    expect(find.byType(PageHeader), findsOneWidget);
    expect(find.text('消息'), findsOneWidget);
    expect(find.text('会话列表'), findsOneWidget);
  });

  testWidgets('top NavigationView shows every tab label', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(Brightness.light),
        home: NavigationView(
          pane: NavigationPane(
            selected: 0,
            displayMode: PaneDisplayMode.top,
            toggleButton: null,
            items: [
              PaneItem(
                icon: const Icon(WindowsIcons.chat_bubbles),
                title: const Text('消息'),
                body: const SizedBox.shrink(),
              ),
              PaneItem(
                icon: const Icon(WindowsIcons.people),
                title: const Text('通讯录'),
                body: const SizedBox.shrink(),
              ),
              PaneItem(
                icon: const Icon(WindowsIcons.globe),
                title: const Text('发现'),
                body: const SizedBox.shrink(),
              ),
              PaneItem(
                icon: const Icon(WindowsIcons.settings),
                title: const Text('我'),
                body: const SizedBox.shrink(),
              ),
            ],
          ),
          paneBodyBuilder: (item, body) => const Text('页面'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(NavigationView), findsOneWidget);
    expect(find.text('消息'), findsWidgets);
    expect(find.text('通讯录'), findsWidgets);
    expect(find.text('发现'), findsWidgets);
    expect(find.text('我'), findsWidgets);
    expect(find.text('页面'), findsOneWidget);
  });
}
