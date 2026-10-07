import 'package:pocket_bot/services/asset_download.dart';
import 'package:test/test.dart';

void main() {
  group('planAssetDownload', () {
    test('starts a fresh download at the beginning', () {
      final plan = planAssetDownload(localBytes: 0, assetSize: 100);
      expect(plan.offset, 0);
      expect(plan.complete, isFalse);
    });

    test('resumes a shorter partial file', () {
      final plan = planAssetDownload(localBytes: 40, assetSize: 100);
      expect(plan.offset, 40);
      expect(plan.complete, isFalse);
    });

    test('reuses a file that already has the full asset', () {
      final plan = planAssetDownload(localBytes: 100, assetSize: 100);
      expect(plan.complete, isTrue);
      expect(plan.offset, 100);
    });

    test('discards a partial larger than the asset', () {
      final plan = planAssetDownload(localBytes: 150, assetSize: 100);
      expect(plan.offset, 0);
      expect(plan.complete, isFalse);
    });

    test('resumes when the server did not report a size', () {
      final plan = planAssetDownload(localBytes: 10, assetSize: 0);
      expect(plan.offset, 10);
      expect(plan.complete, isFalse);
    });
  });

  test('only HTTP 206 appends to the partial file', () {
    expect(responseAppendsFromOffset(206), isTrue);
    expect(responseAppendsFromOffset(200), isFalse);
    expect(responseAppendsFromOffset(416), isFalse);
  });
}
