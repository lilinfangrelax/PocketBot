import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pocket_bot/services/update_proxy.dart';
import 'package:pocket_bot/services/update_transport.dart';
import 'package:test/test.dart';

/// One-day test root generated for PEM loading. Not a production certificate.
const _testRootDer = '''
MIIDITCCAgmgAwIBAgIUNFH7gVfQalPm1GPY2v1G8u/F7vUwDQYJKoZIhvcNAQEL
BQAwIDEeMBwGA1UEAwwVUG9ja2V0Qm90IFVwZGF0ZSBUZXN0MB4XDTI2MTAxMjA4
MDQ0NloXDTI2MTAxMzA4MDQ0NlowIDEeMBwGA1UEAwwVUG9ja2V0Qm90IFVwZGF0
ZSBUZXN0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyadv57e5cRFF
b/XcOo/uhRfz50Obz2YaXC01NWLkQnK/zEbk7WzrLSriskHfxQD9s6tjnB2DFbY7
PHRbWgIVVqma45Hsw8zVnFbv7ssOx1foe8u+KdISTgCp9YxVhafqyQfNkpfFN60F
apVEKX8WmSKFVqA2gQpQfJFqiSa28Q+lNfCN1EGVyPMJ5FETv/bJjL/BoZmTu3J+
SmOywHdlmLJdQ9gV6P6/Xc7htGpunXVwaED+Q2JsFgd6h25zEQEkNFlk/wcwV2MS
ijuLX8bXgFWouzv5ou0Pw1RjibT69vIU+SvOjiF6R/pafyk0hbXKzKnEOppGP9fM
gDSkQWa/DwIDAQABo1MwUTAdBgNVHQ4EFgQUNHJPHID+uVwjymml7OiZx24pxqkw
HwYDVR0jBBgwFoAUNHJPHID+uVwjymml7OiZx24pxqkwDwYDVR0TAQH/BAUwAwEB
/zANBgkqhkiG9w0BAQsFAAOCAQEAXq0iwk86KeaWv9JB7Tjsb5BoDBjjfpwIxvQP
gNSSXcV0SgXMAeYxwCHSt+GzAuk7e+58O9QQUC/Qfx4dnDFImEHWF/Oq6RLkWU01
HJeIcw7fG85yE9XF/bSYUjWfuYvGvoneW1LNjfC4gKVvpvL2WurZr/2lKx9IlWdj
2g2uoiAvukEQYsx0WYUaJXiAuTHhJYzleL/ejPxOJ5J5pH+LPTTW8vM1ZMUA3rwn
XY5FOoOx/tkeShiEb9jgLzJw2rDFrsmJqKvRUIbFpbH9sP2nq1MVUm95EvA5JF+e
b3IDI2fVJFDDfbXtW1sQJzDmtcMsTiWhUhp6WwtesrAIFo//jQ==
''';

