import 'dart:math';

enum DiffOp { same, added, removed }

class DiffLine {
  final DiffOp op;
  final String text;
  final int? oldLine;
  final int? newLine;

  const DiffLine(this.op, this.text, {this.oldLine, this.newLine});
}

/// A run of changed lines with surrounding context, or a marker for
/// skipped unchanged lines when [skipped] is non-zero.
class DiffHunk {
  final List<DiffLine> lines;
  final int skipped;

  const DiffHunk(this.lines) : skipped = 0;
  const DiffHunk.gap(this.skipped) : lines = const [];

  bool get isGap => skipped > 0;
}

class LineDiffStats {
  final int added;
  final int removed;

  const LineDiffStats(this.added, this.removed);
}

/// Line diff via LCS. Inputs beyond [maxCells] comparisons fall back to
/// "everything removed, everything added" to keep the UI responsive.
List<DiffLine> diffLines(
  String? oldText,
  String newText, {
  int maxCells = 1000000,
}) {
  final a = _split(oldText ?? '');
  final b = _split(newText);

  var prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < a.length - prefix &&
      suffix < b.length - prefix &&
      a[a.length - 1 - suffix] == b[b.length - 1 - suffix]) {
    suffix++;
  }

  final result = <DiffLine>[];
  for (var i = 0; i < prefix; i++) {
    result.add(DiffLine(DiffOp.same, a[i], oldLine: i + 1, newLine: i + 1));
  }

  final midA = a.sublist(prefix, a.length - suffix);
  final midB = b.sublist(prefix, b.length - suffix);
  if (midA.length * midB.length > maxCells) {
    for (var i = 0; i < midA.length; i++) {
      result.add(DiffLine(DiffOp.removed, midA[i], oldLine: prefix + i + 1));
    }
    for (var j = 0; j < midB.length; j++) {
      result.add(DiffLine(DiffOp.added, midB[j], newLine: prefix + j + 1));
    }
  } else {
    result.addAll(_lcs(midA, midB, prefix));
  }

  for (var k = 0; k < suffix; k++) {
    final oldIndex = a.length - suffix + k;
    final newIndex = b.length - suffix + k;
    result.add(DiffLine(DiffOp.same, a[oldIndex],
        oldLine: oldIndex + 1, newLine: newIndex + 1));
  }
  return result;
}

List<DiffHunk> diffHunks(List<DiffLine> lines, {int context = 3}) {
  final changed = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].op != DiffOp.same) changed.add(i);
  }
  if (changed.isEmpty) return const [];

  final hunks = <DiffHunk>[];
  var cursor = 0;
  var i = 0;
  while (i < changed.length) {
    final start = max(0, changed[i] - context);
    var end = min(lines.length, changed[i] + context + 1);
    while (i + 1 < changed.length && changed[i + 1] - context <= end) {
      i++;
      end = min(lines.length, changed[i] + context + 1);
    }
    if (start > cursor) hunks.add(DiffHunk.gap(start - cursor));
    hunks.add(DiffHunk(lines.sublist(start, end)));
    cursor = end;
    i++;
  }
  if (cursor < lines.length) hunks.add(DiffHunk.gap(lines.length - cursor));
  return hunks;
}

LineDiffStats diffStats(List<DiffLine> lines) {
  var added = 0;
  var removed = 0;
  for (final line in lines) {
    if (line.op == DiffOp.added) added++;
    if (line.op == DiffOp.removed) removed++;
  }
  return LineDiffStats(added, removed);
}

List<String> _split(String text) {
  if (text.isEmpty) return const [];
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

List<DiffLine> _lcs(List<String> a, List<String> b, int offset) {
  final n = a.length;
  final m = b.length;
  final table = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      table[i][j] = a[i] == b[j]
          ? table[i + 1][j + 1] + 1
          : max(table[i + 1][j], table[i][j + 1]);
    }
  }
  final out = <DiffLine>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      out.add(DiffLine(DiffOp.same, a[i],
          oldLine: offset + i + 1, newLine: offset + j + 1));
      i++;
      j++;
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      out.add(DiffLine(DiffOp.removed, a[i], oldLine: offset + i + 1));
      i++;
    } else {
      out.add(DiffLine(DiffOp.added, b[j], newLine: offset + j + 1));
      j++;
    }
  }
  while (i < n) {
    out.add(DiffLine(DiffOp.removed, a[i], oldLine: offset + i + 1));
    i++;
  }
  while (j < m) {
    out.add(DiffLine(DiffOp.added, b[j], newLine: offset + j + 1));
    j++;
  }
  return out;
}
