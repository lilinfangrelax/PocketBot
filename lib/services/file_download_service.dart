import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pocket_bot/models/attachment.dart';
import 'package:pocket_bot/utils/logger.dart';

/// Service for downloading and opening files
class FileDownloadService {
  /// Download directory
  static Future<Directory> getDownloadDirectory() async {
    if (kIsWeb) {
      // For web, we can't access filesystem directly
      throw Exception('File download not supported on web');
    }

    // Try to get external storage directory first (Android)
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (status.isGranted) {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          // Create the PocketBot download folder.
          final downloadDir =
              Directory('${externalDir.path}/Download/PocketBot');
          if (!await downloadDir.exists()) {
            await downloadDir.create(recursive: true);
          }
          return downloadDir;
        }
      }
    }

    // Fallback to documents directory
    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/Downloads');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir;
  }

  /// Download a file from URL and save to local storage
  static Future<String?> downloadFile(Attachment attachment) async {
    try {
      final url = attachment.url;
      if (url == null || url.isEmpty) {
        Logger.warning(
            'No URL provided for attachment: ${attachment.filename}');
        return null;
      }

      Logger.info('Downloading file: ${attachment.filename} from $url');

      // For data URLs (Base64), decode and save directly
      if (url.startsWith('data:')) {
        return await _saveBase64Data(attachment);
      }

      // For HTTP URLs, download using http client
      final uri = Uri.parse(url);
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        Logger.error('Download failed: HTTP ${response.statusCode}');
        return null;
      }

      // Get download directory
      final downloadDir = await getDownloadDirectory();
      final filePath = '${downloadDir.path}/${attachment.filename}';
      final file = File(filePath);

      // Write to file
      await response.pipe(file.openWrite());
      httpClient.close();

      Logger.info('File saved to: $filePath');
      return filePath;
    } catch (e) {
      Logger.error('Error downloading file: $e');
      return null;
    }
  }

  /// Save Base64 data to file
  static Future<String?> _saveBase64Data(Attachment attachment) async {
    final data = attachment.data;
    if (data == null || data.isEmpty) {
      Logger.warning('No data provided for attachment: ${attachment.filename}');
      return null;
    }

    try {
      final downloadDir = await getDownloadDirectory();
      final filePath = '${downloadDir.path}/${attachment.filename}';
      final file = File(filePath);

      final bytes = base64Decode(data);
      await file.writeAsBytes(bytes);

      Logger.info('Base64 file saved to: $filePath');
      return filePath;
    } catch (e) {
      Logger.error('Error saving Base64 file: $e');
      return null;
    }
  }

  /// Open a file with the default app
  static Future<bool> openFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        Logger.error('File not found: $filePath');
        return false;
      }

      final uri = Uri.file(filePath);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return true;
      } else {
        Logger.error('No app found to open file: $filePath');
        return false;
      }
    } catch (e) {
      Logger.error('Error opening file: $e');
      return false;
    }
  }

  /// Download and open a file
  static Future<bool> downloadAndOpen(Attachment attachment) async {
    final filePath = await downloadFile(attachment);
    if (filePath == null) {
      return false;
    }
    return await openFile(filePath);
  }

  /// Share a file
  static Future<bool> shareFile(String filePath, {String? subject}) async {
    try {
      final uri = Uri.file(filePath);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('Error sharing file: $e');
      return false;
    }
  }

  /// Get file info
  static Future<FileInfo?> getFileInfo(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      final stat = await file.stat();
      return FileInfo(
        path: filePath,
        name: file.path.split(Platform.pathSeparator).last,
        size: stat.size,
        modified: stat.modified,
      );
    } catch (e) {
      Logger.error('Error getting file info: $e');
      return null;
    }
  }

  /// Delete a downloaded file
  static Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        Logger.info('File deleted: $filePath');
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('Error deleting file: $e');
      return false;
    }
  }
}

/// File information model
class FileInfo {
  final String path;
  final String name;
  final int size;
  final DateTime modified;

  FileInfo({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  String get sizeString {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
