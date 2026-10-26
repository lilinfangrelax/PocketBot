import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pocket_bot/services/dev_update.dart';
import 'package:pocket_bot/utils/logger.dart';

const tailnetSuffixChannel = MethodChannel('pocketbot/tailnet');

/// Search domain pushed by the Tailscale VPN, or the local `tailscale` CLI.
Future<String?> discoverTailnetSuffix() async {
  if (Platform.isAndroid) {
    try {
      final raw = await tailnetSuffixChannel.invokeMethod<String>('suffix');
      return tailnetSuffixFromText(raw ?? '');
    } catch (error) {
      Logger.warning('[Update] Tailnet suffix lookup failed: $error');
      return null;
    }
  }
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    return null;
  }
  try {
    final result = await Process.run('tailscale', const ['dns', 'status']);
    if (result.exitCode != 0) return null;
    return tailnetSuffixFromText('${result.stdout}\n${result.stderr}');
  } catch (error) {
    Logger.warning('[Update] tailscale dns status failed: $error');
    return null;
  }
}
