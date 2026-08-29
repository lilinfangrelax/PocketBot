import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// Markdown message widget with beautiful code blocks
class MarkdownMessageView extends StatelessWidget {
  final String content;
  final bool isDarkMode;
  final bool isUser;

  const MarkdownMessageView({
    super.key,
    required this.content,
    required this.isDarkMode,
    this.isUser = false,
  });

  // 缓存样式表，避免每次 build 都创建新对象
  static final Map<String, MarkdownStyleSheet> _styleCache = {};

  MarkdownStyleSheet _getCachedStyleSheet() {
    final key = '$isDarkMode-$isUser';
    return _styleCache.putIfAbsent(
      key,
      () => _buildMarkdownStyleSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: content,
      styleSheet: _getCachedStyleSheet(),
      extensionSet: md.ExtensionSet.gitHubWeb,
      builders: {
        'code': InlineCodeBuilder(isDarkMode: isDarkMode, isUser: isUser),
        'pre': CodeBlockBuilder(isDarkMode: isDarkMode, isUser: isUser),
      },
    );
  }

  MarkdownStyleSheet _buildMarkdownStyleSheet() {
    // User messages always use black text, others follow the theme
    final textColor = isUser ? Colors.black87 : (isDarkMode ? Colors.white : Colors.black87);
    // A2: 使用更明显的代码背景颜色
    final codeBgColor = isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFE8E8E8);
    final inlineCodeColor = isDarkMode ? const Color(0xFF9CDCFE) : const Color(0xFFAF00D7);

    return MarkdownStyleSheet(
      p: TextStyle(
        color: textColor,
        fontSize: 16,  // D2: 调整为16px
        height: 1.5,
      ),
      h1: TextStyle(
        color: textColor,
        fontSize: 24,
        fontWeight: FontWeight.bold,
      ),
      h2: TextStyle(
        color: textColor,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
      h3: TextStyle(
        color: textColor,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      strong: TextStyle(
        color: textColor,
        fontWeight: FontWeight.bold,
      ),
      em: TextStyle(
        color: textColor,
        fontStyle: FontStyle.italic,
      ),
      blockquote: TextStyle(
        color: isDarkMode ? Colors.grey[400]! : Colors.grey[600]!,
        fontStyle: FontStyle.italic,
      ),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      blockquoteDecoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[900]! : Colors.grey[100]!,
        border: Border(
          left: BorderSide(
            color: isDarkMode ? Colors.grey[600]! : Colors.grey[400]!,
            width: 4,
          ),
        ),
      ),
      code: TextStyle(
        color: inlineCodeColor,
        fontFamily: 'monospace',
        fontSize: 14,  // D2: 调整为14px
        backgroundColor: codeBgColor,
      ),
      a: TextStyle(
        color: Colors.blue,
        decoration: TextDecoration.underline,
      ),
      listBullet: TextStyle(
        color: textColor,
        fontSize: 15,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
      ),
    );
  }
}

/// Builder for inline code (single backtick `code`)
class InlineCodeBuilder extends MarkdownElementBuilder {
  final bool isDarkMode;
  final bool isUser;

  InlineCodeBuilder({required this.isDarkMode, this.isUser = false});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // 行内代码：简洁样式，直接返回 Text
    final codeContent = StringBuffer();
    final children = element.children ?? <md.Node>[];
    for (final child in children) {
      if (child is md.Text) {
        codeContent.write(child.text);
      }
    }

    // User messages use dark code colors, others follow theme
    final codeBgColor = isUser
        ? const Color(0xFFE0E0E0)
        : (isDarkMode ? const Color(0xFF3C3C3C) : const Color(0xFFE0E0E0));
    final inlineCodeColor = isUser
        ? const Color(0xFFAF00D7)
        : (isDarkMode ? const Color(0xFF9CDCFE) : const Color(0xFFAF00D7));

