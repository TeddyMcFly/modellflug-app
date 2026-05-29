import 'dart:typed_data';

enum SaveFileResult {
  saved,
  cancelled,
  unavailable,
  failed,
}

void downloadBytesFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) {
  throw UnsupportedError('Direct browser download is only available on web.');
}

void downloadTextFile({
  required String fileName,
  required String content,
  required String mimeType,
}) {
  throw UnsupportedError('Direct browser download is only available on web.');
}

Future<bool> saveTextFile({
  required String fileName,
  required String content,
  required String mimeType,
  List<String> allowedExtensions = const ['json'],
  String description = 'Modellflug Datei',
}) {
  throw UnsupportedError('Browser save dialog is only available on web.');
}

Future<SaveFileResult> saveTextFileResult({
  required String fileName,
  required String content,
  required String mimeType,
  List<String> allowedExtensions = const ['json'],
  String description = 'Modellflug Datei',
}) {
  throw UnsupportedError('Browser save dialog is only available on web.');
}

Future<bool> saveBytesFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
  List<String> allowedExtensions = const ['pdf'],
  String description = 'Modellflug Datei',
}) {
  throw UnsupportedError('Browser save dialog is only available on web.');
}

Future<SaveFileResult> saveBytesFileResult({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
  List<String> allowedExtensions = const ['pdf'],
  String description = 'Modellflug Datei',
}) {
  throw UnsupportedError('Browser save dialog is only available on web.');
}
