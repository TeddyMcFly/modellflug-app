import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

String? createImageThumbnailDataUri(
  Uint8List bytes, {
  int maxSize = 96,
  int quality = 72,
}) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return null;
    }

    final oriented = img.bakeOrientation(decoded);
    final targetWidth = oriented.width >= oriented.height ? maxSize : null;
    final targetHeight = oriented.height > oriented.width ? maxSize : null;
    final resized = img.copyResize(
      oriented,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.average,
    );
    final encoded = img.encodeJpg(resized, quality: quality);
    return 'data:image/jpeg;base64,${base64Encode(encoded)}';
  } catch (_) {
    return null;
  }
}

String? createImageThumbnailDataUriFromDataUri(
  String dataUri, {
  int maxSize = 96,
  int quality = 72,
}) {
  final commaIndex = dataUri.indexOf(',');
  final encoded =
      commaIndex == -1 ? dataUri : dataUri.substring(commaIndex + 1);
  try {
    return createImageThumbnailDataUri(
      base64Decode(encoded),
      maxSize: maxSize,
      quality: quality,
    );
  } catch (_) {
    return null;
  }
}
