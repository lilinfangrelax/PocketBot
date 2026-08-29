import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pocket_bot/config/ota_config.dart';
import 'package:pocket_bot/utils/logger.dart';

/// OTA Update Info Model
class OtaUpdateInfo {
  final bool updateAvailable;
  final String? latestVersion;
  final String? downloadUrl;
  final String? changelog;
  final bool? mandatory;
  final int? fileSize;
  final String? sha256;
  final String? publishedAt;
  final String? currentVersion;

  OtaUpdateInfo({
    required this.updateAvailable,
    this.latestVersion,
    this.downloadUrl,
    this.changelog,
    this.mandatory,
    this.fileSize,
    this.sha256,
    this.publishedAt,
    this.currentVersion,
  });

  factory OtaUpdateInfo.fromJson(Map<String, dynamic> json) {
    return OtaUpdateInfo(
      updateAvailable: json['updateAvailable'] ?? false,
      latestVersion: json['latestVersion'],
      downloadUrl: json['downloadUrl'],
      changelog: json['changelog'],
      mandatory: json['mandatory'] ?? false,
      fileSize: json['fileSize'],
      sha256: json['sha256'],
      publishedAt: json['publishedAt'],
      currentVersion: json['currentVersion'],
    );
  }

  /// Format file size
  String get formattedFileSize {
    if (fileSize == null) return 'Unknown';
    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Whether this is a mandatory update
  bool get isMandatory => mandatory ?? false;
}

/// OTA Hot Update Service
class OtaService {
  static final OtaService _instance = OtaService._internal();
  factory OtaService() => _instance;
  OtaService._internal();
  
  OtaUpdateInfo? _latestUpdate;
  bool _isChecking = false;
  bool _isDownloading = false;

  /// Currently cached update info
  OtaUpdateInfo? get latestUpdate => _latestUpdate;

  /// Whether an update check is in progress
  bool get isChecking => _isChecking;

  /// Whether an update download is in progress
  bool get isDownloading => _isDownloading;

  /// Check for updates
  /// [showProgress] Whether to show progress logs
  Future<OtaUpdateInfo?> checkForUpdates({bool showProgress = true}) async {
    if (!OtaConfig.enabled) {
      if (showProgress) Logger.debug('[OtaService] OTA updates disabled');
      return null;
    }

    if (_isChecking) {
      if (showProgress) Logger.debug('[OtaService] Update check in progress...');
      return _latestUpdate;
    }

    try {
      _isChecking = true;
      
      // Get current version and add channel suffix
      final packageInfo = await PackageInfo.fromPlatform();
      final baseVersion = packageInfo.version;
      final currentVersion = OtaConfig.buildVersion(baseVersion);
      
      if (showProgress) {
        Logger.info('[OtaService] Checking for updates...');
        Logger.info('[OtaService] Current version: $currentVersion (channel: ${OtaConfig.channel.displayName})');
        Logger.debug('[OtaService] Server URL: ${OtaConfig.serverUrl}');
      }

      // Build request URL with channel parameter
      final url = Uri.parse(
        '${OtaConfig.checkUpdateUrl}&version=$currentVersion'
      );

      // Send request
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Update check timeout');
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _latestUpdate = OtaUpdateInfo.fromJson(data);

        if (_latestUpdate!.updateAvailable) {
          if (showProgress) {
            Logger.info('[OtaService] New version found: ${_latestUpdate!.latestVersion}');
            Logger.debug('[OtaService] Update size: ${_latestUpdate!.formattedFileSize}');
          }
        } else {
          if (showProgress) {
            Logger.info('[OtaService] App is up to date');
          }
        }

        return _latestUpdate;
      } else {
        if (showProgress) {
          Logger.error('[OtaService] Update check failed: HTTP ${response.statusCode}');
        }
        return null;
      }
    } on SocketException catch (_) {
      if (showProgress) {
        Logger.warning('[OtaService] Update server not reachable (SocketException)');
      }
      return null;
    } on http.ClientException catch (e) {
      if (showProgress) {
         Logger.warning('[OtaService] Update server not reachable: ${e.message}');
      }
      return null;
    } catch (e) {
      if (showProgress) {
        Logger.error('[OtaService] Update check error: $e');
      }
      return null;
    } finally {
      _isChecking = false;
    }
  }

  /// Download update package
  /// [version] Version number
  /// [onProgress] Download progress callback (0.0 - 1.0)
  /// [savePath] Save path (optional)
  Future<File?> downloadUpdate({
    required String version,
    Function(double)? onProgress,
    String? savePath,
  }) async {
    if (_isDownloading) {
      Logger.debug('[OtaService] Download in progress...');
      return null;
    }

    try {
      _isDownloading = true;
      final downloadUrl = OtaConfig.getDownloadUrl(version);

      Logger.info('[OtaService] Starting download: $version');
      Logger.debug('[OtaService] Download URL: $downloadUrl');

      final response = await http.get(Uri.parse(downloadUrl));

      if (response.statusCode == 200) {
        // Determine save path
        final directory = savePath != null 
          ? Directory(savePath) 
          : await _getUpdateDirectory();
        
        if (!directory.existsSync()) {
          directory.createSync(recursive: true);
        }

        final filePath = '${directory.path}/update-$version.zip';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        Logger.info('[OtaService] Download complete: $filePath');
        Logger.debug('[OtaService] File size: ${(response.bodyBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');

        return file;
      } else {
        Logger.error('[OtaService] Download failed: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      Logger.error('[OtaService] Download error: $e');
      return null;
    } finally {
      _isDownloading = false;
      if (onProgress != null) onProgress(1.0);
    }
  }

  /// Get update package storage directory
  Future<Directory> _getUpdateDirectory() async {
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/pocketbot_updates'
    );
    return directory;
  }

  /// Clean up old update packages
  Future<void> cleanupOldUpdates() async {
    try {
      final directory = await _getUpdateDirectory();
      if (directory.existsSync()) {
        final files = directory.listSync();
        for (final file in files) {
          if (file is File && file.path.endsWith('.zip')) {
            // Delete packages older than 7 days
            final lastModified = file.lastModifiedSync();
            if (DateTime.now().difference(lastModified).inDays > 7) {
              file.deleteSync();
              Logger.debug('[OtaService] Deleted old package: ${file.path}');
            }
          }
        }
      }
    } catch (e) {
      Logger.error('[OtaService] Cleanup error: $e');
    }
  }

  /// Verify update package integrity
  /// [file] Update package file
  /// [expectedSha256] Expected SHA256 checksum
  Future<bool> verifyUpdate(File file, {String? expectedSha256}) async {
    if (expectedSha256 == null) {
      Logger.warning('[OtaService] No SHA256 provided, skipping verification');
      return true;
    }

    try {
      final bytes = await file.readAsBytes();
      final digest = await compute(_calculateSha256, bytes);
      
      if (digest == expectedSha256) {
        Logger.info('[OtaService] Package verification passed');
        return true;
      } else {
        Logger.error('[OtaService] Verification failed: $digest != $expectedSha256');
        return false;
      }
    } catch (e) {
      Logger.error('[OtaService] Verification error: $e');
      return false;
    }
  }

  /// Calculate SHA256 checksum (isolated function)
  static String _calculateSha256(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }
}
