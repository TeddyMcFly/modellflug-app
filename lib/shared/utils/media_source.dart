import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

bool isNetworkMediaSource(String source) {
  return source.startsWith('https://') || source.startsWith('http://');
}

bool isImageMediaSource(String source) {
  final lower = source.toLowerCase();
  return lower.startsWith('data:image/') ||
      lower.contains('.jpg') ||
      lower.contains('.jpeg') ||
      lower.contains('.png') ||
      lower.contains('.webp') ||
      lower.contains('.gif');
}

ImageProvider<Object>? maybeMediaImageProvider(String? source) {
  if (source == null || source.isEmpty) {
    return null;
  }
  return mediaImageProvider(source);
}

ImageProvider<Object> mediaImageProvider(String source) {
  if (isNetworkMediaSource(source)) {
    return NetworkImage(source);
  }
  return MemoryImage(bytesFromDataUri(source));
}

ImageProvider<Object> browserVisibleMediaImageProvider(String source) {
  return mediaImageProvider(source);
}

Uint8List bytesFromDataUri(String dataUri) {
  final commaIndex = dataUri.indexOf(',');
  final encoded =
      commaIndex == -1 ? dataUri : dataUri.substring(commaIndex + 1);
  return base64Decode(encoded);
}
