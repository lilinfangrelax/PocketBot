import 'dart:convert';
import 'dart:typed_data';

/// DNS PTR query for [ipv4], sent to Tailscale MagicDNS.
Uint8List encodeDnsPtrQuery({required int id, required String ipv4}) {
  final octets = ipv4.split('.');
  if (octets.length != 4 || id < 0 || id > 0xffff) {
    throw FormatException('Invalid PTR query', ipv4);
  }
  final labels = [...octets.reversed, 'in-addr', 'arpa'];
  final name = BytesBuilder(copy: false);
  for (final label in labels) {
    final bytes = ascii.encode(label);
    if (bytes.isEmpty || bytes.length > 63) {
      throw FormatException('Invalid PTR label', label);
    }
    name.addByte(bytes.length);
    name.add(bytes);
  }
  name.addByte(0);
  final encodedName = name.toBytes();
  final packet = Uint8List(12 + encodedName.length + 4);
  packet[0] = id >> 8;
  packet[1] = id & 0xff;
  packet[2] = 0x01;
  packet[5] = 1;
  packet.setRange(12, 12 + encodedName.length, encodedName);
  final typeAt = 12 + encodedName.length;
  packet[typeAt + 1] = 12;
  packet[typeAt + 3] = 1;
  return packet;
}

Uint8List frameDnsTcp(Uint8List message) {
  if (message.length > 0xffff) {
    throw const FormatException('DNS message is too long');
  }
  final framed = Uint8List(message.length + 2);
  framed[0] = message.length >> 8;
  framed[1] = message.length & 0xff;
  framed.setRange(2, framed.length, message);
  return framed;
}

/// The first PTR name in a DNS response, or null when the packet is unusable.
String? ptrNameFromDnsResponse(Uint8List packet, {required int queryId}) {
  if (packet.length < 12 || queryId < 0 || queryId > 0xffff) return null;
  final id = (packet[0] << 8) | packet[1];
  if (id != queryId) return null;
  final flags = (packet[2] << 8) | packet[3];
  final response = (flags >> 15) & 1;
  final rcode = flags & 0x0f;
  if (response != 1 || rcode != 0) return null;
  final questions = (packet[4] << 8) | packet[5];
  final answers = (packet[6] << 8) | packet[7];
  var offset = 12;
  for (var i = 0; i < questions; i++) {
    final skipped = _skipName(packet, offset);
    if (skipped == null || skipped + 4 > packet.length) return null;
    offset = skipped + 4;
  }
  for (var i = 0; i < answers; i++) {
    final skipped = _skipName(packet, offset);
    if (skipped == null || skipped + 10 > packet.length) return null;
    offset = skipped;
    final type = (packet[offset] << 8) | packet[offset + 1];
    final length = (packet[offset + 8] << 8) | packet[offset + 9];
    offset += 10;
    if (length < 0 || offset + length > packet.length) return null;
    if (type == 12) {
      final name = _readName(packet, offset);
      if (name != null && name.isNotEmpty) return name;
    }
    offset += length;
  }
  return null;
}

int? _skipName(Uint8List packet, int offset) {
  final end = _walkName(packet, offset, []);
  return end?.offset;
}

String? _readName(Uint8List packet, int offset) {
  final labels = <String>[];
  final end = _walkName(packet, offset, labels);
  if (end == null) return null;
  return labels.join('.');
}

class _NameEnd {
  const _NameEnd(this.offset);
  final int offset;
}

_NameEnd? _walkName(Uint8List packet, int offset, List<String> labels) {
  var cursor = offset;
  var jumps = 0;
  var end = offset;
  var jumped = false;
  while (cursor < packet.length && jumps < 16) {
    final length = packet[cursor];
    if (length == 0) {
      if (!jumped) end = cursor + 1;
      return _NameEnd(end);
    }
    if ((length & 0xc0) == 0xc0) {
      if (cursor + 1 >= packet.length) return null;
      final pointer = ((length & 0x3f) << 8) | packet[cursor + 1];
      if (pointer >= packet.length) return null;
      if (!jumped) end = cursor + 2;
      jumped = true;
      jumps++;
      cursor = pointer;
      continue;
    }
    if ((length & 0xc0) != 0) return null;
    final start = cursor + 1;
    final stop = start + length;
    if (stop > packet.length) return null;
    labels.add(ascii.decode(packet.sublist(start, stop), allowInvalid: true));
    cursor = stop;
    if (!jumped) end = cursor;
  }
  return null;
}
