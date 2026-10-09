/// File change reported in an ACP tool call (`{"type": "diff"}` content).
class AcpDiff {
  final String path;
  final String? oldText;
  final String newText;

  const AcpDiff({required this.path, required this.newText, this.oldText});

  bool get isNewFile => oldText == null;

  Map<String, dynamic> toJson() => {
        'path': path,
        'oldText': oldText,
        'newText': newText,
      };

  factory AcpDiff.fromJson(Map<String, dynamic> json) => AcpDiff(
        path: json['path'] as String? ?? '',
        oldText: json['oldText'] as String?,
        newText: json['newText'] as String? ?? '',
      );
}

/// Everything the client knows about one tool call, merged across
/// `tool_call` and `tool_call_update` notifications.
class AcpToolCall {
  final String id;
  String title;
  String kind;
  String status;
  Map<String, dynamic> rawInput;
  Object? rawOutput;
  final List<String> output;
  final List<AcpDiff> diffs;
  final List<String> terminalIds;
  final List<String> locations;

  AcpToolCall({
    required this.id,
    this.title = '',
    this.kind = 'other',
    this.status = 'pending',
    Map<String, dynamic>? rawInput,
    this.rawOutput,
    List<String>? output,
    List<AcpDiff>? diffs,
    List<String>? terminalIds,
    List<String>? locations,
  })  : rawInput = rawInput ?? {},
        output = output ?? [],
        diffs = diffs ?? [],
        terminalIds = terminalIds ?? [],
        locations = locations ?? [];

  /// Shell command, when the agent reports one in `rawInput`.
  String? get command {
    final value = rawInput['command'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is List && value.isNotEmpty) return value.join(' ');
    return null;
  }

  bool get hasDetails =>
      command != null ||
      output.isNotEmpty ||
      diffs.isNotEmpty ||
      terminalIds.isNotEmpty ||
      locations.isNotEmpty;

  /// Applies an ACP tool call update. Per the protocol, `content` and
  /// `locations` replace the previous lists when present.
  void merge(Map<String, dynamic> update) {
    final title = update['title'];
    if (title is String && title.trim().isNotEmpty) this.title = title.trim();
    final kind = update['kind'];
    if (kind is String && kind.isNotEmpty) this.kind = kind;
    final status = update['status'];
    if (status is String && status.isNotEmpty) this.status = status;
    final input = update['rawInput'];
    if (input is Map) rawInput = Map<String, dynamic>.from(input);
    if (update.containsKey('rawOutput')) rawOutput = update['rawOutput'];

    final content = update['content'];
    if (content is List) {
      output.clear();
      diffs.clear();
      terminalIds.clear();
      for (final raw in content) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        switch (item['type']) {
          case 'diff':
            diffs.add(AcpDiff.fromJson(item));
          case 'terminal':
            final terminalId = item['terminalId'];
            if (terminalId is String) terminalIds.add(terminalId);
          default:
            final text = _text(item);
            if (text.isNotEmpty) output.add(text);
        }
      }
    }

    final locations = update['locations'];
    if (locations is List) {
      this.locations
        ..clear()
        ..addAll(locations.whereType<Map>().map((item) {
          final path = item['path'] as String? ?? '';
          final line = item['line'];
          return line is int ? '$path:$line' : path;
        }).where((path) => path.isNotEmpty));
    }
  }

  static String _text(Map<String, dynamic> item) {
    final type = item['type'];
    if (type == 'content' && item['content'] is Map) {
      return _text(Map<String, dynamic>.from(item['content'] as Map));
    }
    if (type == 'text') return item['text'] as String? ?? '';
    if (type == 'resource_link') {
      return item['uri'] as String? ?? item['name'] as String? ?? '';
    }
    if (type == 'resource' && item['resource'] is Map) {
      final resource = item['resource'] as Map;
      return resource['text'] as String? ?? resource['uri'] as String? ?? '';
    }
    return item['text'] as String? ?? '';
  }
}
