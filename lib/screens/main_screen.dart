import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pocket_bot/screens/chat_screen.dart';
import 'package:pocket_bot/screens/contacts_screen.dart';
import 'package:pocket_bot/screens/home_screen.dart';
import 'package:pocket_bot/screens/settings_screen.dart';
import 'package:pocket_bot/screens/wechat_session_list.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // 使用 IndexedStack 缓存页面，避免切换时重建
  final List<Widget> _pages = const [
    WeChatSessionList(),
    ContactsScreen(),
    HomeScreen(),
    SettingsScreen(),
  ];

  void _onTabTapped(int index) {
    if (index != _currentIndex) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FluentColors.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: colors.chrome,
          border: Border(top: BorderSide(color: colors.stroke)),
        ),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                  0, '消息', Icons.chat_bubble_outline, Icons.chat_bubble),
              _buildNavItem(1, '通讯录', Icons.people_outline, Icons.people),
              _buildNavItem(2, '发现', Icons.explore_outlined, Icons.explore),
              _buildNavItem(3, '我', Icons.person_outline, Icons.person),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    String label,
    IconData outlineIcon,
    IconData filledIcon,
  ) {
    final colors = FluentColors.of(context);
    final isSelected = _currentIndex == index;
    final color = isSelected ? colors.accent : colors.textSecondary;

    return GestureDetector(
      onTap: () => _onTabTapped(index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? colors.accentSubtle : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isSelected ? filledIcon : outlineIcon,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
