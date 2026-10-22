import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pocket_bot/utils/logger.dart';

/// Static Internet Settings proxy. Auto-config (PAC) is not resolved.
class WindowsProxyConfig {
  const WindowsProxyConfig({this.proxy, this.bypass});

  final String? proxy;
  final String? bypass;
}

WindowsProxyConfig? readWindowsProxyConfig() {
  if (!Platform.isWindows) return null;
  try {
    return _readWindowsProxyConfig();
  } catch (error) {
    Logger.warning('[Update] Windows proxy settings unavailable: $error');
    return null;
  }
}

/// DER certificates from the Windows ROOT store, or empty when unavailable.
List<Uint8List> readWindowsRootCertificates() {
  if (!Platform.isWindows) return const [];
  try {
    return _readWindowsRootCertificates();
  } catch (error) {
    Logger.warning('[Update] Windows root certificates unavailable: $error');
    return const [];
  }
}

WindowsProxyConfig? _readWindowsProxyConfig() {
  // Win64: BOOL plus padding, then three pointers. 32 bytes.
  if (sizeOf<WinHttpCurrentUserIeProxyConfig>() != 32) {
    Logger.warning('[Update] Unexpected WinHTTP proxy struct size');
    return null;
  }
  final winhttp = DynamicLibrary.open('winhttp.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final getConfig = winhttp.lookupFunction<
      Int32 Function(Pointer<WinHttpCurrentUserIeProxyConfig>),
      int Function(Pointer<WinHttpCurrentUserIeProxyConfig>)>(
    'WinHttpGetIEProxyConfigForCurrentUser',
  );
  final globalFree = kernel32.lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)>('GlobalFree');

  final config = calloc<WinHttpCurrentUserIeProxyConfig>();
  try {
    if (getConfig(config) == 0) return null;
    final proxy = _takeUtf16(config.ref.lpszProxy, globalFree);
    final bypass = _takeUtf16(config.ref.lpszProxyBypass, globalFree);
    _takeUtf16(config.ref.lpszAutoConfigUrl, globalFree);
    return WindowsProxyConfig(proxy: proxy, bypass: bypass);
  } finally {
    calloc.free(config);
  }
}

List<Uint8List> _readWindowsRootCertificates() {
  // Win64 CERT_CONTEXT is 40 bytes. A mismatch would read off the struct.
  if (sizeOf<CertContext>() != 40) {
    Logger.warning('[Update] Unexpected certificate context size');
    return const [];
  }
  final crypt32 = DynamicLibrary.open('crypt32.dll');
  final openStore = crypt32.lookupFunction<
      Pointer<Void> Function(IntPtr, Pointer<Utf16>),
      Pointer<Void> Function(int, Pointer<Utf16>)>('CertOpenSystemStoreW');
  final enumCerts = crypt32.lookupFunction<
      Pointer<CertContext> Function(Pointer<Void>, Pointer<CertContext>),
      Pointer<CertContext> Function(Pointer<Void>, Pointer<CertContext>)>(
    'CertEnumCertificatesInStore',
  );
  final freeContext = crypt32.lookupFunction<
      Int32 Function(Pointer<CertContext>),
      int Function(Pointer<CertContext>)>('CertFreeCertificateContext');
  final closeStore = crypt32.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)>('CertCloseStore');

  final name = 'ROOT'.toNativeUtf16();
  try {
    final store = openStore(0, name);
    if (store == nullptr) return const [];
    final certs = <Uint8List>[];
    var current = nullptr.cast<CertContext>();
    try {
      while (true) {
        current = enumCerts(store, current);
        if (current == nullptr) break;
        final length = current.ref.cbCertEncoded;
        final encoded = current.ref.pbCertEncoded;
        if (encoded == nullptr || length < 64 || length > 65536) continue;
        final view = encoded.asTypedList(length);
        if (view[0] != 0x30) continue;
        // The next enumeration frees this context, so copy the bytes now.
        certs.add(Uint8List.fromList(view));
      }
    } finally {
      if (current != nullptr) freeContext(current);
      closeStore(store, 0);
    }
    return certs;
  } finally {
    malloc.free(name);
  }
}

String? _takeUtf16(
  Pointer<Utf16> pointer,
  Pointer<Void> Function(Pointer<Void>) globalFree,
) {
  if (pointer == nullptr) return null;
  try {
    final value = pointer.toDartString().trim();
    return value.isEmpty ? null : value;
  } finally {
    globalFree(pointer.cast());
  }
}

/// `WINHTTP_CURRENT_USER_IE_PROXY_CONFIG` on Win64.
final class WinHttpCurrentUserIeProxyConfig extends Struct {
  @Int32()
  external int fAutoDetect;

  external Pointer<Utf16> lpszAutoConfigUrl;

  external Pointer<Utf16> lpszProxy;

  external Pointer<Utf16> lpszProxyBypass;
}

/// `CERT_CONTEXT` on Win64.
final class CertContext extends Struct {
  @Uint32()
  external int dwCertEncodingType;

  external Pointer<Uint8> pbCertEncoded;

  @Uint32()
  external int cbCertEncoded;

  external Pointer<Void> pCertInfo;

  external Pointer<Void> hCertStore;
}
