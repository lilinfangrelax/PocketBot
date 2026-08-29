import 'package:pocket_bot/utils/semver.dart';
import 'package:test/test.dart';

void main() {
  group('SemVer.parse', () {
    test('parses core versions and optional v prefix', () {
      expect(SemVer.parse('1.2.3').toString(), '1.2.3');
      expect(SemVer.parse('v1.2.3').toString(), '1.2.3');
    });

    test('parses prerelease and ignores build metadata', () {
      expect(SemVer.parse('1.2.0-beta.1').toString(), '1.2.0-beta.1');
      expect(SemVer.parse('v1.2.0-beta.1+8').toString(), '1.2.0-beta.1');
    });

    test('tryParse returns null for invalid input', () {
      expect(SemVer.tryParse(null), isNull);
      expect(SemVer.tryParse(''), isNull);
      expect(SemVer.tryParse('latest'), isNull);
      expect(SemVer.tryParse('1.2'), isNull);
    });
  });

  group('SemVer.compareTo', () {
    test('orders by major.minor.patch', () {
      expect(SemVer.parse('1.1.1') < SemVer.parse('1.1.2'), isTrue);
      expect(SemVer.parse('1.2.0') > SemVer.parse('1.1.9'), isTrue);
      expect(SemVer.parse('2.0.0') > SemVer.parse('1.9.9'), isTrue);
    });

    test('release is newer than matching prerelease', () {
      expect(SemVer.parse('1.2.0-beta.1') < SemVer.parse('1.2.0'), isTrue);
      expect(SemVer.parse('1.2.0') > SemVer.parse('1.2.0-beta.11'), isTrue);
    });

    test('orders prerelease identifiers per semver', () {
      expect(
          SemVer.parse('1.0.0-alpha') < SemVer.parse('1.0.0-alpha.1'), isTrue);
      expect(
          SemVer.parse('1.0.0-alpha.1') < SemVer.parse('1.0.0-beta'), isTrue);
      expect(SemVer.parse('1.0.0-beta') < SemVer.parse('1.0.0-beta.2'), isTrue);
      expect(SemVer.parse('1.0.0-beta.2') < SemVer.parse('1.0.0-rc.1'), isTrue);
      expect(
          SemVer.parse('1.0.0-beta.2') < SemVer.parse('1.0.0-beta.11'), isTrue);
    });

    test('does not treat a newer beta as a downgrade from older stable', () {
      expect(SemVer.parse('1.3.0-beta.1') > SemVer.parse('1.2.5'), isTrue);
    });
  });
}
