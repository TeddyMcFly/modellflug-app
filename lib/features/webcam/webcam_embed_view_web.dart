import 'package:flutter/material.dart';

class WebcamEmbedView extends StatelessWidget {
  final String url;

  const WebcamEmbedView({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(url)?.host;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF0F172A)),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.link_rounded,
                color: Colors.white,
                size: 36,
              ),
              const SizedBox(height: 10),
              const Text(
                'Diese Webcam-Adresse ist eine Webseite.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (host != null && host.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  host,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                'Trage eine direkte Bild- oder Stream-Adresse ein, damit sie hier angezeigt wird.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
