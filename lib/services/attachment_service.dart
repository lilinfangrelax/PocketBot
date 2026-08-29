import 'dart:async';
import 'package:pocket_bot/models/attachment.dart';
import 'package:pocket_bot/utils/logger.dart';

/// Service for handling file attachments
class AttachmentService {
  /// Maximum file size for Base64 encoding (5MB)
  static const int maxFileSize = 5 * 1024 * 1024;

  /// Allowed MIME types for file transfer
  static const List<String> allowedMimeTypes = [
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'text/plain',
    'text/markdown',
    'text/csv',
    'text/html',
    'text/css',
    'text/javascript',
    'application/javascript',
    'application/json',
    'application/xml',
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
    'image/svg+xml',
    'audio/mpeg',
    'audio/wav',
    'audio/ogg',
    'video/mp4',
    'video/mpeg',
    'video/webm',
    'application/zip',
    'application/x-rar-compressed',
    'application/x-7z-compressed',
  ];

  /// Pick files from device (currently disabled - no file picker)
  /// Returns empty list as file picker is not available
  static Future<List<Attachment>> pickFiles() async {
    Logger.info('File picker is not available in this version');
    return [];
  }

  /// Pick a single image (currently disabled)
  static Future<Attachment?> pickImage() async {
    Logger.info('File picker is not available in this version');
    return null;
  }

  /// Get file icon based on MIME type or extension
  static String getFileIcon(String filename) {
    final extension = filename.split('.').last.toLowerCase();
    
    final iconMap = {
      // Images
      'jpg': 'image',
      'jpeg': 'image',
      'png': 'image',
      'gif': 'image',
      'webp': 'image',
      'svg': 'image',
      // Documents
      'pdf': 'picture_as_pdf',
      'doc': 'description',
      'docx': 'description',
      'xls': 'table_chart',
      'xlsx': 'table_chart',
      'ppt': 'slideshow',
      'pptx': 'slideshow',
      'txt': 'article',
      'md': 'article',
      'csv': 'table_chart',
      // Code
      'json': 'code',
      'xml': 'code',
      'html': 'code',
      'css': 'code',
      'js': 'code',
      'ts': 'code',
      'dart': 'code',
      'py': 'code',
      // Archives
      'zip': 'archive',
      'rar': 'archive',
      '7z': 'archive',
      // Audio
      'mp3': 'audiotrack',
      'wav': 'audiotrack',
      'ogg': 'audiotrack',
      // Video
      'mp4': 'videocam',
      'mov': 'videocam',
      'avi': 'videocam',
      'webm': 'videocam',
    };
    
    return iconMap[extension] ?? 'insert_drive_file';
  }

  /// Convert bytes to human readable string
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
