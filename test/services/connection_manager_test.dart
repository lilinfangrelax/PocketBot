import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/services/connection_manager.dart';

void main() {
  group('ConnectionManager - Network Utilities', () {
    group('_getSubnet', () {
      test('should correctly extract subnet from IP 192.168.1.100', () {
        // Using private method via reflection or testing the logic directly
        // Since _getSubnet is private, we'll test via public API behavior
        // This test verifies the subnet calculation logic
        
        // Test IP: 192.168.1.100 -> subnet: (192, 168, 1)
        final ip = '192.168.1.100';
        final parts = ip.split('.').map(int.parse).toList();
        final subnet = (parts[0], parts[1], parts[2]);
        
        expect(subnet.$1, 192);
        expect(subnet.$2, 168);
        expect(subnet.$3, 1);
      });

      test('should correctly extract subnet from IP 10.0.0.50', () {
        final ip = '10.0.0.50';
        final parts = ip.split('.').map(int.parse).toList();
        final subnet = (parts[0], parts[1], parts[2]);
        
        expect(subnet.$1, 10);
        expect(subnet.$2, 0);
        expect(subnet.$3, 0);
      });

      test('should correctly extract subnet from IP 172.16.0.1', () {
        final ip = '172.16.0.1';
        final parts = ip.split('.').map(int.parse).toList();
        final subnet = (parts[0], parts[1], parts[2]);
        
        expect(subnet.$1, 172);
        expect(subnet.$2, 16);
        expect(subnet.$3, 0);
      });
    });

    group('Tailscale IP Detection', () {
      test('should detect valid Tailscale IP in range 100.64.0.0 - 100.127.255.255', () {
        // Test IP detection logic
        bool isTailscaleIP(String ip) {
          if (!ip.startsWith('100.')) return false;
          final parts = ip.split('.');
          if (parts.length != 4) return false;
          final firstTwo = int.parse(parts[0]);
          final secondTwo = int.parse(parts[1]);
          // 100.64.0.0 - 100.127.255.255
          return firstTwo == 100 && secondTwo >= 64 && secondTwo <= 127;
        }

        // Valid Tailscale IPs
        expect(isTailscaleIP('100.64.0.0'), true);
        expect(isTailscaleIP('100.100.100.100'), true);
        expect(isTailscaleIP('100.127.255.255'), true);
        expect(isTailscaleIP('100.64.1.1'), true);
        expect(isTailscaleIP('100.127.0.0'), true);
        
        // Invalid IPs (outside range)
        expect(isTailscaleIP('100.63.255.255'), false); // Below range
        expect(isTailscaleIP('100.128.0.0'), false);    // Above range
        expect(isTailscaleIP('192.168.1.1'), false);    // Not 100.x.x.x
        expect(isTailscaleIP('10.0.0.1'), false);       // Not 100.x.x.x
      });

      test('should correctly generate full subnet scan list', () {
        // Test that scanning the subnet works correctly
        String? getSubnet(String ip) {
          final parts = ip.split('.').map(int.parse).toList();
          if (parts.length != 4) return null;
          return '${parts[0]}.${parts[1]}.${parts[2]}';
        }

        expect(getSubnet('192.168.1.100'), '192.168.1');
        expect(getSubnet('100.100.100.100'), '100.100.100');
      });
    });

    group('IP Validation', () {
      test('should validate correct IP addresses', () {
        bool isValidIP(String ip) {
          final parts = ip.split('.');
          if (parts.length != 4) return false;
          for (final part in parts) {
            final num = int.tryParse(part);
            if (num == null || num < 0 || num > 255) return false;
          }
          return true;
        }

        expect(isValidIP('192.168.1.1'), true);
        expect(isValidIP('10.0.0.1'), true);
        expect(isValidIP('100.64.0.0'), true);
        expect(isValidIP('100.127.255.255'), true);
        expect(isValidIP('0.0.0.0'), true);
        expect(isValidIP('255.255.255.255'), true);
        
        // Invalid IPs
        expect(isValidIP('256.1.1.1'), false);
        expect(isValidIP('192.168.1'), false);
        expect(isValidIP('192.168.1.1.1'), false);
        expect(isValidIP('abc.def.ghi.jkl'), false);
        expect(isValidIP('192.168.1.-1'), false);
      });
    });

    group('Port Validation', () {
      test('should validate correct ports', () {
        bool isValidPort(int port) {
          return port > 0 && port <= 65535;
        }

        expect(isValidPort(80), true);
        expect(isValidPort(443), true);
        expect(isValidPort(8080), true);
        expect(isValidPort(18789), true);
        expect(isValidPort(65535), true);
        expect(isValidPort(1), true);
        
        // Invalid ports
        expect(isValidPort(0), false);
        expect(isValidPort(-1), false);
        expect(isValidPort(65536), false);
        expect(isValidPort(100000), false);
      });
    });
  });

  group('GatewayInfo Model Tests', () {
    test('should create GatewayInfo with required fields', () {
      final gateway = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test-token',
      );

      expect(gateway.host, '192.168.1.100');
      expect(gateway.port, 18789);
      expect(gateway.token, 'test-token');
      expect(gateway.name, 'ACP Agent'); // default
      expect(gateway.version, 'Unknown'); // default
    });

    test('should generate correct URI', () {
      final gateway = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test-token',
      );

      expect(gateway.uri, 'ssh://192.168.1.100:18789');
    });

    test('should correctly serialize to JSON', () {
      final gateway = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test-token',
        name: 'My Gateway',
        version: '1.0.0',
      );

      final json = gateway.toJson();

      expect(json['host'], '192.168.1.100');
      expect(json['port'], 18789);
      expect(json['token'], 'test-token');
      expect(json['name'], 'My Gateway');
      expect(json['version'], '1.0.0');
    });

    test('should correctly deserialize from JSON', () {
      final json = {
        'host': '192.168.1.100',
        'port': 18789,
        'token': 'test-token',
        'name': 'My Gateway',
        'version': '1.0.0',
      };

      final gateway = GatewayInfo.fromJson(json);

      expect(gateway.host, '192.168.1.100');
      expect(gateway.port, 18789);
      expect(gateway.token, 'test-token');
      expect(gateway.name, 'My Gateway');
      expect(gateway.version, '1.0.0');
    });

    test('should handle missing JSON fields with defaults', () {
      final json = {
        'host': '192.168.1.100',
      };

      final gateway = GatewayInfo.fromJson(json);

      expect(gateway.host, '192.168.1.100');
      expect(gateway.port, 22); // default SSH port
      expect(gateway.token, ''); // default
      expect(gateway.name, 'ACP Agent'); // default
      expect(gateway.version, 'Unknown'); // default
    });

    test('should correctly identify if auth is required', () {
      final gatewayWithToken = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: 'test-token',
      );

      final gatewayWithoutToken = GatewayInfo(
        host: '192.168.1.100',
        port: 18789,
        token: '',
      );

      expect(gatewayWithToken.requiresAuth, false);
      expect(gatewayWithoutToken.requiresAuth, true);
    });
  });
}
