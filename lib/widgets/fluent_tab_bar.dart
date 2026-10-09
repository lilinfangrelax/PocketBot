import 'package:fluent_ui/fluent_ui.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';

class FluentTab {
  const FluentTab({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// Bottom tab bar for phones.
///
/// fluent_ui's top [NavigationView] pane is sized for desktop windows and
/// pushes tabs into an overflow menu on narrow screens, so the app shell uses
/// this bar with WinUI colors and the pill selection indicator instead.
class FluentTabBar extends StatelessWidget {
  const FluentTabBar({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
  });

  final List<FluentTab> tabs;
  final int selected;
  final ValueChanged<int> onChanged;

  static const double height = 60;

  @override
  Widget build(BuildContext context) {
    final colors = FluentColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.chrome,
        border: Border(top: BorderSide(color: colors.stroke)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: _FluentTabButton(
                    tab: tabs[i],
                    selected: i == selected,
                    onPressed: () => onChanged(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FluentTabButton extends StatelessWidget {
  const _FluentTabButton({
    required this.tab,
    required this.selected,
    required this.onPressed,
  });

  final FluentTab tab;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = FluentColors.of(context);
    final foreground = selected ? colors.accent : colors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      child: HoverButton(
        onPressed: onPressed,
        builder: (context, states) {
          final pressed = states.isPressed;
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                width: 52,
                height: 28,
                decoration: BoxDecoration(
                  color: selected
                      ? colors.accentSubtle
                      : pressed
                          ? colors.stroke
                          : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(tab.icon, size: 20, color: foreground),
              ),
              const SizedBox(height: 3),
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: foreground,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
