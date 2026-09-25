import 'dart:typed_data';

Future<void> downloadBytes({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) {
  throw UnsupportedError('Browser downloads are only available on web.');
}
