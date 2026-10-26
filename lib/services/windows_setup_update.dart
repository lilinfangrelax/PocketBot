import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pocket_bot/services/github_release_client.dart';

/// Per-user uninstall key written by windows/packaging/pocketbot.iss.
const pocketBotUninstallKey =
    r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{8F4C1A2E-6B7D-4E91-9C3A-1D5E7F0A2B64}_is1';

/// How a downloaded Setup.exe should be started.
class WindowsSetupPlan {
  const WindowsSetupPlan.silent({
    required this.installDir,
    required this.relaunchExe,
  }) : silent = true;

  const WindowsSetupPlan.interactive()
      : silent = false,
        installDir = null,
        relaunchExe = null;

  final bool silent;

  /// Directory passed to Inno `/DIR=`. Set only for [silent].
  final String? installDir;

  /// Executable started after a silent setup. Set only for [silent].
  final String? relaunchExe;
}

final path.Context _windowsPath = path.Context(style: path.Style.windows);

/// Silent in-place upgrade only when this process is the registered install.
///
/// A portable copy, a dev build, or a missing uninstall entry opens the
/// installer wizard instead of writing over an unrelated directory.
WindowsSetupPlan planWindowsSetupUpdate({
  required String executablePath,
  required String? registeredInstallDir,
}) {
  final registered = registeredInstallDir?.trim();
  if (registered == null || registered.isEmpty || !_safePath(registered)) {
    return const WindowsSetupPlan.interactive();
  }
  final executable = executablePath.trim();
  if (!_safePath(executable)) return const WindowsSetupPlan.interactive();

  final exeDir = _windowsPath.dirname(_windowsPath.normalize(executable));
  final installDir = _windowsPath.normalize(registered);
  if (_windowsPath.equals(exeDir, executable) ||
      exeDir == '.' ||
      !directoriesMatch(exeDir, installDir)) {
    return const WindowsSetupPlan.interactive();
  }
  final relaunch = _windowsPath.normalize(executable);
  if (!directoriesMatch(_windowsPath.dirname(relaunch), installDir)) {
    return const WindowsSetupPlan.interactive();
  }
  return WindowsSetupPlan.silent(installDir: installDir, relaunchExe: relaunch);
}

bool directoriesMatch(String left, String right) {
  return _windowsPath.normalize(left).toLowerCase() ==
      _windowsPath.normalize(right).toLowerCase();
}

/// Reads `InstallLocation` from `reg query` output. Empty values are ignored.
String? parseInstallLocation(String regOutput) {
  for (final rawLine in regOutput.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    final match = RegExp(
      r'^InstallLocation\s+REG_\w+\s+(.*)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (match == null) continue;
    final value = match.group(1)!.trim();
    if (value.isEmpty) return null;
    return value;
  }
  return null;
}

Future<String?> queryInnoInstallLocation() async {
  if (!Platform.isWindows) return null;
  try {
    final result = await Process.run(
      'reg',
      ['query', pocketBotUninstallKey, '/v', 'InstallLocation'],
    );
    if (result.exitCode != 0) return null;
    return parseInstallLocation('${result.stdout}');
  } catch (_) {
    return null;
  }
}

/// Waits until [waitingForPid] exits, runs silent setup into [installDir],
/// then starts [relaunchExe]. The PowerShell process is detached.
///
/// Returns false when the helper could not be started. The downloaded setup
/// file must stay in place until the helper finishes.
Future<bool> launchInstalledSetupUpdate({
  required File setup,
  required String installDir,
  required String relaunchExe,
  required int waitingForPid,
}) async {
  if (!isWindowsSetupFileName(path.basename(setup.path))) return false;
  final systemRoot = Platform.environment['SystemRoot'];
  if (systemRoot == null || systemRoot.isEmpty) return false;
  final powershell = path.join(
    systemRoot,
    r'System32\WindowsPowerShell\v1.0\powershell.exe',
  );
  if (!File(powershell).existsSync()) return false;

  final directory = setup.parent;
  final planFile = File(path.join(directory.path, 'pocketbot-update.json'));
  final scriptFile = File(path.join(directory.path, 'pocketbot-update.ps1'));
  final plan = jsonEncode({
    'pid': waitingForPid,
    'setup': setup.path,
    'installDir': installDir,
    'relaunch': relaunchExe,
  });
  await planFile.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(plan)]);
  await scriptFile.writeAsString(installedSetupScript, flush: true);

  await Process.start(
    powershell,
    [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      scriptFile.path,
      planFile.path,
    ],
    mode: ProcessStartMode.detached,
  );
  return true;
}

/// ASCII helper. Paths come from the UTF-8 JSON plan, not from this file.
const installedSetupScript = r'''
$ErrorActionPreference = 'Stop'
$planPath = $args[0]
$plan = Get-Content -LiteralPath $planPath -Encoding UTF8 -Raw | ConvertFrom-Json
$log = Join-Path (Split-Path -Parent $planPath) 'pocketbot-update.log'
function Write-Log($message) {
  Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date -Format o), $message)
}
try {
  $processId = [int]$plan.pid
  Write-Log ("waiting for pid {0}" -f $processId)
  $deadline = (Get-Date).AddMinutes(30)
  while (Get-Process -Id $processId -ErrorAction SilentlyContinue) {
    if ((Get-Date) -gt $deadline) {
      Write-Log 'timed out waiting for PocketBot to exit'
      exit 1
    }
    Start-Sleep -Seconds 1
  }
  $installDir = [string]$plan.installDir
  if ($installDir.Contains('"')) { throw 'Install directory contains a quote' }
  Write-Log ("running setup {0}" -f $plan.setup)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = [string]$plan.setup
  $psi.Arguments = '/VERYSILENT /NORESTART /CURRENTUSER /DIR="' + $installDir + '"'
  $psi.UseShellExecute = $true
  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $psi
  [void]$proc.Start()
  $proc.WaitForExit()
  Write-Log ("setup exit {0}" -f $proc.ExitCode)
  $relaunch = [string]$plan.relaunch
  if (Test-Path -LiteralPath $relaunch) {
    Start-Process -FilePath $relaunch | Out-Null
    Write-Log ("relaunched {0}" -f $relaunch)
  }
} catch {
  Write-Log $_.Exception.Message
  exit 1
}
''';

bool _safePath(String value) {
  return !value.contains('"') &&
      !value.contains('\n') &&
      !value.contains('\r') &&
      !value.contains('%');
}
