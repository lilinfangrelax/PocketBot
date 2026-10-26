import 'package:crypto/crypto.dart';

/// MagicDNS name of the computer publishing dev builds.
///
/// Tailscale Services can only be hosted by a tagged node. This computer is a
/// personal device, so the phone looks up the machine name instead.
const devUpdateServiceName = 'msi-laptop';
const devUpdateLocalPort = 8787;
const devUpdateApkName = 'PocketBot.apk';

final _tailnetSuffix = RegExp(r'^[a-z0-9-]+\.ts\.net$');
final _explicitSuffix = RegExp(
  r'suffix\s*=\s*([a-z0-9-]+\.ts\.net)',
  caseSensitive: false,
);
final _sha256 = RegExp(r'^[0-9a-f]{64}$');
final _apkName = RegExp(r'^[A-Za-z0-9._-]+\.apk$');

/// `version: 1.2.27-beta+3` keeps the version name and drops the build number.
String? readPubspecVersion(String pubspec) {
  final match = RegExp(
    r'^version:\s*([^\s#+]+)',
    multiLine: true,
  ).firstMatch(pubspec);
  final version = match?.group(1)?.trim();
  if (version == null || version.isEmpty) return null;
  return version;
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// A MagicDNS suffix such as `example.ts.net`. Hostnames are rejected.
String? tailnetSuffixFromDomains(Iterable<String> domains) {
  for (final domain in domains) {
    for (final part in domain.split(RegExp(r'[\r\n,;]+'))) {
      var cleaned = part.trim().toLowerCase();
      cleaned = cleaned.replaceFirst(RegExp(r'^[-*\s]+'), '');
      cleaned = cleaned.replaceAll(RegExp(r'^\.+|\.+$'), '');
      if (_tailnetSuffix.hasMatch(cleaned)) return cleaned;
    }
  }
  return null;
}

/// Parses `tailscale dns status` or a search-domain list.
String? tailnetSuffixFromText(String text) {
  final explicit = _explicitSuffix.firstMatch(text);
  if (explicit != null) return explicit.group(1)!.toLowerCase();
  return tailnetSuffixFromDomains([text]);
}

Uri devUpdateManifestUri(String suffix) {
  final host = '$devUpdateServiceName.${_cleanSuffix(suffix)}';
  return Uri.https(host, '/update.json');
}

String _cleanSuffix(String suffix) {
  final cleaned = suffix.trim().toLowerCase().replaceAll(
        RegExp(r'^\.+|\.+$'),
        '',
      );
  if (!_tailnetSuffix.hasMatch(cleaned)) {
    throw FormatException('Invalid tailnet suffix', suffix);
  }
  return cleaned;
}

class DevUpdateManifest {
  const DevUpdateManifest({
    required this.version,
    required this.sha256,
    required this.size,
    required this.file,
  });

  final String version;
  final String sha256;
  final int size;
  final String file;

  Map<String, Object> toJson() => {
        'version': version,
        'sha256': sha256,
        'size': size,
        'file': file,
      };
}

DevUpdateManifest? parseDevUpdateManifest(Object? decoded) {
  if (decoded is! Map) return null;
  final version = decoded['version']?.toString().trim() ?? '';
  final file = decoded['file']?.toString().trim() ?? '';
  final sha = decoded['sha256']?.toString().trim().toLowerCase() ?? '';
  final size = (decoded['size'] as num?)?.toInt() ?? -1;
  if (version.isEmpty || size < 0) return null;
  if (!_sha256.hasMatch(sha) || !_apkName.hasMatch(file)) return null;
  if (file.contains('..')) return null;
  return DevUpdateManifest(
    version: version,
    sha256: sha,
    size: size,
    file: file,
  );
}

/// A new compile is a new package even when `pubspec.yaml` did not change.
bool devBuildAvailable({
  required String sha256,
  required String? installedSha256,
}) {
  final remote = sha256.trim().toLowerCase();
  final installed = installedSha256?.trim().toLowerCase();
  if (remote.isEmpty) return false;
  return remote != installed;
}

class DevByteRange {
  const DevByteRange({
    required this.start,
    required this.end,
    required this.total,
  });

  final int start;
  final int end;
  final int total;

  int get length => end - start;
}

/// `null` means the range cannot be satisfied. An absent header is the whole file.
DevByteRange? byteRangeForRequest(String? header, int total) {
  if (total <= 0) return null;
  if (header == null || header.trim().isEmpty) {
    return DevByteRange(start: 0, end: total, total: total);
  }
  final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(header.trim());
  if (match == null) return null;
  final start = int.parse(match.group(1)!);
  if (start >= total) return null;
  final endText = match.group(2)!;
  final endInclusive = endText.isEmpty ? total - 1 : int.parse(endText);
  if (endInclusive < start) return null;
  final end = endInclusive + 1 > total ? total : endInclusive + 1;
  return DevByteRange(start: start, end: end, total: total);
}
