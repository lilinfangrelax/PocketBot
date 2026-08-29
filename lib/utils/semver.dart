/// Semantic version (MAJOR.MINOR.PATCH[-prerelease][+build]).
class SemVer implements Comparable<SemVer> {
  final int major;
  final int minor;
  final int patch;
  final List<String> preRelease;

  const SemVer(this.major, this.minor, this.patch,
      [this.preRelease = const []]);

  bool get isPreRelease => preRelease.isNotEmpty;

  static final _pattern = RegExp(
    r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
  );

  /// Parses `1.2.0`, `v1.2.0-beta.1`, or `1.2.0+42`. Throws [FormatException].
  factory SemVer.parse(String input) {
    final parsed = tryParse(input);
    if (parsed == null) {
      throw FormatException('Invalid semantic version', input);
    }
    return parsed;
  }

  static SemVer? tryParse(String? input) {
    if (input == null) return null;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final match = _pattern.firstMatch(trimmed);
    if (match == null) return null;
    final pre = match.group(4);
    return SemVer(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      pre == null || pre.isEmpty ? const [] : pre.split('.'),
    );
  }

  @override
  int compareTo(SemVer other) {
    var result = major.compareTo(other.major);
    if (result != 0) return result;
    result = minor.compareTo(other.minor);
    if (result != 0) return result;
    result = patch.compareTo(other.patch);
    if (result != 0) return result;

    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;

    final length = preRelease.length < other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var i = 0; i < length; i++) {
      result = _compareIdentifier(preRelease[i], other.preRelease[i]);
      if (result != 0) return result;
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }

  static int _compareIdentifier(String a, String b) {
    final aNum = int.tryParse(a);
    final bNum = int.tryParse(b);
    if (aNum != null && bNum != null) return aNum.compareTo(bNum);
    if (aNum != null) return -1;
    if (bNum != null) return 1;
    return a.compareTo(b);
  }

  bool operator <(SemVer other) => compareTo(other) < 0;
  bool operator <=(SemVer other) => compareTo(other) <= 0;
  bool operator >(SemVer other) => compareTo(other) > 0;
  bool operator >=(SemVer other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) => other is SemVer && compareTo(other) == 0;

  @override
  int get hashCode =>
      Object.hash(major, minor, patch, Object.hashAll(preRelease));

  @override
  String toString() {
    final core = '$major.$minor.$patch';
    if (preRelease.isEmpty) return core;
    return '$core-${preRelease.join('.')}';
  }
}
