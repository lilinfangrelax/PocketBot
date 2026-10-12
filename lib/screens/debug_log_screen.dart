import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';
import 'package:pocket_bot/utils/debug_log.dart';
import 'package:pocket_bot/utils/version_utils.dart';
import 'package:pocket_bot/widgets/fluent_page.dart';

class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key, DebugLog? log}) : _log = log;

  final DebugLog? _log;

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  final _search = TextEditingController();
  LogLevel _minLevel = LogLevel.debug;

  DebugLog get _log => widget._log ?? DebugLog.instance;

  String get _header => 'App: PocketBot ${AppVersion.fullVersion}';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<LogEntry> _visible() {
    final query = _search.text.trim().toLowerCase();
    return _log.entries.reversed
        .where((e) => e.level.index >= _minLevel.index)
        .where((e) => query.isEmpty || e.message.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _copyAll() async {
    final text = await _log.exportText(header: _header);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showAppNotice(context, '日志已复制');
  }

  Future<void> _export() async {
    try {
      final file = await _log.exportFile(header: _header);
      final result = await OpenFilex.open(file.path, type: 'text/plain');
      if (!mounted) return;
      showAppNotice(
        context,
        result.type == ResultType.done
            ? '已导出：${file.path}'
            : '已保存到 ${file.path}',
      );
    } catch (error) {
      if (mounted) showAppNotice(context, '导出失败：$error');
    }
  }

  Future<void> _clear() async {
    await _log.clear();
    if (mounted) showAppNotice(context, '日志已清空');
  }

  @override
  Widget build(BuildContext context) {
    final colors = FluentColors.of(context);
    return FluentScreen(
      title: const Text('调试日志'),
      commands: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          fluent.Tooltip(
            message: '复制全部',
            child: fluent.IconButton(
              icon: const Icon(fluent.WindowsIcons.copy),
              onPressed: _copyAll,
            ),
          ),
          fluent.Tooltip(
            message: '导出文件',
            child: fluent.IconButton(
              icon: const Icon(fluent.WindowsIcons.share),
              onPressed: _export,
            ),
          ),
          fluent.Tooltip(
            message: '清空',
            child: fluent.IconButton(
              icon: const Icon(fluent.WindowsIcons.delete),
              onPressed: _clear,
            ),
          ),
        ],
      ),
      content: ListenableBuilder(
        listenable: _log,
        builder: (context, _) {
          final entries = _visible();
          return Column(
            children: [
              if (!_log.enabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: fluent.InfoBar(
                    title: const Text('调试模式未开启'),
                    content: const Text('只记录信息和错误。开启后会记录连接、ACP 消息等详细过程。'),
                    action: fluent.Button(
                      onPressed: () => _log.setEnabled(true),
                      child: const Text('开启'),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: fluent.TextBox(
                        controller: _search,
                        placeholder: '搜索日志',
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    fluent.ComboBox<LogLevel>(
                      value: _minLevel,
                      items: const [
                        fluent.ComboBoxItem(
                            value: LogLevel.debug, child: Text('全部')),
                        fluent.ComboBoxItem(
                            value: LogLevel.info, child: Text('信息')),
                        fluent.ComboBoxItem(
                            value: LogLevel.warn, child: Text('警告')),
                        fluent.ComboBoxItem(
                            value: LogLevel.error, child: Text('错误')),
                      ],
                      onChanged: (value) =>
                          setState(() => _minLevel = value ?? LogLevel.debug),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text('暂无日志',
                            style: TextStyle(color: colors.textSecondary)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) =>
                            _LogTile(entry: entries[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final LogEntry entry;

  Color _levelColor(FluentColors colors) => switch (entry.level) {
        LogLevel.debug => colors.textSecondary,
        LogLevel.info => colors.accent,
        LogLevel.warn => colors.warning,
        LogLevel.error => colors.danger,
      };

  @override
  Widget build(BuildContext context) {
    final colors = FluentColors.of(context);
    final time = entry.format().substring(11, 23);
    return InkWell(
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: entry.format()));
        if (context.mounted) showAppNotice(context, '已复制这条日志');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$time  ${entry.level.label}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _levelColor(colors),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              entry.message,
              maxLines: 12,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
