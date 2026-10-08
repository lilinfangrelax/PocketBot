/// Android [versionCode] derived from `MAJOR.MINOR.PATCH`.
///
/// Releases increment the patch: `1.2.1-beta`, then `1.2.2-beta`, then
/// `1.2.2`. The `+` build suffix is ignored. Older `beta.N` tags are still
/// parsed so they sort below the next `-beta` version.
///
/// Layout: `major * 10000000 + minor * 100000 + patch * 1000 + pre`.
/// `-beta` uses `pre = 100`. A plain release uses `pre = 900`.
int androidVersionCode(String versionName) {
  final withoutBuild = versionName.split('+').first.trim();
  final match = RegExp(
    r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.]+))?$',
  ).firstMatch(withoutBuild);
  if (match == null) return 1;

  final major = int.parse(match.group(1)!);
  final minor = int.parse(match.group(2)!);
  final patch = int.parse(match.group(3)!);
  final pre = match.group(4) ?? '';
  return major * 10000000 + minor * 100000 + patch * 1000 + _preReleaseCode(pre);
}

int _preReleaseCode(String pre) {
  if (pre.isEmpty) return 900;
  if (pre == 'beta') return 100;

  final beta = RegExp(r'^beta\.(\d+)$').firstMatch(pre);
  if (beta != null) {
    return int.parse(beta.group(1)!).clamp(1, 499);
  }

  final rc = RegExp(r'^rc\.(\d+)$').firstMatch(pre);
  if (rc != null) {
    return 500 + int.parse(rc.group(1)!).clamp(1, 399);
  }

  return 1;
}
