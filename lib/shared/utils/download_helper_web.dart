import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

@JS('showSaveFilePicker')
external JSPromise<JSAny> _showSaveFilePicker(JSObject options);

extension type _FileSystemFileHandle(JSObject _) implements JSObject {
  external JSPromise<_FileSystemWritableFileStream> createWritable();
  external JSPromise<web.File> getFile();
}

extension type _FileSystemWritableFileStream(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSAny data);
  external JSPromise<JSAny?> close();
}

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
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
}

void downloadTextFile({
  required String fileName,
  required String content,
  required String mimeType,
}) {
  final blob = web.Blob(
    [content.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
}

Future<bool> saveTextFile({
  required String fileName,
  required String content,
  required String mimeType,
  List<String> allowedExtensions = const ['json'],
  String description = 'Modellflug Datei',
}) async {
  return await saveTextFileResult(
        fileName: fileName,
        content: content,
        mimeType: mimeType,
        allowedExtensions: allowedExtensions,
        description: description,
      ) ==
      SaveFileResult.saved;
}

Future<SaveFileResult> saveTextFileResult({
  required String fileName,
  required String content,
  required String mimeType,
  List<String> allowedExtensions = const ['json'],
  String description = 'Modellflug Datei',
}) {
  return saveBytesFileResult(
    fileName: fileName,
    bytes: Uint8List.fromList(utf8.encode(content)),
    mimeType: mimeType,
    allowedExtensions: allowedExtensions,
    description: description,
  );
}

Future<bool> saveBytesFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
  List<String> allowedExtensions = const ['pdf'],
  String description = 'Modellflug Datei',
}) async {
  return await saveBytesFileResult(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
        allowedExtensions: allowedExtensions,
        description: description,
      ) ==
      SaveFileResult.saved;
}

Future<SaveFileResult> saveBytesFileResult({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
  List<String> allowedExtensions = const ['pdf'],
  String description = 'Modellflug Datei',
}) async {
  try {
    final picker = globalContext.getProperty<JSAny?>(
      'showSaveFilePicker'.toJS,
    );
    if (picker == null || picker.isUndefinedOrNull) {
      return SaveFileResult.unavailable;
    }

    final pickerMimeType = mimeType.split(';').first.trim();
    final options = {
      'suggestedName': fileName,
      'types': [
        {
          'description': description,
          'accept': {
            pickerMimeType: [
              for (final extension in allowedExtensions) '.$extension',
            ],
          },
        },
      ],
    }.jsify()! as JSObject;

    final blob = web.Blob(
      <JSUint8Array>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final handle = _FileSystemFileHandle(
      await _showSaveFilePicker(options).toDart as JSObject,
    );
    final writable = await handle.createWritable().toDart;

    await writable.write(blob).toDart;
    await writable.close().toDart;
    final writtenFile = await handle.getFile().toDart;
    if (bytes.isNotEmpty && writtenFile.size == 0) {
      return SaveFileResult.failed;
    }
    return SaveFileResult.saved;
  } on Object catch (error) {
    return _isUserCancelledSave(error)
        ? SaveFileResult.cancelled
        : SaveFileResult.failed;
  }
}

bool _isUserCancelledSave(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('abort') || message.contains('cancel');
}
