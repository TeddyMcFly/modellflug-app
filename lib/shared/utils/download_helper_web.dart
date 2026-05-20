import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

@JS('showSaveFilePicker')
external JSPromise<JSAny> _showSaveFilePicker(JSObject options);

extension type _FileSystemFileHandle(JSObject _) implements JSObject {
  external JSPromise<_FileSystemWritableFileStream> createWritable();
}

extension type _FileSystemWritableFileStream(JSObject _) implements JSObject {
  external JSPromise<JSAny?> write(JSAny data);
  external JSPromise<JSAny?> close();
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
  web.URL.revokeObjectURL(url);
}

Future<bool> saveTextFile({
  required String fileName,
  required String content,
  required String mimeType,
}) async {
  try {
    final picker = globalContext.getProperty<JSAny?>(
      'showSaveFilePicker'.toJS,
    );
    if (picker == null || picker.isUndefinedOrNull) {
      return false;
    }

    final pickerMimeType = mimeType.split(';').first.trim();
    final options = {
      'suggestedName': fileName,
      'types': [
        {
          'description': 'Modellflug Sicherung',
          'accept': {
            pickerMimeType: ['.json'],
          },
        },
      ],
    }.jsify()! as JSObject;

    final blob = web.Blob(
      [content.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final handle = _FileSystemFileHandle(
      await _showSaveFilePicker(options).toDart as JSObject,
    );
    final writable = await handle.createWritable().toDart;

    await writable.write(blob).toDart;
    await writable.close().toDart;
    return true;
  } on Object {
    return false;
  }
}
