import 'package:pocket_bot/models/contact.dart';
import 'package:test/test.dart';

void main() {
  group('Contact Model Tests', () {
    test('should create contact with isAI false by default', () {
      final now = DateTime.now();
      final contact = Contact(
        id: 'contact-1',
        name: 'John Doe',
        createdAt: now,
        updatedAt: now,
      );

      expect(contact.isAI, false);
    });

    test('should create contact with isAI true', () {
      final now = DateTime.now();
      final contact = Contact(
        id: 'contact-1',
        name: 'GPT Assistant',
        isAI: true,
        createdAt: now,
        updatedAt: now,
      );

      expect(contact.isAI, true);
    });

    test('should serialize isAI to JSON', () {
      final now = DateTime.now();
      final contact = Contact(
        id: 'contact-1',
        name: 'GPT Assistant',
        isAI: true,
        createdAt: now,
        updatedAt: now,
      );

      final json = contact.toJson();

      expect(json['isAI'], true);
    });

    test('should deserialize isAI from JSON', () {
      final json = {
        'id': 'contact-1',
        'name': 'GPT Assistant',
        'isAI': true,
        'createdAt': '2024-01-01T00:00:00.000',
        'updatedAt': '2024-01-01T00:00:00.000',
      };

      final contact = Contact.fromJson(json);

      expect(contact.isAI, true);
    });

    test('should default isAI to false when deserializing from JSON without isAI field', () {
      final json = {
        'id': 'contact-1',
        'name': 'John Doe',
        'createdAt': '2024-01-01T00:00:00.000',
        'updatedAt': '2024-01-01T00:00:00.000',
      };

      final contact = Contact.fromJson(json);

      expect(contact.isAI, false);
    });

    test('copyWith should preserve isAI value', () {
      final now = DateTime.now();
      final original = Contact(
        id: 'contact-1',
        name: 'GPT Assistant',
        isAI: true,
        createdAt: now,
        updatedAt: now,
      );

      final copied = original.copyWith(name: 'Updated Name');

      expect(copied.isAI, true);
      expect(copied.name, 'Updated Name');
    });

    test('copyWith should update isAI value', () {
      final now = DateTime.now();
      final original = Contact(
        id: 'contact-1',
        name: 'John Doe',
        isAI: false,
        createdAt: now,
        updatedAt: now,
      );

      final copied = original.copyWith(isAI: true);

      expect(copied.isAI, true);
      expect(copied.name, 'John Doe');
    });
  });
}