    return Text(
      codeContent.toString(),
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,  // D2: 调整为14px
        color: inlineCodeColor,
        backgroundColor: codeBgColor,
      ),
    );
  }
}

/// Builder for code blocks (triple backtick ```code```)
class CodeBlockBuilder extends MarkdownElementBuilder {
  final bool isDarkMode;
  final bool isUser;

  CodeBlockBuilder({required this.isDarkMode, this.isUser = false});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // Extract language from class attribute (e.g., "language-dart")
    String language = 'text';
    final classAttr = element.attributes['class'];
    if (classAttr != null && classAttr.startsWith('language-')) {
      language = classAttr.substring(9);
    }

    // Extract code content
    final codeContent = StringBuffer();
    final children = element.children ?? <md.Node>[];
    for (final child in children) {
      if (child is md.Text) {
        codeContent.write(child.text);
      } else if (child is md.Element) {
        codeContent.write(_extractText(child));
      }
    }

    return CodeBlockWidget(
      code: codeContent.toString(),
      language: language,
      isDarkMode: isDarkMode,
      isUser: isUser,
    );
  }

  String _extractText(md.Element element) {
    final buffer = StringBuffer();
    final children = element.children ?? <md.Node>[];
    for (final child in children) {
      if (child is md.Text) {
        buffer.write(child.text);
      } else if (child is md.Element) {
        buffer.write(_extractText(child));
      }
    }
    return buffer.toString();
  }
}

/// Beautiful code block widget with dark theme, copy button, and language badge
class CodeBlockWidget extends StatefulWidget {
  final String code;
  final String language;
  final bool isDarkMode;
  final bool isUser;

  const CodeBlockWidget({
    super.key,
    required this.code,
    required this.language,
    required this.isDarkMode,
    this.isUser = false,
  });

  @override
  State<CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<CodeBlockWidget> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    // User messages use light theme for code blocks, others follow theme
    final bgColor = widget.isUser
        ? const Color(0xFFF8F8F8)
        : (widget.isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF8F8F8));
    final borderColor = widget.isUser
        ? Colors.grey[300]!
        : (widget.isDarkMode ? Colors.grey[700]! : Colors.grey[300]!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with language badge and copy button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border(
              top: BorderSide(color: borderColor),
              left: BorderSide(color: borderColor),
              right: BorderSide(color: borderColor),
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
          child: Row(
            children: [
              // Language badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getLanguageColor(),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  widget.language.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              // Copy button
              GestureDetector(
                onTap: _copyCode,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.isDarkMode ? Colors.grey[800] : Colors.grey[200],
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _copied ? Icons.check : Icons.content_copy,
                        size: 12,
                        color: _copied
                            ? Colors.green
                            : (widget.isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _copied ? '已复制' : '复制',
                        style: TextStyle(
                          fontSize: 11,
                          color: _copied
                              ? Colors.green
                              : (widget.isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Code content
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              widget.code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: widget.isDarkMode ? const Color(0xFFD4D4D4) : const Color(0xFF24292E),
                height: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    setState(() {
      _copied = true;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _copied = false;
        });
      }
    });
  }

  Color _getLanguageColor() {
    final colors = {
      'dart': Colors.blue,
      'python': Colors.blueGrey,
      'javascript': Colors.yellow[700]!,
      'typescript': Colors.blue[700]!,
      'java': Colors.orange,
      'kotlin': Colors.purple,
      'swift': Colors.orange,
      'rust': Colors.brown,
      'go': Colors.cyan,
      'c': Colors.blue,
      'cpp': Colors.blue,
      'css': Colors.blue[400]!,
      'html': Colors.orange[400]!,
      'json': Colors.grey[600]!,
      'bash': Colors.black,
      'shell': Colors.black,
      'sql': Colors.yellow[800]!,
      'yaml': Colors.red[400]!,
      'xml': Colors.red[400]!,
      'text': Colors.grey,
    };
    return colors[widget.language.toLowerCase()] ?? Colors.blue;
  }
}
