import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class WebcamEmbedView extends StatelessWidget {
  final String url;
  final int refreshSerial;

  const WebcamEmbedView({
    super.key,
    required this.url,
    required this.refreshSerial,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF0F172A)),
      child: HtmlElementView(
        viewType: _registerWebcamEmbed(url, refreshSerial),
      ),
    );
  }
}

final _registeredViewTypes = <String>{};

String _registerWebcamEmbed(String url, int refreshSerial) {
  final viewType = 'modellflug-webcam-embed-${Object.hash(url, refreshSerial)}';
  if (_registeredViewTypes.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (_) {
      return web.HTMLIFrameElement()
        ..src = url
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = '0'
        ..style.display = 'block'
        ..style.backgroundColor = '#0F172A'
        ..allow =
            'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share; fullscreen'
        ..referrerPolicy = 'strict-origin-when-cross-origin'
        ..setAttribute('allowfullscreen', 'true');
    });
  }
  return viewType;
}
