import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/models/acp_tool_call.dart';

void main() {
  test('exposes rawOutput as displayable text', () {
    final call = AcpToolCall(id: 'c1')
      ..merge({
        'rawOutput': {'exitCode': 0},
      });

    expect(call.hasDetails, isTrue);
    expect(call.rawOutputText, contains('"exitCode": 0'));
  });

  test('ignores blank rawOutput', () {
    final call = AcpToolCall(id: 'c1')..merge({'rawOutput': '  '});

    expect(call.rawOutputText, isNull);
    expect(call.hasDetails, isFalse);
  });
}
