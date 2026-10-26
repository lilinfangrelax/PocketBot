import 'dart:convert';
import 'dart:typed_data';

class ProxyEndpoint {
  const ProxyEndpoint({
    required this.host,
    required this.port,
    this.username,
    this.password,
    this.socks = false,
  });

  final String host;
  final int port;
  final String? username;
  final String? password;
  final bool socks;

  String get directive {
    final hostText = host.contains(':') ? '[$host]' : host;
    return 'PROXY $hostText:$port';
  }

  String get label {
    final hostText = host.contains(':') ? '[$host]' : host;
    return '$hostText:$port';
  }
}

class UpdateProxyChoice {
  const UpdateProxyChoice._(this.endpoint, this.source);

  const UpdateProxyChoice.direct(String source) : this._(null, source);

  const UpdateProxyChoice.proxy(ProxyEndpoint endpoint, String source)
      : this._(endpoint, source);

  final ProxyEndpoint? endpoint;
  final String source;

  String get directive => endpoint?.directive ?? 'DIRECT';

  String get label => endpoint?.label ?? 'DIRECT';
}

/// Selects the proxy for one update URL.
///
/// `HTTPS_PROXY` wins over `ALL_PROXY`, both honor `NO_PROXY`, and a Windows
/// static proxy is used only when those variables are unset. PAC URLs are
/// ignored because resolving them can hang the update check.
UpdateProxyChoice chooseUpdateProxy({
  required Uri target,
  Map<String, String> environment = const {},
  String? windowsProxy,
  String? windowsBypass,
}) {
  // MagicDNS names are only reachable through the tailnet, not an HTTP proxy.
  if (_isTailscaleMagicDns(target.host)) {
    return const UpdateProxyChoice.direct('tailscale');
  }

  if (_hostBypassed(
    target.host,
    _firstEnv(environment, const ['NO_PROXY', 'no_proxy']),
    windowsStyle: false,
  )) {
    return const UpdateProxyChoice.direct('no_proxy');
  }

  final httpsProxy = _firstEnv(
    environment,
    const ['HTTPS_PROXY', 'https_proxy'],
  );
  if (httpsProxy != null) {
    final endpoint = parseProxyEndpoint(httpsProxy);
    if (endpoint == null) {
      return const UpdateProxyChoice.direct('invalid_https_proxy');
    }
    return UpdateProxyChoice.proxy(endpoint, 'https_proxy');
  }

  final allProxy = _firstEnv(environment, const ['ALL_PROXY', 'all_proxy']);
  if (allProxy != null) {
    final endpoint = parseProxyEndpoint(allProxy);
    if (endpoint == null) {
      return const UpdateProxyChoice.direct('invalid_all_proxy');
    }
    return UpdateProxyChoice.proxy(endpoint, 'all_proxy');
  }

  final staticProxy = windowsProxy?.trim();
  if (staticProxy != null && staticProxy.isNotEmpty) {
    if (_hostBypassed(target.host, windowsBypass, windowsStyle: true)) {
      return const UpdateProxyChoice.direct('windows_bypass');
    }
    final endpoint = proxyForTarget(staticProxy, target.scheme);
    if (endpoint != null) {
      return UpdateProxyChoice.proxy(endpoint, 'windows');
    }
  }

  return const UpdateProxyChoice.direct('direct');
}

