/// Attachment model for file transfers
class Attachment {
  final String id;
  final String filename;
  final String mimeType;
  final int size;
  final String? data;      // Base64 encoded content (for sending)
  final String? filePath; // Local file path (for received files)
  final String? url;      // Download URL (for received files)

  Attachment({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.size,
    this.data,
    this.filePath,
    this.url,
  });

  /// Create from JSON
  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id'] ?? '',
      filename: json['filename'] ?? '',
      mimeType: json['mimeType'] ?? 'application/octet-stream',
      size: json['size'] ?? 0,
      data: json['data'],
      filePath: json['filePath'],
      url: json['url'],
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filename': filename,
      'mimeType': mimeType,
      'size': size,
      'data': data,
      'filePath': filePath,
      'url': url,
    };
  }

  /// Get file extension from filename
  String get extension {
    final parts = filename.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  /// Get human readable size
  String get sizeString {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Whether this is an image
  bool get isImage {
    return mimeType.startsWith('image/');
  }

  /// Whether this is a PDF
  bool get isPdf {
    return mimeType == 'application/pdf';
  }

  /// Whether this is a video
  bool get isVideo {
    return mimeType.startsWith('video/');
  }

  /// Whether this is audio
  bool get isAudio {
    return mimeType.startsWith('audio/');
  }

  /// Whether this is a text file
  bool get isText {
    return mimeType.startsWith('text/') || 
           filename.endsWith('.md') || 
           filename.endsWith('.txt') ||
           filename.endsWith('.json') ||
           filename.endsWith('.yaml') ||
           filename.endsWith('.yml') ||
           filename.endsWith('.dart') ||
           filename.endsWith('.py') ||
           filename.endsWith('.js') ||
           filename.endsWith('.ts');
  }

  /// Get icon name based on type
  String get iconName {
    if (isImage) return 'image';
    if (isPdf) return 'picture_as_pdf';
    if (isVideo) return 'videocam';
    if (isAudio) return 'audiotrack';
    if (filename.endsWith('.zip') || filename.endsWith('.rar') || filename.endsWith('.7z')) return 'archive';
    if (filename.endsWith('.doc') || filename.endsWith('.docx')) return 'description';
    if (filename.endsWith('.xls') || filename.endsWith('.xlsx')) return 'table_chart';
    if (filename.endsWith('.ppt') || filename.endsWith('.pptx')) return 'slideshow';
    return 'insert_drive_file';
  }
}
