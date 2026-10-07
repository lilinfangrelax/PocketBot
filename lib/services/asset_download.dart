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
