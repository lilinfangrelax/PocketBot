/// Cursor ACP sometimes appends an internal stream failure as assistant text
/// and still completes the turn. That text is not part of the reply.
final _leakedAgentErrorSuffix = RegExp(
  r'(?:\r?\n)*[ \t]*Error:[ \t]*(?:RetriableError:[ \t]*)?WritableIterable is closed[ \t]*$',
);

/// Removes a trailing `Error: RetriableError: WritableIterable is closed`.
String stripLeakedAgentError(String text) {
  var value = text;
  while (true) {
    final next = value.replaceFirst(_leakedAgentErrorSuffix, '');
    if (next == value) return value;
    value = next;
  }
}

/// True when [text] contains only the leaked Cursor stream error.
bool isLeakedAgentErrorOnly(String text) {
  if (!text.contains('WritableIterable is closed')) return false;
  return stripLeakedAgentError(text).trim().isEmpty;
}
