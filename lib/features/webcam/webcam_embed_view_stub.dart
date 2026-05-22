import 'package:flutter/material.dart';

class WebcamEmbedView extends StatelessWidget {
  final String url;

  const WebcamEmbedView({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xFF0F172A)),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Diese Webcam-Adresse ist eine Webseite. Trage eine direkte Bild- oder Stream-Adresse ein, damit sie hier angezeigt wird.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
