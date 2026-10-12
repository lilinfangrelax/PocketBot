import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:pocket_bot/services/update_proxy.dart';
import 'package:pocket_bot/services/windows_update_network.dart';
import 'package:pocket_bot/utils/logger.dart';

/// HTTP client for GitHub release checks.
///
/// Uses `HTTPS_PROXY` / `ALL_PROXY` / `NO_PROXY`, then the Windows static
/// proxy. On Windows, TLS trusts the system ROOT store so an intranet
/// inspection CA is accepted. Dart's default roots are kept when that store
/// cannot be read.
http.Client createUpdateHttpClient() => IOClient(createUpdateIoClient());

Dio createUpdateDio() {
  final dio = Dio();
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: createUpdateIoClient,
  );
  return dio;
}

HttpClient createUpdateIoClient({
  Map<String, String>? environment,
  String? windowsProxy,
  String? windowsBypass,
  List<List<int>>? windowsRoots,
}) {
  final env = environment ?? Platform.environment;
  final windows = (windowsProxy != null || windowsBypass != null)
      ? WindowsProxyConfig(proxy: windowsProxy, bypass: windowsBypass)
      : readWindowsProxyConfig();
  final roots = windowsRoots ?? readWindowsRootCertificates();
  final context = _windowsRootContext(roots);
  final client = HttpClient(context: context);
  client.userAgent = 'PocketBot';
  client.connectionTimeout = const Duration(seconds: 20);
  client.findProxy = _findProxy(
    client,
    environment: env,
    windowsProxy: windows?.proxy,
    windowsBypass: windows?.bypass,
  );

  final preview = chooseUpdateProxy(
    target: Uri.parse('https://api.github.com/'),
    environment: env,
    windowsProxy: windows?.proxy,
    windowsBypass: windows?.bypass,
  );
  final endpoint = preview.endpoint;
  if (endpoint != null && endpoint.socks) {
    Logger.warning(
      '[Update] SOCKS proxy ${endpoint.label} is not supported; '
      'the update client sends HTTP CONNECT',
    );
  }
  Logger.info(
    '[Update] proxy ${preview.label} via ${preview.source}; '
    'windowsRoots=${context == null ? 0 : usableCertificateDers(roots).length}',
  );
  return client;
}

String Function(Uri uri) _findProxy(
  HttpClient client, {
  required Map<String, String> environment,
  required String? windowsProxy,
  required String? windowsBypass,
}) {
  final credentials = <String, ProxyEndpoint>{};
  final attempted = <String>{};
  client.authenticateProxy = (host, port, scheme, realm) async {
    final key = '$host:$port:${realm ?? ''}';
    if (!attempted.add(key)) return false;
    final endpoint = credentials['$host:$port'];
    final username = endpoint?.username;
    if (username == null || username.isEmpty) return false;
    client.addProxyCredentials(
      host,
      port,
      realm ?? '',
      HttpClientBasicCredentials(username, endpoint?.password ?? ''),
    );
    return true;
  };

  return (uri) {
    try {
      final choice = chooseUpdateProxy(
        target: uri,
        environment: environment,
        windowsProxy: windowsProxy,
        windowsBypass: windowsBypass,
      );
      final endpoint = choice.endpoint;
      if (endpoint != null &&
          endpoint.username != null &&
          endpoint.username!.isNotEmpty) {
        credentials['${endpoint.host}:${endpoint.port}'] = endpoint;
      }
      return choice.directive;
    } catch (error) {
      Logger.warning('[Update] Proxy selection failed: $error');
      return 'DIRECT';
    }
  };
}

SecurityContext? _windowsRootContext(List<List<int>> ders) {
  final usable = usableCertificateDers(ders);
  if (usable.isEmpty) return null;
  final context = SecurityContext(withTrustedRoots: false);
  var loaded = 0;
  for (final der in usable) {
    try {
      context.setTrustedCertificatesBytes(
        certificateDerToPem(der).codeUnits,
      );
      loaded++;
    } catch (error) {
      Logger.warning('[Update] Skipped an unreadable Windows root: $error');
    }
  }
  if (loaded == 0) return null;
  return context;
}
