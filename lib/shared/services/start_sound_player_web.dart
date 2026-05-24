import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class StartSoundPlayer {
  StartSoundPlayer(this.assetPath);

  final String assetPath;

  web.HTMLAudioElement? _audio;
  Timer? _fadeTimer;
  bool _disposed = false;
  bool _started = false;

  Future<bool> play() async {
    if (_disposed || _started) {
      return false;
    }
    _started = true;

    final audio = web.HTMLAudioElement()
      ..src = _webAssetUrl(assetPath)
      ..preload = 'auto'
      ..loop = false
      ..volume = 1;
    _audio = audio;

    try {
      await audio.play().toDart;
      return true;
    } catch (_) {
      // Browser koennen Autoplay mit Ton blockieren. Dann bleibt der Start
      // schlicht stumm, statt die App zu stoeren.
      _started = false;
      _audio = null;
      return false;
    }
  }

  Future<void> fadeOut({
    Duration duration = const Duration(milliseconds: 800),
  }) async {
    final audio = _audio;
    if (audio == null) {
      return;
    }

    _fadeTimer?.cancel();

    if (duration.inMilliseconds <= 0 || audio.paused) {
      _stop(audio);
      return;
    }

    final completer = Completer<void>();
    const steps = 18;
    final startVolume = audio.volume.clamp(0, 1).toDouble();
    final interval = Duration(
      milliseconds: (duration.inMilliseconds / steps).round().clamp(16, 1000),
    );
    var step = 0;

    _fadeTimer = Timer.periodic(interval, (timer) {
      step += 1;
      final factor = (1 - step / steps).clamp(0, 1).toDouble();
      audio.volume = startVolume * factor;

      if (step >= steps) {
        timer.cancel();
        _fadeTimer = null;
        _stop(audio);
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });

    return completer.future;
  }

  void dispose() {
    _disposed = true;
    _fadeTimer?.cancel();
    final audio = _audio;
    if (audio != null) {
      _stop(audio);
    }
    _audio = null;
  }

  void _stop(web.HTMLAudioElement audio) {
    audio.pause();
    audio.volume = 0;
    try {
      audio.currentTime = 0;
    } catch (_) {
      // Manche Browser erlauben currentTime erst nach geladenen Metadaten.
    }
  }
}

String _webAssetUrl(String assetPath) {
  final normalized =
      assetPath.startsWith('/') ? assetPath.substring(1) : assetPath;
  return Uri.base.resolve('assets/$normalized').toString();
}
