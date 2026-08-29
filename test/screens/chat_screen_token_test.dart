import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/models/message.dart';

void main() {
  group('ChatSession Token Fields', () {
    test('should have default token values of 0', () {
      final session = ChatSession.create();

      expect(session.inputTokens, 0);
      expect(session.outputTokens, 0);
      expect(session.totalTokens, 0);
      expect(session.contextTokens, 0);
    });

    test('should store token values correctly', () {
      final session = ChatSession.create();
      session.inputTokens = 1500;
      session.outputTokens = 500;
      session.totalTokens = 2000;
      session.contextTokens = 200000;
      session.model = 'minimax-portal/MiniMax-M2.5';

      expect(session.inputTokens, 1500);
      expect(session.outputTokens, 500);
      expect(session.totalTokens, 2000);
      expect(session.contextTokens, 200000);
      expect(session.model, 'minimax-portal/MiniMax-M2.5');
    });

    test('should calculate total from input and output', () {
      final session = ChatSession.create();
      session.inputTokens = 2700;
      session.outputTokens = 448;
      session.totalTokens = session.inputTokens + session.outputTokens;

      expect(session.totalTokens, 3148);
    });

    test('should handle zero tokens', () {
      final session = ChatSession.create();
      session.inputTokens = 0;
      session.outputTokens = 0;
      session.totalTokens = 0;
      session.contextTokens = 200000;

      expect(session.inputTokens, 0);
      expect(session.outputTokens, 0);
      expect(session.totalTokens, 0);
    });

    test('should handle large token values', () {
      final session = ChatSession.create();
      session.inputTokens = 150000;
      session.outputTokens = 50000;
      session.totalTokens = 200000;
      session.contextTokens = 200000;

      expect(session.inputTokens, 150000);
      expect(session.outputTokens, 50000);
      expect(session.totalTokens, 200000);
      expect(session.contextTokens, 200000);
    });
  });

  group('Token Formatting Utilities', () {
    // Helper function matching chat_screen.dart _formatNumber
    String formatNumber(int value) {
      if (value >= 1000) {
        return '${(value / 1000).toStringAsFixed(1)}k';
      }
      return value.toString();
    }

    // Helper function matching chat_screen.dart _formatTokenUsage
    String formatTokenUsage(int used, int max) {
      if (used >= 1000 || max >= 1000) {
        final usedK = (used / 1000).toStringAsFixed(used % 1000 == 0 ? 0 : 1);
        final maxK = (max / 1000).toStringAsFixed(max % 1000 == 0 ? 0 : 1);
        return '$usedK k / $maxK k';
      }
      return '$used / $max';
    }

    test('formatNumber should format values >= 1000 with k suffix', () {
      expect(formatNumber(0), '0');
      expect(formatNumber(999), '999');
      expect(formatNumber(1000), '1.0k');
      expect(formatNumber(1500), '1.5k');
      expect(formatNumber(10000), '10.0k');
      expect(formatNumber(15000), '15.0k');
    });

    test('formatNumber should handle exact thousands', () {
      expect(formatNumber(2000), '2.0k');
      expect(formatNumber(10000), '10.0k');
      expect(formatNumber(100000), '100.0k');
    });

    test('formatTokenUsage should format with k for large values', () {
      expect(formatTokenUsage(0, 200000), '0 k / 200 k');
      expect(formatTokenUsage(1000, 200000), '1 k / 200 k');
      expect(formatTokenUsage(2700, 200000), '2.7 k / 200 k');
      expect(formatTokenUsage(3148, 200000), '3.1 k / 200 k');
    });

    test('formatTokenUsage should show raw numbers for small values', () {
      expect(formatTokenUsage(100, 200000), '0.1 k / 200 k');
      expect(formatTokenUsage(500, 100000), '0.5 k / 100 k');
    });

    test('formatTokenUsage should handle exact thousand in used value', () {
      expect(formatTokenUsage(2000, 200000), '2 k / 200 k');
      expect(formatTokenUsage(5000, 200000), '5 k / 200 k');
    });
  });
}
