import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_bot/config/update_config.dart';
import 'package:pocket_bot/screens/main_screen.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/contact_agent_linker.dart';
import 'package:pocket_bot/services/group_chat_service.dart';
import 'package:pocket_bot/services/github_update_service.dart';
import 'package:pocket_bot/services/notification_service.dart';
import 'package:pocket_bot/services/ssh_host_keys.dart';
import 'package:pocket_bot/services/websocket_service.dart';
import 'package:pocket_bot/utils/debug_log.dart';
import 'package:pocket_bot/utils/logger.dart';
import 'package:pocket_bot/utils/version_utils.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';
import 'package:pocket_bot/widgets/host_key_dialog.dart';
import 'package:pocket_bot/widgets/update_settings_card.dart';

/// User config provider for avatar changes
class UserConfigProvider with ChangeNotifier {
  static final UserConfigProvider _instance = UserConfigProvider._internal();
  factory UserConfigProvider() => _instance;
  UserConfigProvider._internal();

  final _configChangedController = StreamController<void>.broadcast();
  Stream<void> get configChanged => _configChangedController.stream;

  void notifyConfigChanged() {
    _configChangedController.add(null);
    notifyListeners();
  }
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorHandlers();

  await DebugLog.instance.init();
  await AppVersion.init();
  Logger.info('[App] PocketBot ${AppVersion.fullVersion} started on '
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  await UpdateConfig.load();
  SshHostKeys.prompt = hostKeyPromptFor(appNavigatorKey);

  _initNotifications();
  _scheduleUpdateCheck();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          lazy: false,
          create: (_) {
            final manager = ConnectionManager();
            GroupChatService().linker = ContactAgentLinker(manager);
            return manager;
          },
        ),
        ChangeNotifierProvider(create: (_) => WebSocketService()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => UserConfigProvider()),
      ],
      child: const PocketBotApp(),
    ),
  );
}

void _installErrorHandlers() {
  FlutterError.onError = (details) {
    Logger.error(
      '[Flutter] ${details.exceptionAsString()}',
      details.context?.toDescription(),
      details.stack,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    Logger.error('[Uncaught]', error, stack);
    return true;
  };
}

Future<void> _initNotifications() async {
  final notificationService = NotificationService();
  await notificationService.initialize();
  await notificationService.requestPermissions();
}

void _scheduleUpdateCheck() {
  Future<void>.delayed(const Duration(seconds: 3), () async {
    final service = GithubUpdateService();
    try {
      final result = await service.checkForUpdates();
      if (result == null || !result.updateAvailable) return;
      final context = appNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      await UpdateDialogs.showAvailable(context, result, service: service);
    } catch (e) {
      Logger.warning('[Main] Update check failed: $e');
    } finally {
      service.close();
    }
  });
}

/// Theme provider for dark mode support
class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('theme_mode') ?? 0;
    _themeMode = ThemeMode.values[themeIndex];
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
    notifyListeners();
  }
}

class PocketBotApp extends StatefulWidget {
  const PocketBotApp({super.key});

  @override
  State<PocketBotApp> createState() => _PocketBotAppState();
}

class _PocketBotAppState extends State<PocketBotApp> {
  @override
  void initState() {
    super.initState();
    context.read<ThemeProvider>().loadTheme();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeProvider>().themeMode;

    return FluentApp(
      title: 'PocketBot',
      navigatorKey: appNavigatorKey,
      theme: buildFluentTheme(Brightness.light),
      darkTheme: buildFluentTheme(Brightness.dark),
      themeMode: themeMode,
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final brightness = FluentTheme.of(context).brightness;
        return material.ScaffoldMessenger(
          child: material.Theme(
            data: buildMaterialTheme(brightness),
            child: material.Material(
              type: material.MaterialType.transparency,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}
