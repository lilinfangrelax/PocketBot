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

/// A MagicDNS suffix such as `example.ts.net`. A machine name is reduced to
/// its tailnet suffix; `ts.net` alone is not enough.
String? tailnetSuffixFromDomains(Iterable<String> domains) {
  for (final domain in domains) {
    for (final part in domain.split(RegExp(r'[\s,;]+'))) {
      var cleaned = part.trim().toLowerCase();
      cleaned = cleaned.replaceFirst(RegExp(r'^[~*\-]+'), '');
      cleaned = cleaned.replaceAll(RegExp(r'^\.+|\.+$'), '');
      final suffix = tailnetSuffixFromName(cleaned);
      if (suffix != null) return suffix;
    }
  }
  return null;
}

/// `example.ts.net`, or `phone.example.ts.net` reduced to that suffix.
String? tailnetSuffixFromName(String name) {
  final cleaned =
      name.trim().toLowerCase().replaceAll(RegExp(r'^\.+|\.+$'), '');
  if (_tailnetSuffix.hasMatch(cleaned)) return cleaned;
  final labels = cleaned.split('.').where((label) => label.isNotEmpty).toList();
  if (labels.length < 4) return null;
  if (labels[labels.length - 1] != 'net' || labels[labels.length - 2] != 'ts') {
    return null;
  }
  final suffix = labels.sublist(labels.length - 3).join('.');
  if (!_tailnetSuffix.hasMatch(suffix)) return null;
  return suffix;
}

/// Tailscale addresses sit in 100.64.0.0/10. 100.100.100.100 is MagicDNS
/// itself, not this phone.
bool isTailscaleIPv4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  final numbers = <int>[];
  for (final part in parts) {
    if (part.isEmpty || part.length > 3) return false;
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return false;
    if (part.length > 1 && part.startsWith('0')) return false;
    numbers.add(value);
  }
  if (numbers[0] != 100 || numbers[1] < 64 || numbers[1] > 127) return false;
  if (numbers[1] == 100 && numbers[2] == 100 && numbers[3] == 100) {
    return false;
  }
  return true;
}

/// Accepts a dotted Tailscale address or an IPv4-mapped form such as
/// `::ffff:100.73.210.105`.
String? tailscaleIpv4FromAddress(String raw) {
  var text = raw.trim().toLowerCase();
  if (text.startsWith('[') && text.contains(']')) {
    text = text.substring(1, text.indexOf(']'));
  }
  final zone = text.indexOf('%');
  if (zone >= 0) text = text.substring(0, zone);
  if (text.startsWith('::ffff:')) {
    final rest = text.substring('::ffff:'.length);
    if (isTailscaleIPv4(rest)) return rest;
    final halves = rest.split(':');
    if (halves.length == 2) {
      final high = int.tryParse(halves[0], radix: 16);
      final low = int.tryParse(halves[1], radix: 16);
      if (high != null && low != null && high <= 0xffff && low <= 0xffff) {
        final ip = '${high >> 8}.${high & 0xff}.${low >> 8}.${low & 0xff}';
        if (isTailscaleIPv4(ip)) return ip;
      }
    }
    return null;
  }
  if (text.contains(':')) text = text.split(':').first;
  if (isTailscaleIPv4(text)) return text;
  return null;
}

class TailnetDiscovery {
  const TailnetDiscovery({this.suffix, this.interfaceUp = false});

  final String? suffix;

  /// True when a Tailscale address or MagicDNS itself was reachable.
  final bool interfaceUp;
}

/// Search domains win. Otherwise the phone's 100.x address is reversed.
Future<TailnetDiscovery> resolveTailnetSuffix({
  required String domains,
  required Iterable<String> addresses,
  required Future<String?> Function(String ipv4) ptrLookup,
  Future<String?> Function()? observeLocalTailscaleAddress,
  Future<bool> Function()? magicDnsReachable,
}) async {
  final fromDomains = tailnetSuffixFromText(domains);
  if (fromDomains != null) {
    return TailnetDiscovery(suffix: fromDomains, interfaceUp: true);
  }

  final candidates = <String>[];
  void add(String? ip) {
    final cleaned = tailscaleIpv4FromAddress(ip ?? '');
    if (cleaned == null || candidates.contains(cleaned)) return;
    candidates.add(cleaned);
  }

  for (final address in addresses) {
    add(address);
  }
  if (candidates.isEmpty && observeLocalTailscaleAddress != null) {
    add(await observeLocalTailscaleAddress());
  }

  for (final ip in candidates) {
    final suffix = tailnetSuffixFromName(await ptrLookup(ip) ?? '');
    if (suffix != null) {
      return TailnetDiscovery(suffix: suffix, interfaceUp: true);
    }
  }
  var interfaceUp = candidates.isNotEmpty;
  if (!interfaceUp && magicDnsReachable != null) {
    interfaceUp = await magicDnsReachable();
  }
  return TailnetDiscovery(interfaceUp: interfaceUp);
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
