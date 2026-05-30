import 'dart:async';

import 'package:flutter/material.dart';

OverlayEntry? _centeredNoticeEntry;
Timer? _centeredNoticeTimer;

void showCenteredSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  if (!context.mounted) {
    return;
  }

  ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
  _centeredNoticeTimer?.cancel();
  if (_centeredNoticeEntry?.mounted ?? false) {
    _centeredNoticeEntry?.remove();
  }

  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
    _centeredNoticeEntry = null;
    return;
  }

  final entry = OverlayEntry(
    builder: (context) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;

      return Positioned.fill(
        child: IgnorePointer(
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Material(
                  color: Colors.transparent,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.inverseSurface,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 22,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 16,
                        ),
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onInverseSurface,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  _centeredNoticeEntry = entry;
  overlay.insert(entry);
  _centeredNoticeTimer = Timer(duration, () {
    if (_centeredNoticeEntry == entry) {
      if (entry.mounted) {
        entry.remove();
      }
      _centeredNoticeEntry = null;
    }
  });
}
