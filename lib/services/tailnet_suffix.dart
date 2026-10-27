import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pocket_bot/services/dev_update.dart';
import 'package:pocket_bot/services/tailnet_dns.dart';
import 'package:pocket_bot/utils/logger.dart';

const tailnetSuffixChannel = MethodChannel('pocketbot/tailnet');

const _magicDns = '100.100.100.100';

/// Search domain pushed by the Tailscale VPN, or the phone's own MagicDNS name.
///
/// Android often leaves the VPN search domain blank for other apps, and this
/// app previously could not read link properties at all. A 100.64/10 address
/// is reversed through MagicDNS, which answers `host.tailnet.ts.net`.
Future<TailnetDiscovery> discoverTailnet() async {
  if (Platform.isAndroid) {
    final probe = await _androidProbe();
    final addresses = <String>[
      ...probe.addresses,
      ...await _interfaceAddresses(),
    ];
    final session = _MagicDnsSession();
    try {
      final found = await resolveTailnetSuffix(
        domains: probe.domains,
        addresses: addresses,
        ptrLookup: session.ptr,
        observeLocalTailscaleAddress: session.localAddress,
        magicDnsReachable: session.magicDnsReachable,
      );
      if (found.suffix == null) {
        Logger.warning(
          '[Update] Tailnet suffix missing '
          '(domains="${probe.domains}", tailscale=${found.interfaceUp})',
        );
      } else {
        Logger.info('[Update] Tailnet suffix ${found.suffix}');
      }
      return found;
    } finally {
      session.close();
    }
  }
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    return const TailnetDiscovery();
  }
  try {
    final result = await Process.run('tailscale', const ['dns', 'status']);
    if (result.exitCode != 0) return const TailnetDiscovery();
    final suffix = tailnetSuffixFromText('${result.stdout}\n${result.stderr}');
    return TailnetDiscovery(suffix: suffix, interfaceUp: suffix != null);
  } catch (error) {
    Logger.warning('[Update] tailscale dns status failed: $error');
    return const TailnetDiscovery();
  }
}

class _AndroidProbe {
  const _AndroidProbe({required this.domains, required this.addresses});

  final String domains;
  final List<String> addresses;
}

Future<_AndroidProbe> _androidProbe() async {
  try {
    final raw = await tailnetSuffixChannel.invokeMethod<dynamic>('suffix');
    if (raw is String) {
      return _AndroidProbe(domains: raw, addresses: const []);
    }
    if (raw is Map) {
      return _AndroidProbe(
        domains: raw['domains']?.toString() ?? '',
        addresses: _stringList(raw['addresses']),
      );
    }
  } catch (error) {
    Logger.warning('[Update] Tailnet network probe failed: $error');
  }
  return const _AndroidProbe(domains: '', addresses: []);
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList();
  }
  if (value is String && value.trim().isNotEmpty) {
    return value.split(RegExp(r'[\s,;]+'));
  }
  return const [];
}

Future<List<String>> _interfaceAddresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses) address.address,
    ];
  } catch (error) {
    Logger.warning('[Update] Network interface lookup failed: $error');
    return const [];
  }
}

/// One TCP session to MagicDNS.
///
/// Dart often reports this socket's local address as 100.100.100.100, so the
/// node address has to come from the VPN interface. A completed connection
/// still means the device is on the tailnet.
class _MagicDnsSession {
  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  final List<int> _buffer = [];
  Completer<void>? _waiter;
  bool _failed = false;
  bool _closed = false;
  bool _reachable = false;
  int _nextId = 1;

  Future<String?> localAddress() async {
    final socket = await _open();
    if (socket == null) return null;
    return tailscaleIpv4FromAddress(socket.address.address);
  }

  Future<bool> magicDnsReachable() async {
    await _open();
    return _reachable;
  }

  Future<String?> ptr(String ipv4) async {
    final socket = await _open();
    if (socket == null || _closed) return null;
    final id = _nextId;
    _nextId = (_nextId + 1) & 0xffff;
    if (_nextId == 0) _nextId = 1;
    try {
      socket.add(frameDnsTcp(encodeDnsPtrQuery(id: id, ipv4: ipv4)));
      await socket.flush();
    } catch (error) {
      _fail(error);
      return null;
    }
    final header = await _take(2);
    if (header == null) return null;
    final length = (header[0] << 8) | header[1];
    if (length <= 0 || length > 2048) return null;
    final message = await _take(length);
    if (message == null) return null;
    return ptrNameFromDnsResponse(message, queryId: id);
  }

  Future<Socket?> _open() async {
    if (_failed) return null;
    final existing = _socket;
    if (existing != null) return existing;
    try {
      final socket = await Socket.connect(
        InternetAddress(_magicDns),
        53,
        timeout: const Duration(seconds: 3),
      );
      _socket = socket;
      _reachable = true;
      _subscription = socket.listen(
        _onData,
        onError: _fail,
        onDone: _onDone,
        cancelOnError: false,
      );
      return socket;
    } catch (error) {
      _failed = true;
      Logger.warning('[Update] MagicDNS unreachable: $error');
      return null;
    }
  }

  void _onData(Uint8List data) {
    _buffer.addAll(data);
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  void _onDone() {
    _closed = true;
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  void _fail(Object error, [StackTrace? stackTrace]) {
    _closed = true;
    _failed = true;
    Logger.warning('[Update] MagicDNS read failed: $error');
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<Uint8List?> _take(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (_buffer.length < count) {
      if (_closed) return null;
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return null;
      final waiter = Completer<void>();
      _waiter = waiter;
      if (_buffer.length >= count || _closed) break;
      try {
        await waiter.future.timeout(remaining);
      } on TimeoutException {
        if (identical(_waiter, waiter)) _waiter = null;
        _closed = true;
        return null;
      }
    }
    if (_buffer.length < count) return null;
    final bytes = Uint8List.fromList(_buffer.sublist(0, count));
    _buffer.removeRange(0, count);
    return bytes;
  }

  void close() {
    _closed = true;
    _subscription?.cancel();
    _socket?.destroy();
    _socket = null;
    _subscription = null;
  }
}
