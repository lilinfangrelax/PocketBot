import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pocket_bot/services/attachment_service.dart';

void main() {
  // 1x1 transparent PNG.
  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
    'z8BQDwAFgwJ/lY2mAAAAAElFTkSuQmCC',
  );

  group('attachmentFromXFile', () {
    test('encodes image bytes and detects the mime type', () async {
      final attachment = await AttachmentService.attachmentFromXFile(
        XFile.fromData(pngBytes, path: 'photo.png'),
      );

      expect(attachment.filename, 'photo.png');
      expect(attachment.mimeType, 'image/png');
      expect(attachment.size, pngBytes.length);
      expect(attachment.data, base64Encode(pngBytes));
      expect(attachment.isImage, isTrue);
      expect(attachment.id, isNotEmpty);
    });

    test('prefers the mime type reported by the picker', () async {
      final attachment = await AttachmentService.attachmentFromXFile(
        XFile.fromData(pngBytes, path: 'photo.bin', mimeType: 'image/png'),
      );

      expect(attachment.mimeType, 'image/png');
    });

    test('rejects empty files', () async {
      await expectLater(
        AttachmentService.attachmentFromXFile(
          XFile.fromData(Uint8List(0), path: 'empty.png'),
        ),
        throwsA(isA<AttachmentException>().having(
          (error) => error.message,
          'message',
          '图片内容为空',
        )),
      );
    });

    test('rejects non-image files', () async {
      await expectLater(
        AttachmentService.attachmentFromXFile(
          XFile.fromData(
            Uint8List.fromList(utf8.encode('hello')),
            path: 'notes.txt',
            mimeType: 'text/plain',
          ),
        ),
        throwsA(isA<AttachmentException>().having(
          (error) => error.message,
          'message',
          '只能发送图片附件',
        )),
      );
    });

    test('rejects files beyond the base64 size limit', () async {
      await expectLater(
        AttachmentService.attachmentFromXFile(
          XFile.fromData(
            Uint8List(AttachmentService.maxFileSize + 1),
            path: 'huge.png',
            mimeType: 'image/png',
          ),
        ),
        throwsA(isA<AttachmentException>().having(
          (error) => error.message,
          'message',
          '图片不能超过 5MB',
        )),
      );
    });
  });
}
