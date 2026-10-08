/// How to continue an in-app update download.
class AssetDownloadPlan {
  final int offset;
  final bool complete;

  const AssetDownloadPlan({
    required this.offset,
    required this.complete,
  });
}

/// A finished file is reused. A shorter partial file resumes. A longer one
/// is discarded because it cannot belong to this asset.
AssetDownloadPlan planAssetDownload({
  required int localBytes,
  required int assetSize,
}) {
  if (assetSize > 0 && localBytes == assetSize) {
    return AssetDownloadPlan(offset: localBytes, complete: true);
  }
  if (localBytes > 0 && (assetSize <= 0 || localBytes < assetSize)) {
    return AssetDownloadPlan(offset: localBytes, complete: false);
  }
  return const AssetDownloadPlan(offset: 0, complete: false);
}

/// HTTP 206 means the server honored Range and the body should be appended.
bool responseAppendsFromOffset(int? statusCode) => statusCode == 206;

/// A resumed body is usable only when it continues at [offset].
bool contentRangeStartsAt(String? header, int offset) {
  if (header == null || offset < 0) return false;
  final match = RegExp(r'bytes\s+(\d+)-', caseSensitive: false).firstMatch(header);
  if (match == null) return false;
  return int.tryParse(match.group(1)!) == offset;
}

/// The saved file must be the whole asset. A longer file is a bad resume.
bool downloadSizeMatches({required int written, required int assetSize}) {
  if (written <= 0) return false;
  if (assetSize <= 0) return true;
  return written == assetSize;
}

/// APK and zip files start with the local file header `PK\x03\x04`.
bool looksLikeZipHeader(List<int> header) {
  return header.length >= 4 &&
      header[0] == 0x50 &&
      header[1] == 0x4b &&
      header[2] == 0x03 &&
      header[3] == 0x04;
}
