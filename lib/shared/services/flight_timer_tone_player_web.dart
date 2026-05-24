import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class FlightTimerTonePlayer {
  web.AudioContext? _context;
  bool _disposed = false;
  bool _unlocked = false;

  Future<bool> unlock() async {
    if (_disposed) {
      return false;
    }

    try {
      final context = _context ??= web.AudioContext();
      await context.resume().toDart;
      _unlocked = context.state == 'running';
      if (_unlocked) {
        _playTone(volume: 0.0001, duration: 0.02);
      }
      return _unlocked;
    } catch (_) {
      _context = null;
      _unlocked = false;
      return false;
    }
  }

  void speakStartMessage(String message) {
    if (_disposed || message.trim().isEmpty) {
      return;
    }

    try {
      final speech = web.window.speechSynthesis;
      speech.cancel();
      speech.resume();
      final utterance = web.SpeechSynthesisUtterance(message)
        ..lang = 'de-DE'
        ..rate = 0.78
        ..pitch = 0.92
        ..volume = 0.94;
      final voice = _preferredGermanVoice(speech);
      if (voice != null) {
        utterance.voice = voice;
      }
      speech.speak(utterance);
    } catch (_) {
      // Browsers can block speech just like audio; the timer should continue.
    }
  }

  void playMinuteTone() {
    if (_disposed) {
      return;
    }

    final context = _context;
    if (context == null || (!_unlocked && context.state != 'running')) {
      return;
    }

    try {
      if (context.state == 'suspended') {
        unawaited(context.resume().toDart);
      }
      _playTone();
    } catch (_) {
      // Site-wide or browser sound blocking should keep the timer working.
    }
  }

  void dispose() {
    _disposed = true;
    final context = _context;
    _context = null;
    if (context != null) {
      unawaited(context.close().toDart);
    }
  }

  void _playTone({
    double frequency = 523.25,
    double volume = 0.075,
    double duration = 0.48,
  }) {
    final context = _context;
    if (context == null) {
      return;
    }

    _playNote(
      context: context,
      frequency: frequency,
      volume: volume,
      duration: duration,
    );
    _playNote(
      context: context,
      frequency: frequency * 1.25,
      volume: volume * 0.72,
      duration: duration * 0.82,
      delay: 0.12,
    );
  }

  void _playNote({
    required web.AudioContext context,
    required double frequency,
    required double volume,
    required double duration,
    double delay = 0,
  }) {
    final oscillator = context.createOscillator();
    final gain = context.createGain();
    final start = context.currentTime + delay;
    final end = start + duration;

    oscillator.type = 'triangle';
    oscillator.frequency.setValueAtTime(frequency, start);
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.linearRampToValueAtTime(volume, start + 0.035);
    gain.gain.linearRampToValueAtTime(volume * 0.32, start + duration * 0.42);
    gain.gain.linearRampToValueAtTime(0.0001, end);
    oscillator.connect(gain);
    gain.connect(context.destination);
    oscillator.start(start);
    oscillator.stop(end + 0.04);

    Timer(Duration(milliseconds: ((delay + duration + 0.12) * 1000).round()),
        () {
      try {
        oscillator.disconnect();
        gain.disconnect();
      } catch (_) {
        // The browser may already have cleaned up the short-lived nodes.
      }
    });
  }
}

web.SpeechSynthesisVoice? _preferredGermanVoice(web.SpeechSynthesis speech) {
  final voices = speech.getVoices().toDart;
  if (voices.isEmpty) {
    return null;
  }

  final germanVoices = [
    for (final voice in voices)
      if (voice.lang.toLowerCase().startsWith('de')) voice,
  ];
  if (germanVoices.isEmpty) {
    return null;
  }

  const warmVoiceNames = [
    'katja',
    'hedda',
    'anna',
    'petra',
    'marlene',
    'helena',
    'amala',
    'google deutsch',
    'google german',
  ];

  for (final preferredName in warmVoiceNames) {
    for (final voice in germanVoices) {
      if (voice.name.toLowerCase().contains(preferredName)) {
        return voice;
      }
    }
  }

  for (final voice in germanVoices) {
    if (voice.localService) {
      return voice;
    }
  }

  return germanVoices.first;
}
