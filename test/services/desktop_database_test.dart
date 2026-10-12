import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/services/desktop_database.dart';

void main() {
  test('desktop database uses FFI on Windows and Linux', () {
    expect(
      desktopNeedsFfiDatabase(isWeb: false, operatingSystem: 'windows'),
      isTrue,
    );
    expect(
      desktopNeedsFfiDatabase(isWeb: false, operatingSystem: 'linux'),
      isTrue,
    );
    expect(
      desktopNeedsFfiDatabase(isWeb: false, operatingSystem: 'android'),
      isFalse,
    );
    expect(
      desktopNeedsFfiDatabase(isWeb: false, operatingSystem: 'macos'),
      isFalse,
    );
    expect(
      desktopNeedsFfiDatabase(isWeb: true, operatingSystem: 'windows'),
      isFalse,
    );
  });
}
