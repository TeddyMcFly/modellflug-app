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
}) {
  throw UnsupportedError('Browser save dialog is only available on web.');
}
