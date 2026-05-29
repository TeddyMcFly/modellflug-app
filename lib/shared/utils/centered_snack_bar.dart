import 'package:flutter/material.dart';

void showCenteredSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  final size = MediaQuery.maybeSizeOf(context) ?? const Size(360, 640);
  final horizontalMargin = size.width > 620 ? (size.width - 560) / 2 : 16.0;
  final bottomMargin = size.height > 360 ? size.height * 0.42 : 24.0;
  final messenger = ScaffoldMessenger.of(context);

  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: duration,
        margin: EdgeInsets.only(
          left: horizontalMargin,
          right: horizontalMargin,
          bottom: bottomMargin,
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
        ),
      ),
    );
}
