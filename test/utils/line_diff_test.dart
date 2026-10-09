import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/utils/line_diff.dart';

void main() {
  test('marks changed lines and keeps line numbers', () {
    final lines = diffLines('a\nb\nc\n', 'a\nB\nc\nd\n');
    expect(
      lines.map((line) => '${line.op.name}:${line.text}'),
      ['same:a', 'removed:b', 'added:B', 'same:c', 'added:d'],
    );
    expect(lines[2].newLine, 2);
    expect(lines[1].oldLine, 2);
    final stats = diffStats(lines);
    expect(stats.added, 2);
    expect(stats.removed, 1);
  });

  test('treats a missing old text as a new file', () {
    final lines = diffLines(null, 'x\ny');
    expect(lines.every((line) => line.op == DiffOp.added), isTrue);
  });

  test('collapses unchanged runs between hunks', () {
    final old = List.generate(30, (i) => 'line $i').join('\n');
    final changed = old.replaceFirst('line 2', 'two').replaceFirst(
          'line 25',
          'twenty five',
        );
    final hunks = diffHunks(diffLines(old, changed), context: 2);
    expect(hunks.where((hunk) => !hunk.isGap), hasLength(2));
    expect(hunks.firstWhere((hunk) => hunk.isGap).skipped, greaterThan(0));
  });

  test('falls back to replace-all for huge inputs', () {
    final lines = diffLines('a\nb', 'c\nd', maxCells: 1);
    expect(lines.map((line) => line.op),
        [DiffOp.removed, DiffOp.removed, DiffOp.added, DiffOp.added]);
  });
}
