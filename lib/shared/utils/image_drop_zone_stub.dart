import 'dart:typed_data';

import 'package:flutter/material.dart';

class DroppedImageFile {
  final String name;
  final Uint8List bytes;

  const DroppedImageFile({
    required this.name,
    required this.bytes,
  });
}

class ImageDropZone extends StatelessWidget {
  final Widget child;
  final ValueChanged<DroppedImageFile> onImageDropped;
  final ValueChanged<List<DroppedImageFile>>? onImagesDropped;
  final ValueChanged<bool>? onDragActiveChanged;

  const ImageDropZone({
    super.key,
    required this.child,
    required this.onImageDropped,
    this.onImagesDropped,
    this.onDragActiveChanged,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
