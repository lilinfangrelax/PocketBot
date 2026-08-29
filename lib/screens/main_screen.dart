import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pocket_bot/screens/chat_screen.dart';
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
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // 使用 IndexedStack 保持页面状态，只重建可见页面
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      // 绿色浮动按钮已移除
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 1,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, '消息', Icons.chat_bubble_outline, Icons.chat_bubble, isDarkMode),
              _buildNavItem(1, '通讯录', Icons.people_outline, Icons.people, isDarkMode),
              _buildNavItem(2, '发现', Icons.explore_outlined, Icons.explore, isDarkMode),
              _buildNavItem(3, '我', Icons.person_outline, Icons.person, isDarkMode),
            ],
          ),
        ),
      ),
    );
  }

  // 预定义颜色常量，避免每次重建创建新对象
  static const Color _selectedColor = Color(0xFF07C160);

  Widget _buildNavItem(
    int index,
    String label,
    IconData outlineIcon,
    IconData filledIcon,
    bool isDarkMode,
  ) {
    final isSelected = _currentIndex == index;
    final unselectedColor = isDarkMode ? Colors.grey[400]! : Colors.grey[500]!;

    return GestureDetector(
      onTap: () => _onTabTapped(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? filledIcon : outlineIcon,
              color: isSelected ? _selectedColor : unselectedColor,
              size: 26,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? _selectedColor : unselectedColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
