enum McpTransport { stdio, http, sse }

class McpKeyValue {
  final String name;
  final String value;

  const McpKeyValue(this.name, this.value);

  Map<String, dynamic> toJson() => {'name': name, 'value': value};

  factory McpKeyValue.fromJson(Map<String, dynamic> json) =>
      McpKeyValue(json['name'] as String? ?? '', json['value'] as String? ?? '');

  /// Parses `KEY=value` / `Header: value` lines.
  static List<McpKeyValue> parseLines(String text, {String separator = '='}) {
    final result = <McpKeyValue>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final index = line.indexOf(separator);
      if (index <= 0) continue;
      result.add(McpKeyValue(
        line.substring(0, index).trim(),
        line.substring(index + separator.length).trim(),
      ));
    }
    return result;
  }

  static String formatLines(List<McpKeyValue> items,
          {String separator = '='}) =>
      items.map((item) => '${item.name}$separator${item.value}').join('\n');
}

/// An MCP server handed to the agent in `session/new`. Stdio servers run
/// on the agent's machine, so over SSH the command must exist remotely.
class McpServerConfig {
  final String id;
  final String name;
  final McpTransport transport;
  final bool enabled;
  final String command;
  final List<String> args;
  final List<McpKeyValue> env;
  final String url;
  final List<McpKeyValue> headers;

  const McpServerConfig({
    required this.id,
    required this.name,
    this.transport = McpTransport.stdio,
    this.enabled = true,
    this.command = '',
    this.args = const [],
    this.env = const [],
    this.url = '',
    this.headers = const [],
  });

  bool get isValid =>
      name.trim().isNotEmpty &&
      (transport == McpTransport.stdio
          ? command.trim().isNotEmpty
          : Uri.tryParse(url)?.hasScheme == true);

  /// ACP `McpServer` shape.
  Map<String, dynamic> toAcp() {
    switch (transport) {
      case McpTransport.stdio:
        return {
          'name': name,
          'command': command,
          'args': args,
          'env': env.map((item) => item.toJson()).toList(),
        };
      case McpTransport.http:
      case McpTransport.sse:
        return {
          'type': transport.name,
          'name': name,
          'url': url,
          'headers': headers.map((item) => item.toJson()).toList(),
        };
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'transport': transport.name,
        'enabled': enabled,
        'command': command,
        'args': args,
        'env': env.map((item) => item.toJson()).toList(),
        'url': url,
        'headers': headers.map((item) => item.toJson()).toList(),
      };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    List<McpKeyValue> pairs(Object? raw) => (raw as List? ?? const [])
        .whereType<Map>()
        .map((item) => McpKeyValue.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    return McpServerConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      transport: McpTransport.values.firstWhere(
        (value) => value.name == json['transport'],
        orElse: () => McpTransport.stdio,
      ),
      enabled: json['enabled'] as bool? ?? true,
      command: json['command'] as String? ?? '',
      args: (json['args'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      env: pairs(json['env']),
      url: json['url'] as String? ?? '',
      headers: pairs(json['headers']),
    );
  }

  McpServerConfig copyWith({bool? enabled}) => McpServerConfig(
        id: id,
        name: name,
        transport: transport,
        enabled: enabled ?? this.enabled,
        command: command,
        args: args,
        env: env,
        url: url,
        headers: headers,
      );
}
