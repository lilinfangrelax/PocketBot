/// One shell command that starts or reattaches the remote helper.
String buildRemoteHelperCommand({
  required bool windows,
  required String helperPath,
  required String sessionId,
  required String workingDirectory,
  required List<String> argv,
  required bool fresh,
  String? archiveUrl,
  String? sha256,
  String? agentId,
  String? agentVersion,
  String? relativeCommand,
  Map<String, String> env = const {},
  List<String> legacyArgv = const [],
}) {
  final args = <String>[
    helperPath,
    'run',
    '--session',
    sessionId,
    '--cwd',
    workingDirectory,
    if (fresh) '--fresh',
    if (archiveUrl != null && archiveUrl.isNotEmpty) ...[
      '--archive',
      archiveUrl,
      if (sha256 != null && sha256.isNotEmpty) ...['--sha256', sha256],
      if (agentId != null && agentId.isNotEmpty) ...['--agent-id', agentId],
      if (agentVersion != null && agentVersion.isNotEmpty)
        ...['--agent-version', agentVersion],
      if (relativeCommand != null && relativeCommand.isNotEmpty)
        ...['--cmd', relativeCommand],
    ],
    for (final entry in env.entries) ...['--env', '${entry.key}=${entry.value}'],
    for (final legacy in legacyArgv) ...['--legacy', legacy],
    '--',
    ...argv,
  ];
  if (windows) {
    final joined = args.map(_cmdArg).join(' ');
    return 'cmd /d /s /c "$joined"';
  }
  return args.map(_shQuote).join(' ');
}

String _shQuote(String value) {
  if (value.isEmpty) return "''";
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

String _cmdArg(String value) {
  if (value.isEmpty) return '""';
  if (RegExp(r'[\s"&|<>^]').hasMatch(value)) {
    return '"${value.replaceAll('"', '')}"';
  }
  return value;
}