void main() {
  final github = Uri.parse('https://api.github.com/repos/x/y/releases');

  group('chooseUpdateProxy', () {
    test('https proxy wins over all_proxy and the windows proxy', () {
      final choice = chooseUpdateProxy(
        target: github,
        environment: const {
          'HTTPS_PROXY': 'http://https-proxy.example:8080',
          'ALL_PROXY': 'http://all-proxy.example:8080',
        },
        windowsProxy: 'ie-proxy.example:8080',
      );
      expect(choice.source, 'https_proxy');
      expect(choice.directive, 'PROXY https-proxy.example:8080');
    });

    test('all_proxy is used when https_proxy is unset', () {
      final choice = chooseUpdateProxy(
        target: github,
        environment: const {'ALL_PROXY': 'http://all-proxy.example:9'},
        windowsProxy: 'ie-proxy.example:8080',
      );
      expect(choice.source, 'all_proxy');
      expect(choice.label, 'all-proxy.example:9');
    });

    test('an empty https_proxy does not hide all_proxy', () {
      final choice = chooseUpdateProxy(
        target: github,
        environment: const {
          'HTTPS_PROXY': '   ',
          'all_proxy': 'http://all-proxy.example:8080',
        },
      );
      expect(choice.source, 'all_proxy');
    });

    test('http_proxy alone does not override the windows proxy', () {
      final choice = chooseUpdateProxy(
        target: github,
        environment: const {'HTTP_PROXY': 'http://http-only.example:8080'},
        windowsProxy: 'ie-proxy.example:8080',
      );
      expect(choice.source, 'windows');
      expect(choice.label, 'ie-proxy.example:8080');
    });

    test('no_proxy bypasses an explicit https proxy', () {
      final choice = chooseUpdateProxy(
        target: github,
        environment: const {
          'https_proxy': 'http://proxy.example:8080',
          'NO_PROXY': 'localhost, api.github.com',
        },
      );
      expect(choice.directive, 'DIRECT');
      expect(choice.source, 'no_proxy');
    });

    test('no_proxy matches a parent domain and a cidr', () {
      final domain = chooseUpdateProxy(
        target: github,
        environment: const {
          'HTTPS_PROXY': 'http://proxy.example:8080',
          'NO_PROXY': '.github.com',
        },
      );
      expect(domain.source, 'no_proxy');

      final cidr = chooseUpdateProxy(
        target: Uri.parse('https://10.1.2.3/'),
        environment: const {
          'HTTPS_PROXY': 'http://proxy.example:8080',
          'NO_PROXY': '10.0.0.0/8',
        },
      );
      expect(cidr.source, 'no_proxy');

      final other = chooseUpdateProxy(
        target: Uri.parse('https://11.0.0.1/'),
        environment: const {
          'HTTPS_PROXY': 'http://proxy.example:8080',
          'NO_PROXY': '10.0.0.0/8',
        },
      );
      expect(other.source, 'https_proxy');
    });

    test('windows https entry is preferred over http and a keyless value', () {
      final choice = chooseUpdateProxy(
        target: github,
        windowsProxy:
            'http=plain.example:80;https=secure.example:8443;direct.example:8080',
      );
      expect(choice.source, 'windows');
      expect(choice.label, 'secure.example:8443');
    });

    test('a keyless windows proxy is used when https= is absent', () {
      final choice = chooseUpdateProxy(
        target: github,
        windowsProxy: 'http://proxy.corp.local:8080',
      );
      expect(choice.directive, 'PROXY proxy.corp.local:8080');
    });

    test('windows bypass does not apply to an env proxy', () {
      final choice = chooseUpdateProxy(
        target: Uri.parse('https://intranet.local/'),
        environment: const {'HTTPS_PROXY': 'http://proxy.example:8080'},
        windowsProxy: 'ie-proxy.example:8080',
        windowsBypass: '<local>',
      );
      expect(choice.source, 'https_proxy');
    });

    test('windows bypass skips local names and wildcard domains', () {
      final local = chooseUpdateProxy(
        target: Uri.parse('https://intranet/'),
        windowsProxy: 'proxy.corp:8080',
        windowsBypass: '<local>;*.corp.example',
      );
      expect(local.source, 'windows_bypass');

      final wild = chooseUpdateProxy(
        target: Uri.parse('https://git.corp.example/'),
        windowsProxy: 'proxy.corp:8080',
        windowsBypass: '*.corp.example',
      );
      expect(wild.source, 'windows_bypass');

      final external = chooseUpdateProxy(
        target: github,
        windowsProxy: 'proxy.corp:8080',
        windowsBypass: '<local>;*.corp.example',
      );
      expect(external.label, 'proxy.corp:8080');
    });

    test('proxy credentials stay out of the directive', () {
      final choice = chooseUpdateProxy(
        target: github,
        environment: const {
          'HTTPS_PROXY': 'http://user:secret@proxy.local:8080',
        },
      );
      expect(choice.directive, 'PROXY proxy.local:8080');
      expect(choice.endpoint?.username, 'user');
      expect(choice.endpoint?.password, 'secret');
      expect(choice.directive, isNot(contains('secret')));
    });

    test('an invalid https proxy is not replaced by the windows proxy', () {
      final choice = chooseUpdateProxy(
        target: github,
        environment: const {'HTTPS_PROXY': '://'},
        windowsProxy: 'ie-proxy.example:8080',
      );
      expect(choice.source, 'invalid_https_proxy');
      expect(choice.directive, 'DIRECT');
    });
  });

  group('redactProxySecrets', () {
    test('replaces userinfo and leaves ordinary urls', () {
      expect(
        redactProxySecrets(
          'error sending request for url (https://user:secret@proxy.local:8080/)',
        ),
        'error sending request for url (https://***:***@proxy.local:8080/)',
      );
      expect(
        redactProxySecrets('connection failed for https://github.com'),
        'connection failed for https://github.com',
      );
    });

    test('formatUpdateError truncates long messages', () {
      final detail = formatUpdateError('x' * 400);
      expect(detail.length, 161);
      expect(detail.endsWith('…'), isTrue);
    });
  });

  group('certificates', () {
    test('pem keeps plausible ders and drops the rest', () {
      final good = Uint8List(64)..[0] = 0x30;
      final short = Uint8List(63)..[0] = 0x30;
      final wrong = Uint8List(80)..[0] = 0xff;
      final usable = usableCertificateDers([good, short, wrong, <int>[]]);
      expect(usable, hasLength(1));
      final pem = certificateDerToPem(usable.single);
      expect(pem, startsWith('-----BEGIN CERTIFICATE-----\n'));
      expect(pem, endsWith('-----END CERTIFICATE-----\n'));
      expect(pem, isNot(contains('0xff')));
    });
  });

  test('the update client builds without a windows certificate store', () {
    final client = createUpdateIoClient(
      environment: const {},
      windowsProxy: 'proxy.example:8080',
      windowsRoots: const [],
    );
    client.close();
  });

  test('a plausible root pem is accepted by the tls context', () {
    final der = base64.decode(_testRootDer.replaceAll(RegExp(r'\s'), ''));
    final context = SecurityContext(withTrustedRoots: false);
    context.setTrustedCertificatesBytes(certificateDerToPem(der).codeUnits);
    expect(der.length, greaterThanOrEqualTo(64));
    expect(der.first, 0x30);
  });

  test('https traffic is sent to the configured proxy', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final line = _firstProxyLine(server);
    final client = createUpdateIoClient(
      environment: {'HTTPS_PROXY': 'http://127.0.0.1:${server.port}'},
      windowsRoots: const [],
    );
    try {
      client
          .getUrl(Uri.parse('https://api.github.com/'))
          .then((request) {}, onError: (Object _) {});
      expect(
        await line.timeout(const Duration(seconds: 5)),
        'CONNECT api.github.com:443 HTTP/1.1',
      );
    } finally {
      client.close(force: true);
      await server.close();
    }
  });
}

Future<String> _firstProxyLine(ServerSocket server) {
  final done = Future<Socket>.value(server.first);
  return done.then((socket) async {
    final buffer = StringBuffer();
    await for (final data in socket) {
      buffer.write(String.fromCharCodes(data));
      final text = buffer.toString();
      final end = text.indexOf('\r\n');
      if (end >= 0) {
        socket.destroy();
        return text.substring(0, end);
      }
    }
    socket.destroy();
    return buffer.toString();
  });
}
