import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocket_bot/models/acp_tool_call.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';
import 'package:pocket_bot/utils/line_diff.dart';

final _diffCache = Expando<List<DiffLine>>('diffLines');

List<DiffLine> _cachedDiff(AcpDiff diff) =>
    _diffCache[diff] ??= diffLines(diff.oldText, diff.newText);

/// Collapsible tool call card. Collapsed it is one line, like a file
/// message in a chat; expanded it shows the command, output and diffs.
class ToolCallCard extends StatefulWidget {
  const ToolCallCard({
    super.key,
    required this.title,
    required this.status,
    this.summary = '',
    this.toolCall,
    this.awaitingPermission = false,
  });

  final String title;
  final String status;

  /// Fallback detail text when [toolCall] is unknown (e.g. after a restart).
  final String summary;
  final AcpToolCall? toolCall;
  final bool awaitingPermission;

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = FluentColors.of(context);
    final call = widget.toolCall;
    final status = widget.awaitingPermission ? 'awaiting' : widget.status;
    final color = _statusColor(colors, status);
    final diffs = call?.diffs ?? const <AcpDiff>[];
    final canExpand =
        (call?.hasDetails ?? false) || widget.summary.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 2, 16, 2),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.awaitingPermission ? colors.warning : colors.stroke,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: canExpand
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: [
                    Icon(_kindIcon(call?.kind), size: 14, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    for (final diff in diffs.take(1)) ...[
                      const SizedBox(width: 6),
                      _DiffBadge(diff: diff),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      _statusLabel(status),
                      style: TextStyle(fontSize: 11, color: color),
                    ),
                    if (canExpand)
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: colors.textSecondary,
                      ),
                  ],
                ),
              ),
            ),
            if (_expanded) _buildDetails(context, colors),
          ],
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context, FluentColors colors) {
    final call = widget.toolCall;
    final children = <Widget>[];
    if (call == null) {
      children.add(_MonoBlock(text: widget.summary.trim()));
    } else {
      final command = call.command;
      if (command != null) {
        children.add(_MonoBlock(text: '\$ $command', copyable: true));
      }
      if (call.locations.isNotEmpty) {
        children.add(Text(
          call.locations.join('\n'),
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ));
      }
      for (final diff in call.diffs) {
        children.add(DiffView(diff: diff));
      }
      if (call.output.isNotEmpty) {
        children.add(_MonoBlock(text: call.output.join('\n'), copyable: true));
      }
      if (call.terminalIds.isNotEmpty && call.output.isEmpty) {
        children.add(Text(
          '终端输出在代理所在的机器上',
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ));
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final child in children) ...[
            child,
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  static Color _statusColor(FluentColors colors, String status) {
    switch (status) {
      case 'failed':
        return colors.danger;
      case 'completed':
        return colors.success;
      case 'awaiting':
        return colors.warning;
      default:
        return colors.info;
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return '完成';
      case 'in_progress':
        return '进行中';
      case 'pending':
        return '等待';
      case 'failed':
        return '失败';
      case 'awaiting':
        return '待确认';
      default:
        return status;
    }
  }

  static IconData _kindIcon(String? kind) {
    switch (kind) {
      case 'read':
        return Icons.description_outlined;
      case 'edit':
        return Icons.edit_note;
      case 'delete':
        return Icons.delete_outline;
      case 'move':
        return Icons.drive_file_move_outline;
      case 'search':
        return Icons.search;
      case 'execute':
        return Icons.terminal;
      case 'think':
        return Icons.psychology_outlined;
      case 'fetch':
        return Icons.public;
      default:
        return Icons.build_outlined;
    }
  }
}

class _DiffBadge extends StatelessWidget {
  const _DiffBadge({required this.diff});

  final AcpDiff diff;

  @override
  Widget build(BuildContext context) {
    final colors = FluentColors.of(context);
    final stats = diffStats(_cachedDiff(diff));
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: '+${stats.added}',
          style: TextStyle(color: colors.success),
        ),
        const TextSpan(text: ' '),
        TextSpan(
          text: '-${stats.removed}',
          style: TextStyle(color: colors.danger),
        ),
      ]),
      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
    );
  }
}

class _MonoBlock extends StatelessWidget {
  const _MonoBlock({required this.text, this.copyable = false});

  final String text;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final colors = FluentColors.of(context);
    return GestureDetector(
      onLongPress: copyable
          ? () {
              Clipboard.setData(ClipboardData(text: text));
              showAppNotice(context, '已复制');
            }
          : null,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 240),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(4),
        ),
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Unified diff of one file, with unchanged runs collapsed.
class DiffView extends StatelessWidget {
  const DiffView({super.key, required this.diff});

  final AcpDiff diff;

  @override
  Widget build(BuildContext context) {
    final colors = FluentColors.of(context);
    final lines = _cachedDiff(diff);
    final hunks = diffHunks(lines);
    final stats = diffStats(lines);
    const mono = TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.35);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    diff.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colors.textSecondary),
                  ),
                ),
                Text(
                  diff.isNewFile
                      ? '新文件 +${stats.added}'
                      : '+${stats.added} -${stats.removed}',
                  style: mono.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hunks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('没有内容变化',
                              style:
                                  mono.copyWith(color: colors.textSecondary)),
                        ),
                      for (final hunk in hunks)
                        if (hunk.isGap)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            child: Text(
                              '⋯ ${hunk.skipped} 行未改动',
                              style: mono.copyWith(color: colors.textTertiary),
                            ),
                          )
                        else
                          for (final line in hunk.lines)
                            Container(
                              color: switch (line.op) {
                                DiffOp.added =>
                                  colors.success.withValues(alpha: 0.14),
                                DiffOp.removed =>
                                  colors.danger.withValues(alpha: 0.14),
                                DiffOp.same => null,
                              },
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                '${switch (line.op) {
                                  DiffOp.added => '+',
                                  DiffOp.removed => '-',
                                  DiffOp.same => ' ',
                                }} ${line.text}',
                                style: mono.copyWith(color: colors.textPrimary),
                                softWrap: false,
                              ),
                            ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
