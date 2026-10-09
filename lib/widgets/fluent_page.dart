import 'package:fluent_ui/fluent_ui.dart';

/// A phone page built from fluent_ui [ScaffoldPage] and [PageHeader].
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
      header: PageHeader(
        leading: canPop
            ? Padding(
                padding: const EdgeInsetsDirectional.only(start: 4),
                child: IconButton(
                  icon: const Icon(WindowsIcons.back),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              )
            : null,
        title: title,
        commandBar: commands,
      ),
      content: content,
    );
  }
}
