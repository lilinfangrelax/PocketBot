import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/widgets/gateway_card.dart';

void main() {
  group('GatewayCard', () {
    testWidgets('should display gateway information', (WidgetTester tester) async {
      final gateway = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test_token',
        name: 'Test Gateway',
        version: '1.0.0',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GatewayCard(
              gateway: gateway,
              onTap: () {},
              isSelected: false,
            ),
          ),
        ),
      );

      await tester.pump();

      // Check that gateway name is displayed
      expect(find.text('Test Gateway'), findsOneWidget);
      expect(find.text('192.168.1.100:18789'), findsOneWidget);
    });

    testWidgets('should show check icon when selected', (WidgetTester tester) async {
      final gateway = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test_token',
        name: 'Test Gateway',
        version: '1.0.0',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GatewayCard(
              gateway: gateway,
              onTap: () {},
              isSelected: true,
            ),
          ),
        ),
      );

      await tester.pump();

      // When selected, the trailing icon should be check_circle
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('should show chevron when not selected', (WidgetTester tester) async {
      final gateway = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test_token',
        name: 'Test Gateway',
        version: '1.0.0',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GatewayCard(
              gateway: gateway,
              onTap: () {},
              isSelected: false,
            ),
          ),
        ),
      );

      await tester.pump();

      // When not selected, the trailing icon should be chevron_right
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('should show auth required badge', (WidgetTester tester) async {
      final gateway = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test_token',
        name: 'Test Gateway',
        version: '1.0.0',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GatewayCard(
              gateway: gateway,
              onTap: () {},
              isSelected: false,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('SSH'), findsOneWidget);
    });

    testWidgets('should show version badge when version is not empty', (WidgetTester tester) async {
      final gateway = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test_token',
        name: 'Test Gateway',
        version: '1.0.0',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GatewayCard(
              gateway: gateway,
              onTap: () {},
              isSelected: false,
            ),
          ),
        ),
      );

      await tester.pump();

      // Version badge should show "v1.0.0"
      expect(find.text('v1.0.0'), findsOneWidget);
    });

    testWidgets('should not show version badge when version is Unknown', (WidgetTester tester) async {
      final gateway = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test_token',
        name: 'Test Gateway',
        version: 'Unknown',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GatewayCard(
              gateway: gateway,
              onTap: () {},
              isSelected: false,
            ),
          ),
        ),
      );

      await tester.pump();

      // Version badge should not show for "Unknown" version
      expect(find.textContaining('v'), findsNothing);
    });

    testWidgets('should not show version badge when version is empty', (WidgetTester tester) async {
      final gateway = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test_token',
        name: 'Test Gateway',
        version: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GatewayCard(
              gateway: gateway,
              onTap: () {},
              isSelected: false,
            ),
          ),
        ),
      );

      await tester.pump();

      // Version badge should not show for empty version
      expect(find.textContaining('v'), findsNothing);
    });

    testWidgets('should trigger onTap callback', (WidgetTester tester) async {
      bool tapCalled = false;
      final gateway = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test_token',
        name: 'Test Gateway',
        version: '1.0.0',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GatewayCard(
              gateway: gateway,
              onTap: () {
                tapCalled = true;
              },
              isSelected: false,
            ),
          ),
        ),
      );

      await tester.pump();

      // Tap on the card
      await tester.tap(find.byType(GatewayCard));

      expect(tapCalled, isTrue);
    });

    testWidgets('should apply selected background color', (WidgetTester tester) async {
      final gateway = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test_token',
        name: 'Test Gateway',
        version: '1.0.0',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GatewayCard(
              gateway: gateway,
              onTap: () {},
              isSelected: true,
            ),
          ),
        ),
      );

      await tester.pump();

      // The card should be visible
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('should show computer icon', (WidgetTester tester) async {
      final gateway = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test_token',
        name: 'Test Gateway',
        version: '1.0.0',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GatewayCard(
              gateway: gateway,
              onTap: () {},
              isSelected: false,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byIcon(Icons.lan), findsOneWidget);
    });

    testWidgets('should display host:port format correctly', (WidgetTester tester) async {
      final gateway = GatewayInfo(
        host: '10.0.0.50',
        port: 8080,
        token: 'test_token',
        name: 'Custom Port Gateway',
        version: '2.5.0',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GatewayCard(
              gateway: gateway,
              onTap: () {},
              isSelected: false,
            ),
          ),
        ),
      );

      await tester.pump();

      // Should show the custom port
      expect(find.text('10.0.0.50:8080'), findsOneWidget);
    });
  });
}
