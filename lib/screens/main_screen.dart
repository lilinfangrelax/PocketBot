import 'package:fluent_ui/fluent_ui.dart';
import 'package:pocket_bot/screens/contacts_screen.dart';
import 'package:pocket_bot/screens/home_screen.dart';
import 'package:pocket_bot/screens/settings_screen.dart';
import 'package:pocket_bot/screens/wechat_session_list.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // IndexedStack keeps each tab alive across NavigationView changes.
  final List<Widget> _pages = const [
    WeChatSessionList(),
    ContactsScreen(),
    HomeScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: NavigationView(
        pane: NavigationPane(
          selected: _currentIndex,
          onChanged: (index) => setState(() => _currentIndex = index),
          displayMode: PaneDisplayMode.top,
          toggleButton: null,
          indicator: const StickyNavigationIndicator(),
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
        paneBodyBuilder: (item, body) {
          return IndexedStack(
            key: const ValueKey('pocketbot-tabs'),
            index: _currentIndex,
            children: _pages,
          );
        },
      ),
    );
  }
}
