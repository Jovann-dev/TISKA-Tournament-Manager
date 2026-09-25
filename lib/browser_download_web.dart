// ignore_for_file: deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

Future<void> downloadBytes({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) async {
  final blob = html.Blob(<Object>[bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  try {
    html.document.body?.append(anchor);
    anchor.click();
  } finally {
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  }
}
