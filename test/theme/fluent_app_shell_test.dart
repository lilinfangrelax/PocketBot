import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';
import 'package:pocket_bot/widgets/fluent_page.dart';
import 'package:pocket_bot/widgets/fluent_tab_bar.dart';

void main() {
  test('buildFluentTheme returns a fluent_ui theme', () {
    final light = buildFluentTheme(Brightness.light);
    final dark = buildFluentTheme(Brightness.dark);

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.accentColor.normal, const Color(0xFF007C67));
    expect(dark.accentColor, Colors.teal);
  });

  testWidgets('FluentScreen uses ScaffoldPage with a compact header',
      (tester) async {
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
    expect(find.byType(FluentPageHeader), findsOneWidget);
    expect(
      tester.getSize(find.byType(FluentPageHeader)).height,
      FluentPageHeader.height,
    );
    expect(find.text('消息'), findsOneWidget);
    expect(find.text('会话列表'), findsOneWidget);
  });

  testWidgets('FluentTabBar shows every tab on a phone and reports taps',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var selected = 0;
    await tester.pumpWidget(
      FluentApp(
        theme: buildFluentTheme(Brightness.light),
        home: StatefulBuilder(
          builder: (context, setState) => Align(
            alignment: Alignment.bottomCenter,
            child: FluentTabBar(
              selected: selected,
              onChanged: (index) => setState(() => selected = index),
              tabs: const [
                FluentTab(icon: WindowsIcons.chat_bubbles, label: '消息'),
                FluentTab(icon: WindowsIcons.people, label: '通讯录'),
                FluentTab(icon: WindowsIcons.robot, label: '发现'),
                FluentTab(icon: WindowsIcons.contact, label: '我'),
              ],
            ),
          ),
        ),
      ),
    );

    for (final label in ['消息', '通讯录', '发现', '我']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('我'));
    await tester.pumpAndSettle();
    expect(selected, 3);
  });
}
