import 'package:pocket_bot/utils/android_version_code.dart';
import 'package:test/test.dart';

void main() {
  test('ignores a hand-added build number', () {
    expect(androidVersionCode('1.2.0-beta.8+8'), 10200008);
    expect(androidVersionCode('1.2.0-beta.8'), 10200008);
  });

  test('beta numbers stay ordered and below the stable release', () {
    expect(
      androidVersionCode('1.2.0-beta.9'),
      greaterThan(androidVersionCode('1.2.0-beta.8')),
    );
    expect(
      androidVersionCode('1.2.0'),
      greaterThan(androidVersionCode('1.2.0-beta.9')),
    );
    expect(
      androidVersionCode('1.2.0-rc.1'),
      greaterThan(androidVersionCode('1.2.0-beta.9')),
    );
    expect(
      androidVersionCode('1.2.0'),
      greaterThan(androidVersionCode('1.2.0-rc.1')),
    );
  });

  test('plain patch versions keep increasing past older beta tags', () {
    expect(
      androidVersionCode('1.2.2'),
      greaterThan(androidVersionCode('1.2.1')),
    );
    expect(
      androidVersionCode('1.2.1'),
      greaterThan(androidVersionCode('1.2.0-beta.8')),
    );
    expect(
      androidVersionCode('1.3.0'),
      greaterThan(androidVersionCode('1.2.2')),
    );
  });
}
