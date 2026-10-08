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

  test('content range must continue at the requested offset', () {
    expect(contentRangeStartsAt('bytes 40-99/100', 40), isTrue);
    expect(contentRangeStartsAt('bytes 0-99/100', 40), isFalse);
    expect(contentRangeStartsAt(null, 40), isFalse);
  });

  test('a download is kept only when its size matches the asset', () {
    expect(downloadSizeMatches(written: 100, assetSize: 100), isTrue);
    expect(downloadSizeMatches(written: 40, assetSize: 100), isFalse);
    expect(downloadSizeMatches(written: 150, assetSize: 100), isFalse);
  });

  test('an apk starts with a zip local header', () {
    expect(looksLikeZipHeader([0x50, 0x4b, 0x03, 0x04, 0]), isTrue);
    expect(looksLikeZipHeader([0x3c, 0x68, 0x74, 0x6d]), isFalse);
  });
}
