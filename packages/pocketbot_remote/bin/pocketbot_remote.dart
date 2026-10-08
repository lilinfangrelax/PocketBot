import 'dart:io';

import 'package:pocketbot_remote/pocketbot_remote.dart';

Future<void> main(List<String> args) async {
  exit(await runPocketbotRemote(args));
}
