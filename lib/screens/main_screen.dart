import 'package:fluent_ui/fluent_ui.dart';
import 'package:pocket_bot/screens/contacts_screen.dart';
import 'package:pocket_bot/screens/home_screen.dart';
import 'package:pocket_bot/screens/settings_screen.dart';
import 'package:pocket_bot/screens/wechat_session_list.dart';
import 'package:pocket_bot/widgets/fluent_tab_bar.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex = widget.initialIndex;
  int _sessionListRefreshToken = 0;

  static const _tabs = [
    FluentTab(icon: WindowsIcons.chat_bubbles, label: '消息'),
    FluentTab(icon: WindowsIcons.people, label: '通讯录'),
    FluentTab(icon: WindowsIcons.robot, label: '发现'),
    FluentTab(icon: WindowsIcons.contact, label: '我'),
  ];

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps each tab alive across tab changes.
    final pages = [
      WeChatSessionList(refreshToken: _sessionListRefreshToken),
      const ContactsScreen(),
      const HomeScreen(),
      const SettingsScreen(),
    ];
    return ColoredBox(
      color: FluentTheme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: IndexedStack(
                key: const ValueKey('pocketbot-tabs'),
                index: _currentIndex,
                children: pages,
              ),
            ),
          ),
          FluentTabBar(
            tabs: _tabs,
            selected: _currentIndex,
            onChanged: (index) => setState(() {
              if (index == 0 && _currentIndex != 0) {
                _sessionListRefreshToken++;
              }
              _currentIndex = index;
            }),
          ),
        ],
      ),
    );
  }
}
