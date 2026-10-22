import 'package:fluent_ui/fluent_ui.dart';

/// LXGW WenKai (霞鹜文楷), bundled under the SIL Open Font License.
class PocketFonts {
  static const ui = 'LXGW WenKai';

  /// Used when a glyph is not in WenKai, including emoji.
  static const uiFallback = <String>[
    'Segoe UI',
    'Microsoft YaHei',
    'PingFang SC',
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  static TextStyle paint(TextStyle style) {
    return style.copyWith(
      fontFamily: ui,
      fontFamilyFallback: uiFallback,
    );
  }

  static Typography paintTypography(Typography typography) {
    return Typography.raw(
      display: paint(typography.display!),
      titleLarge: paint(typography.titleLarge!),
      title: paint(typography.title!),
      subtitle: paint(typography.subtitle!),
      bodyLarge: paint(typography.bodyLarge!),
      bodyStrong: paint(typography.bodyStrong!),
      body: paint(typography.body!),
      caption: paint(typography.caption!),
    );
  }
}