/// Parses `host:port`, `http://host:port`, or `user:pass@host:port`.
ProxyEndpoint? parseProxyEndpoint(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return null;
  if (!value.contains('://')) {
    value = 'http://$value';
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return null;
  final port = uri.hasPort ? uri.port : _defaultPort(uri.scheme);
  if (port <= 0 || port > 65535) return null;

  String? username;
  String? password;
  final info = uri.userInfo;
  if (info.isNotEmpty) {
    final separator = info.indexOf(':');
    if (separator < 0) {
      username = Uri.decodeComponent(info);
    } else {
      username = Uri.decodeComponent(info.substring(0, separator));
      password = Uri.decodeComponent(info.substring(separator + 1));
    }
  }
  return ProxyEndpoint(
    host: uri.host,
    port: port,
    username: username,
    password: password,
    socks: uri.scheme.startsWith('socks'),
  );
}

/// Picks the `https=` entry for HTTPS, otherwise a keyless proxy value.
ProxyEndpoint? proxyForTarget(String raw, String scheme) {
  final entries = <String, ProxyEndpoint>{};
  ProxyEndpoint? keyless;
  for (final part in raw.split(';')) {
    final piece = part.trim();
    if (piece.isEmpty) continue;
    final eq = piece.indexOf('=');
    final keyHasScheme = eq > 0 && piece.substring(0, eq).contains(':');
    if (eq > 0 && !keyHasScheme) {
      final key = piece.substring(0, eq).trim().toLowerCase();
      final endpoint = parseProxyEndpoint(piece.substring(eq + 1));
      if (key.isNotEmpty && endpoint != null) entries[key] = endpoint;
      continue;
    }
    keyless ??= parseProxyEndpoint(piece);
  }
  return entries[scheme.toLowerCase()] ?? keyless;
}

bool isPlausibleCertDer(List<int> der) {
  return der.length >= 64 && der[0] == 0x30;
}

List<Uint8List> usableCertificateDers(Iterable<List<int>> ders) {
  final usable = <Uint8List>[];
  for (final der in ders) {
    if (!isPlausibleCertDer(der)) continue;
    usable.add(der is Uint8List ? der : Uint8List.fromList(der));
  }
  return usable;
}

String certificateDerToPem(List<int> der) {
  final encoded = base64.encode(der);
  final lines = <String>['-----BEGIN CERTIFICATE-----'];
  for (var i = 0; i < encoded.length; i += 64) {
    final end = i + 64 < encoded.length ? i + 64 : encoded.length;
    lines.add(encoded.substring(i, end));
  }
  lines.add('-----END CERTIFICATE-----');
  return '${lines.join('\n')}\n';
}

/// Replaces `user:pass@` in proxy URLs. Same rule as teshi-update.
String redactProxySecrets(String message) {
  final out = StringBuffer();
  var rest = message;
  while (true) {
    final scheme = rest.indexOf('://');
    if (scheme < 0) break;
    out.write(rest.substring(0, scheme + 3));
    rest = rest.substring(scheme + 3);
    var end = rest.length;
    for (final marker in const [' ', "'", '"', '\n']) {
      final index = rest.indexOf(marker);
      if (index >= 0 && index < end) end = index;
    }
    final authority = rest.substring(0, end);
    final at = authority.lastIndexOf('@');
    if (at >= 0) {
      out
        ..write('***:***@')
        ..write(authority.substring(at + 1));
    } else {
      out.write(authority);
    }
    rest = rest.substring(end);
  }
  out.write(rest);
  return out.toString();
}

String formatUpdateError(Object? error, {int maxLength = 160}) {
  final redacted =
      redactProxySecrets('$error').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (redacted.isEmpty || redacted == 'null') return '';
  if (redacted.length <= maxLength) return redacted;
  return '${redacted.substring(0, maxLength)}…';
}

String? _firstEnv(Map<String, String> environment, List<String> names) {
  for (final name in names) {
    final raw = environment[name];
    if (raw == null) continue;
    var value = raw.trim();
    if (value.length >= 2) {
      final quote = value[0];
      if ((quote == '"' || quote == "'") && value.endsWith(quote)) {
        value = value.substring(1, value.length - 1).trim();
      }
    }
    if (value.isNotEmpty) return value;
  }
  return null;
}

int _defaultPort(String scheme) {
  switch (scheme) {
    case 'https':
      return 443;
    case 'socks':
    case 'socks4':
    case 'socks5':
      return 1080;
    default:
      return 80;
  }
}

bool _isTailscaleMagicDns(String host) {
  final name = _normalizeHost(host);
  return name.endsWith('.ts.net') && name != 'ts.net';
}

bool _hostBypassed(
  String host,
  String? rules, {
  required bool windowsStyle,
}) {
  if (rules == null || rules.trim().isEmpty) return false;
  final hostName = _normalizeHost(host);
  final parts =
      windowsStyle ? rules.split(RegExp(r'[;,\s]+')) : rules.split(',');
  for (final raw in parts) {
    final pattern = raw.trim().toLowerCase();
    if (pattern.isEmpty) continue;
    if (pattern == '*') return true;
    if (windowsStyle && pattern == '<local>') {
      if (!hostName.contains('.') && !hostName.contains(':')) return true;
      continue;
    }
    if (_patternMatchesHost(pattern, hostName, globs: windowsStyle)) {
      return true;
    }
  }
  return false;
}

String _normalizeHost(String host) {
  var value = host.trim().toLowerCase();
  if (value.startsWith('[') && value.endsWith(']') && value.length > 2) {
    value = value.substring(1, value.length - 1);
  }
  return value;
}

bool _patternMatchesHost(
  String pattern,
  String host, {
  required bool globs,
}) {
  if (pattern.contains('/')) return _ipv4MatchesCidr(host, pattern);
  if (_isIp(host) || _isIp(pattern)) return host == pattern;
  var value = pattern;
  if (globs && value.contains('*')) {
    if (value.startsWith('*.')) {
      final suffix = value.substring(2);
      return suffix.isNotEmpty && (host == suffix || host.endsWith('.$suffix'));
    }
    final regex = RegExp(
      '^${value.split('*').map(RegExp.escape).join('.*')}\$',
    );
    return regex.hasMatch(host);
  }
  if (value.startsWith('.')) value = value.substring(1);
  if (value.isEmpty) return false;
  return host == value || host.endsWith('.$value');
}

bool _isIp(String host) => host.contains(':') || _ipv4ToInt(host) != null;

int? _ipv4ToInt(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return null;
  var value = 0;
  for (final part in parts) {
    final octet = int.tryParse(part);
    if (octet == null || octet < 0 || octet > 255) return null;
    value = (value << 8) | octet;
  }
  return value;
}

bool _ipv4MatchesCidr(String host, String cidr) {
  final pieces = cidr.split('/');
  if (pieces.length != 2) return false;
  final prefix = int.tryParse(pieces[1]);
  final network = _ipv4ToInt(pieces[0]);
  final ip = _ipv4ToInt(host);
  if (prefix == null ||
      network == null ||
      ip == null ||
      prefix < 0 ||
      prefix > 32) {
    return false;
  }
  if (prefix == 0) return true;
  final mask = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  return (ip & mask) == (network & mask);
}
