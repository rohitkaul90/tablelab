import 'dart:typed_data';

/// Non-web stand-in — never called (callers gate on `kIsWeb`).
void downloadBytesWeb(Uint8List bytes, String fileName, String mimeType) {
  throw UnsupportedError('downloadBytesWeb is only available on web builds.');
}
