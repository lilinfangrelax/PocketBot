import 'package:pocket_bot/models/attachment.dart';
import 'package:test/test.dart';

void main() {
  group('Attachment Model Tests', () {
    // Basic constructor tests
    test('Create attachment with all fields', () {
      final attachment = Attachment(
        id: 'att-123',
        filename: 'document.pdf',
        mimeType: 'application/pdf',
        size: 1024000,
        data: 'base64data',
        filePath: '/path/to/file',
        url: 'https://example.com/file.pdf',
      );

      expect(attachment.id, 'att-123');
      expect(attachment.filename, 'document.pdf');
      expect(attachment.mimeType, 'application/pdf');
      expect(attachment.size, 1024000);
      expect(attachment.data, 'base64data');
      expect(attachment.filePath, '/path/to/file');
      expect(attachment.url, 'https://example.com/file.pdf');
    });

    test('Create attachment with optional fields', () {
      final attachment = Attachment(
        id: 'att-456',
        filename: 'image.png',
        mimeType: 'image/png',
        size: 204800,
      );

      expect(attachment.id, 'att-456');
      expect(attachment.filename, 'image.png');
      expect(attachment.mimeType, 'image/png');
      expect(attachment.size, 204800);
      expect(attachment.data, isNull);
      expect(attachment.filePath, isNull);
      expect(attachment.url, isNull);
    });

    // JSON serialization tests
    test('Attachment to JSON', () {
      final attachment = Attachment(
        id: 'att-789',
        filename: 'test.txt',
        mimeType: 'text/plain',
        size: 100,
        data: 'encoded',
        filePath: '/local/path',
        url: 'https://remote.url',
      );

      final json = attachment.toJson();

      expect(json['id'], 'att-789');
      expect(json['filename'], 'test.txt');
      expect(json['mimeType'], 'text/plain');
      expect(json['size'], 100);
      expect(json['data'], 'encoded');
      expect(json['filePath'], '/local/path');
      expect(json['url'], 'https://remote.url');
    });

    test('Attachment from JSON', () {
      final json = <String, dynamic>{
        'id': 'att-json-1',
        'filename': 'report.pdf',
        'mimeType': 'application/pdf',
        'size': 500000,
        'data': null,
        'filePath': null,
        'url': 'https://example.com/report.pdf',
      };

      final attachment = Attachment.fromJson(json);

      expect(attachment.id, 'att-json-1');
      expect(attachment.filename, 'report.pdf');
      expect(attachment.mimeType, 'application/pdf');
      expect(attachment.size, 500000);
    });

    test('Attachment from JSON with null fields', () {
      final json = <String, dynamic>{};

      final attachment = Attachment.fromJson(json);

      expect(attachment.id, '');
      expect(attachment.filename, '');
      expect(attachment.mimeType, 'application/octet-stream');
      expect(attachment.size, 0);
    });

    test('Attachment round-trip serialization', () {
      final original = Attachment(
        id: 'roundtrip',
        filename: 'photo.jpg',
        mimeType: 'image/jpeg',
        size: 1500000,
        data: 'somedata',
      );

      final json = original.toJson();
      final restored = Attachment.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.filename, original.filename);
      expect(restored.mimeType, original.mimeType);
      expect(restored.size, original.size);
      expect(restored.data, original.data);
    });

    // File extension tests
    test('Get extension from filename', () {
      final attachment = Attachment(
        id: 'ext-test',
        filename: 'document.pdf',
        mimeType: 'application/pdf',
        size: 100,
      );

      expect(attachment.extension, 'pdf');
    });

    test('Extension is lowercase', () {
      final attachment = Attachment(
        id: 'case-test',
        filename: 'image.PNG',
        mimeType: 'image/png',
        size: 100,
      );

      expect(attachment.extension, 'png');
    });

    test('Empty filename returns empty extension', () {
      final attachment = Attachment(
        id: 'empty-test',
        filename: '',
        mimeType: 'text/plain',
        size: 0,
      );

      expect(attachment.extension, '');
    });

    test('Filename without extension returns empty string', () {
      final attachment = Attachment(
        id: 'noext-test',
        filename: 'README',
        mimeType: 'text/plain',
        size: 100,
      );

      expect(attachment.extension, '');
    });

    // File size formatting tests
    test('Bytes format', () {
      final attachment = Attachment(
        id: 'size-test',
        filename: 'small.txt',
        mimeType: 'text/plain',
        size: 500,
      );

      expect(attachment.sizeString, '500 B');
    });

    test('Kilobytes format', () {
      final attachment = Attachment(
        id: 'kb-test',
        filename: 'medium.txt',
        mimeType: 'text/plain',
        size: 2048,
      );

      expect(attachment.sizeString, '2.0 KB');
    });

    test('Megabytes format', () {
      final attachment = Attachment(
        id: 'mb-test',
        filename: 'large.pdf',
        mimeType: 'application/pdf',
        size: 5 * 1024 * 1024,
      );

      expect(attachment.sizeString, '5.0 MB');
    });

    // File type detection tests
    test('isImage detects image types', () {
      expect(
        Attachment(id: '1', filename: 'test.jpg', mimeType: 'image/jpeg', size: 100).isImage,
        true,
      );
      expect(
        Attachment(id: '2', filename: 'test.png', mimeType: 'image/png', size: 100).isImage,
        true,
      );
      expect(
        Attachment(id: '3', filename: 'test.gif', mimeType: 'image/gif', size: 100).isImage,
        true,
      );
    });

    test('isImage rejects non-image types', () {
      expect(
        Attachment(id: '1', filename: 'test.pdf', mimeType: 'application/pdf', size: 100).isImage,
        false,
      );
      expect(
        Attachment(id: '2', filename: 'test.txt', mimeType: 'text/plain', size: 100).isImage,
        false,
      );
    });

    test('isPdf detects PDF files', () {
      expect(
        Attachment(id: '1', filename: 'doc.pdf', mimeType: 'application/pdf', size: 100).isPdf,
        true,
      );
      expect(
        Attachment(id: '2', filename: 'doc.txt', mimeType: 'text/plain', size: 100).isPdf,
        false,
      );
    });

    test('isVideo detects video types', () {
      expect(
        Attachment(id: '1', filename: 'video.mp4', mimeType: 'video/mp4', size: 100).isVideo,
        true,
      );
      expect(
        Attachment(id: '2', filename: 'video.webm', mimeType: 'video/webm', size: 100).isVideo,
        true,
      );
    });

    test('isAudio detects audio types', () {
      expect(
        Attachment(id: '1', filename: 'song.mp3', mimeType: 'audio/mpeg', size: 100).isAudio,
        true,
      );
      expect(
        Attachment(id: '2', filename: 'sound.wav', mimeType: 'audio/wav', size: 100).isAudio,
        true,
      );
    });

    test('isText detects text files by MIME type', () {
      expect(
        Attachment(id: '1', filename: 'file.txt', mimeType: 'text/plain', size: 100).isText,
        true,
      );
      expect(
        Attachment(id: '2', filename: 'file.html', mimeType: 'text/html', size: 100).isText,
        true,
      );
    });

    test('isText detects text files by extension', () {
      expect(
        Attachment(id: '1', filename: 'readme.md', mimeType: 'application/octet-stream', size: 100).isText,
        true,
      );
      expect(
        Attachment(id: '2', filename: 'script.dart', mimeType: 'application/octet-stream', size: 100).isText,
        true,
      );
      expect(
        Attachment(id: '3', filename: 'config.json', mimeType: 'application/octet-stream', size: 100).isText,
        true,
      );
      expect(
        Attachment(id: '4', filename: 'data.yaml', mimeType: 'application/octet-stream', size: 100).isText,
        true,
      );
      expect(
        Attachment(id: '5', filename: 'script.py', mimeType: 'application/octet-stream', size: 100).isText,
        true,
      );
    });

    // Icon name tests
    test('Icon for image files', () {
      expect(
        Attachment(id: '1', filename: 'photo.jpg', mimeType: 'image/jpeg', size: 100).iconName,
        'image',
      );
      expect(
        Attachment(id: '2', filename: 'image.png', mimeType: 'image/png', size: 100).iconName,
        'image',
      );
    });

    test('Icon for PDF files', () {
      expect(
        Attachment(id: '1', filename: 'document.pdf', mimeType: 'application/pdf', size: 100).iconName,
        'picture_as_pdf',
      );
    });

    test('Icon for video files', () {
      expect(
        Attachment(id: '1', filename: 'video.mp4', mimeType: 'video/mp4', size: 100).iconName,
        'videocam',
      );
    });

    test('Icon for audio files', () {
      expect(
        Attachment(id: '1', filename: 'song.mp3', mimeType: 'audio/mpeg', size: 100).iconName,
        'audiotrack',
      );
    });

    test('Icon for archive files', () {
      expect(
        Attachment(id: '1', filename: 'archive.zip', mimeType: 'application/zip', size: 100).iconName,
        'archive',
      );
      expect(
        Attachment(id: '2', filename: 'backup.rar', mimeType: 'application/x-rar-compressed', size: 100).iconName,
        'archive',
      );
      expect(
        Attachment(id: '3', filename: 'compressed.7z', mimeType: 'application/x-7z-compressed', size: 100).iconName,
        'archive',
      );
    });

    test('Icon for document files', () {
      expect(
        Attachment(id: '1', filename: 'document.doc', mimeType: 'application/msword', size: 100).iconName,
        'description',
      );
      expect(
        Attachment(id: '2', filename: 'document.docx', mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', size: 100).iconName,
        'description',
      );
    });

    test('Icon for spreadsheet files', () {
      expect(
        Attachment(id: '1', filename: 'data.xls', mimeType: 'application/vnd.ms-excel', size: 100).iconName,
        'table_chart',
      );
      expect(
        Attachment(id: '2', filename: 'data.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', size: 100).iconName,
        'table_chart',
      );
    });

    test('Icon for presentation files', () {
      expect(
        Attachment(id: '1', filename: 'slides.ppt', mimeType: 'application/vnd.ms-powerpoint', size: 100).iconName,
        'slideshow',
      );
      expect(
        Attachment(id: '2', filename: 'slides.pptx', mimeType: 'application/vnd.openxmlformats-officedocument.presentationml.presentation', size: 100).iconName,
        'slideshow',
      );
    });

    test('Icon for unknown files defaults to insert_drive_file', () {
      expect(
        Attachment(id: '1', filename: 'unknown.xyz', mimeType: 'application/octet-stream', size: 100).iconName,
        'insert_drive_file',
      );
    });
  });
}
