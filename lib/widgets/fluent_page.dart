import 'package:fluent_ui/fluent_ui.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';

/// A phone page built from fluent_ui [ScaffoldPage].
///
/// [PageHeader] is sized for desktop windows (28px title, no top inset), so
/// the header here is a compact 56px bar with a 20px title.
class FluentScreen extends StatelessWidget {
  const FluentScreen({
    super.key,
    required this.title,
    required this.content,
    this.commands,
    this.bottomBar,
  });

  final Widget title;
  final Widget content;
  final Widget? commands;
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return ScaffoldPage(
      padding: EdgeInsets.zero,
      bottomBar: bottomBar,
      header: FluentPageHeader(
        leading: canPop
            ? IconButton(
                icon: const Icon(WindowsIcons.back),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: title,
        commands: commands,
      ),
      content: content,
    );
  }
}

class FluentPageHeader extends StatelessWidget {
  const FluentPageHeader({
    super.key,
    required this.title,
    this.leading,
    this.commands,
  });

  final Widget title;
  final Widget? leading;
  final Widget? commands;

  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    final colors = FluentColors.of(context);
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: leading != null ? 6 : 16,
          end: 6,
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: 20,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: title,
              ),
            ),
            if (commands != null) commands!,
          ],
        ),
      ),
    );
  }
}

/// Group label above a settings-style card, like WinUI's "body strong" text.
class FluentSectionHeader extends StatelessWidget {
  const FluentSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, top: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: FluentColors.of(context).textPrimary,
        ),
      ),
    );
  }
}

/// Round icon avatar on the subtle accent fill.
class FluentIconAvatar extends StatelessWidget {
  const FluentIconAvatar({
    super.key,
    required this.icon,
    this.size = 44,
  });

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = FluentColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.accentSubtle,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: colors.accent, size: size * 0.48),
    );
  }
}
