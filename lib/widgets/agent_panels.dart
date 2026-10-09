import 'package:flutter/material.dart';
import 'package:pocket_bot/services/websocket_service.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';

/// Pending `session/request_permission` calls, shown above the input bar
/// so they cannot scroll out of view.
class PermissionRequestPanel extends StatelessWidget {
  const PermissionRequestPanel({
    super.key,
    required this.requests,
    required this.onRespond,
  });

  final List<AcpPermissionRequest> requests;
  final void Function(AcpPermissionRequest request, String? optionId)
      onRespond;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final request in requests)
          _PermissionCard(request: request, onRespond: onRespond),
      ],
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.request, required this.onRespond});

  final AcpPermissionRequest request;
  final void Function(AcpPermissionRequest request, String? optionId)
      onRespond;

  @override
  Widget build(BuildContext context) {
    final colors = FluentColors.of(context);
    final detail = request.detail?.trim() ?? '';
    final options = [...request.options]
      ..sort((a, b) => _rank(a).compareTo(_rank(b)));

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: colors.warningSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 16, color: colors.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  request.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  detail,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              for (final option in options)
                option.allows && !option.always
                    ? FilledButton(
                        onPressed: () => onRespond(request, option.optionId),
                        child: Text(option.name),
                      )
                    : OutlinedButton(
                        onPressed: () => onRespond(request, option.optionId),
                        style: option.allows
                            ? null
                            : OutlinedButton.styleFrom(
                                foregroundColor: colors.danger,
                              ),
                        child: Text(option.name),
                      ),
            ],
          ),
        ],
      ),
    );
  }

  static int _rank(AcpPermissionOption option) {
    switch (option.kind) {
      case 'reject_always':
        return 0;
      case 'reject_once':
        return 1;
      case 'allow_always':
        return 2;
      case 'allow_once':
        return 3;
      default:
        return 4;
    }
  }
}

/// The agent's current plan, pinned like a group announcement.
class PlanPanel extends StatefulWidget {
  const PlanPanel({super.key, required this.entries});

  final List<AcpPlanEntry> entries;

  @override
  State<PlanPanel> createState() => _PlanPanelState();
}

class _PlanPanelState extends State<PlanPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    if (entries.isEmpty) return const SizedBox.shrink();
    final colors = FluentColors.of(context);
    final done = entries.where((entry) => entry.isDone).length;
    final current = entries.firstWhere(
      (entry) => entry.isActive,
      orElse: () => entries.firstWhere(
        (entry) => !entry.isDone,
        orElse: () => entries.last,
      ),
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(bottom: BorderSide(color: colors.stroke)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.checklist, size: 16, color: colors.accent),
                  const SizedBox(width: 8),
                  Text(
                    '计划 $done/${entries.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      done == entries.length ? '全部完成' : current.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                children: [
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            entry.isDone
                                ? Icons.check_circle
                                : entry.isActive
                                    ? Icons.timelapse
                                    : Icons.radio_button_unchecked,
                            size: 14,
                            color: entry.isDone
                                ? colors.success
                                : entry.isActive
                                    ? colors.accent
                                    : colors.textTertiary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.content,
                              style: TextStyle(
                                fontSize: 12,
                                color: entry.isDone
                                    ? colors.textSecondary
                                    : colors.textPrimary,
                                decoration: entry.isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
