import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/screens/home_screen.dart';
import 'package:pocket_bot/services/connection_manager.dart';
import 'package:pocket_bot/services/ssh_host_pool.dart';
import 'package:pocket_bot/theme/fluent_theme.dart';

class _FakeManager extends ConnectionManager {
  _FakeManager() : super(hosts: SshHostPool(open: (_) => throw 'unused'));

  List<GatewayInfo> saved = [];
  final Map<String, HostState> states = {};

  @override
  List<GatewayInfo> get savedGateways => saved;

  @override
  GatewayInfo? get gateway => null;

  @override
  Future<void> checkGatewaysStatus() async {}

  @override
  HostState hostState(GatewayInfo gateway) =>
      states[gateway.hostId] ?? const HostState(HostStatus.unknown);

  void update() => notifyListeners();
}

void main() {
  testWidgets('saved hosts and their status show up without a reconnect',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final manager = _FakeManager();
    await tester.pumpWidget(
      ChangeNotifierProvider<ConnectionManager>.value(
        value: manager,
        child: FluentApp(
          theme: buildFluentTheme(Brightness.dark),
          builder: (context, child) => material.ScaffoldMessenger(
            child: material.Theme(
              data: buildMaterialTheme(Brightness.dark),
              child: material.Material(
                type: material.MaterialType.transparency,
                child: child!,
              ),
            ),
          ),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('已保存的连接'), findsNothing);

    final host = GatewayInfo.ssh(
      host: '100.73.210.105',
      username: 'lilin',
      password: 'pw',
      name: 'msi',
    );
    manager.saved = [host];
    manager.update();
    await tester.pump();
    expect(find.text('msi'), findsOneWidget);
    expect(find.text('已保存的连接 · SSH 在线 0/1'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);

    manager.states[host.hostId] = const HostState(HostStatus.online);
    manager.update();
    await tester.pump();
    expect(find.text('已保存的连接 · SSH 在线 1/1'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('选目录启动'), findsOneWidget);
  });
}
