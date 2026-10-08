import 'package:pocket_bot/utils/acp_stream_text.dart';
import 'package:test/test.dart';

void main() {
  test('strips a trailing leaked stream error and keeps the answer', () {
    expect(
      stripLeakedAgentError(
        '嗯，我在。有想做的事直接说就行。\n\nError: RetriableError: WritableIterable is closed',
      ),
      '嗯，我在。有想做的事直接说就行。',
    );
  });

  test('detects an error-only chunk', () {
    expect(
      isLeakedAgentErrorOnly(
        '\n\nError: RetriableError: WritableIterable is closed',
      ),
      isTrue,
    );
    expect(isLeakedAgentErrorOnly('我是 Grok 4.7'), isFalse);
    expect(
      isLeakedAgentErrorOnly(
        '我是 Grok 4.7\n\nError: RetriableError: WritableIterable is closed',
      ),
      isFalse,
    );
  });
}
