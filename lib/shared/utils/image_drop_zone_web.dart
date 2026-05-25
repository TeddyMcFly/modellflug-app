import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class DroppedImageFile {
  final String name;
  final Uint8List bytes;

  const DroppedImageFile({
    required this.name,
    required this.bytes,
  });
}

class ImageDropZone extends StatefulWidget {
  final Widget child;
  final ValueChanged<DroppedImageFile> onImageDropped;
  final ValueChanged<bool>? onDragActiveChanged;

  const ImageDropZone({
    super.key,
    required this.child,
    required this.onImageDropped,
    this.onDragActiveChanged,
  });

  @override
  State<ImageDropZone> createState() => _ImageDropZoneState();
}

class _ImageDropZoneState extends State<ImageDropZone> {
  static int _nextId = 0;

  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'modellflug-image-drop-zone-${_nextId++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final element = web.HTMLDivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'block'
        ..style.backgroundColor = 'rgba(0, 0, 0, 0)'
        ..style.cursor = 'copy';

      void setActive(bool active) {
        widget.onDragActiveChanged?.call(active);
      }

      void handleDrag(web.Event event) {
        event.preventDefault();
        event.stopPropagation();
        final dragEvent = event as web.DragEvent;
        dragEvent.dataTransfer?.dropEffect = 'copy';
        setActive(true);
      }

      void handleLeave(web.Event event) {
        event.preventDefault();
        event.stopPropagation();
        setActive(false);
      }

      void handleDrop(web.Event event) {
        event.preventDefault();
        event.stopPropagation();
        setActive(false);
        unawaited(_readDroppedImage(event));
      }

      element.addEventListener('dragenter', handleDrag.toJS);
      element.addEventListener('dragover', handleDrag.toJS);
      element.addEventListener('dragleave', handleLeave.toJS);
      element.addEventListener('drop', handleDrop.toJS);

      return element;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        HtmlElementView(viewType: _viewType),
      ],
    );
  }

  Future<void> _readDroppedImage(web.Event event) async {
    final dragEvent = event as web.DragEvent;
    final files = dragEvent.dataTransfer?.files;
    if (files == null || files.length == 0) {
      return;
    }

    web.File? selectedFile;
    for (var index = 0; index < files.length; index++) {
      final file = files.item(index);
      if (file == null) {
        continue;
      }
      if (_isImageFile(file)) {
        selectedFile = file;
        break;
      }
    }

    if (selectedFile == null) {
      return;
    }

    final buffer = await selectedFile.arrayBuffer().toDart;
    if (!mounted) {
      return;
    }
    widget.onImageDropped(
      DroppedImageFile(
        name: selectedFile.name,
        bytes: buffer.toDart.asUint8List(),
      ),
    );
  }

  bool _isImageFile(web.File file) {
    final type = file.type.toLowerCase();
    if (type.startsWith('image/')) {
      return true;
    }
    final name = file.name.toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif');
  }
}
