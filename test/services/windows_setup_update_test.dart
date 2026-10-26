import 'package:pocket_bot/services/windows_setup_update.dart';
import 'package:test/test.dart';

void main() {
  const installDir = r'C:\Users\ada\AppData\Local\PocketBot';
  const executable = r'C:\Users\ada\AppData\Local\PocketBot\PocketBot.exe';

  group('planWindowsSetupUpdate', () {
    test('replaces the registered installation in place', () {
      final plan = planWindowsSetupUpdate(
        executablePath: executable,
        registeredInstallDir: '$installDir\\',
      );
      expect(plan.silent, isTrue);
      expect(plan.installDir, installDir);
      expect(plan.relaunchExe, executable);
    });

    test('matches the install directory regardless of case', () {
      final plan = planWindowsSetupUpdate(
        executablePath: executable.toLowerCase(),
        registeredInstallDir: installDir.toUpperCase(),
      );
      expect(plan.silent, isTrue);
    });

    test('opens the wizard for a portable or dev copy', () {
      final plan = planWindowsSetupUpdate(
        executablePath:
            r'D:\Dev\PocketBot\dev\build\windows\x64\runner\Release\PocketBot.exe',
        registeredInstallDir: installDir,
      );
      expect(plan.silent, isFalse);
      expect(plan.installDir, isNull);
    });

    test('opens the wizard when nothing is registered', () {
      final plan = planWindowsSetupUpdate(
        executablePath: executable,
        registeredInstallDir: null,
      );
      expect(plan.silent, isFalse);
    });

    test('opens the wizard for a path that cannot be quoted safely', () {
      final plan = planWindowsSetupUpdate(
        executablePath: executable,
        registeredInstallDir: r'C:\Users\ada\App%Data\PocketBot',
      );
      expect(plan.silent, isFalse);
    });
  });

  test('reg query output yields the install location', () {
    const output = r'''
HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\{8F4C1A2E-6B7D-4E91-9C3A-1D5E7F0A2B64}_is1
    InstallLocation    REG_SZ    C:\Users\ada\AppData\Local\PocketBot\

''';
    expect(
      parseInstallLocation(output),
      r'C:\Users\ada\AppData\Local\PocketBot\',
    );
    expect(parseInstallLocation('InstallLocation    REG_SZ    '), isNull);
  });

  test('the helper waits, then runs a silent per-user setup', () {
    expect(installedSetupScript, contains('/VERYSILENT'));
    expect(installedSetupScript, contains('/NORESTART'));
    expect(installedSetupScript, contains('/CURRENTUSER'));
    expect(installedSetupScript, contains(r'/DIR="'));
    expect(installedSetupScript, contains('Get-Process'));
    expect(
        installedSetupScript, contains('Start-Process -FilePath \$relaunch'));
  });
}
