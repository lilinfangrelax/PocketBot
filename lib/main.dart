import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_bot/config/update_config.dart';
import 'package:pocket_bot/screens/main_screen.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/github_update_service.dart';
import 'package:pocket_bot/services/notification_service.dart';
import 'package:pocket_bot/services/websocket_service.dart';
import 'package:pocket_bot/utils/logger.dart';
import 'package:pocket_bot/utils/version_utils.dart';
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

  await AppVersion.init();
  await UpdateConfig.load();

  _initNotifications();
  _scheduleUpdateCheck();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionManager()),
        ChangeNotifierProvider(create: (_) => WebSocketService()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => UserConfigProvider()),
      ],
      child: const PocketBotApp(),
    ),
  );
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

    return MaterialApp(
      title: 'PocketBot',
      navigatorKey: appNavigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          primary: Colors.blue,
          secondary: Colors.blueAccent,
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.interTextTheme(),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          primary: Colors.blue,
          secondary: Colors.blueAccent,
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
