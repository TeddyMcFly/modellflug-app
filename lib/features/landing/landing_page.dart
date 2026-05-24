import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/providers/fleet_provider.dart';
import '../../shared/services/start_sound_player.dart';

class LandingPage extends ConsumerStatefulWidget {
  const LandingPage({super.key});

  @override
  ConsumerState<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends ConsumerState<LandingPage> {
  static const _landingImage = 'assets/splash/landingpage_heaven.png';
  static const _startSound = 'assets/audio/prog_start.mp3';
  static bool _startSoundPlayed = false;
  static const _loadingSteps = [
    'Flotte laden...',
    'Akkus pruefen...',
    'Flugbuch vorbereiten...',
    'Wartungen abgleichen...',
    'Startklar.',
  ];

  Timer? _timer;
  Timer? _soundDelayTimer;
  late final StartSoundPlayer _startSoundPlayer;
  double _progress = 0;
  int _stepIndex = 0;
  bool _isLeaving = false;
  bool _loadingCompleteHandled = false;
  bool _showEnableSoundButton = false;

  bool get _isReady => _progress >= 1;

  @override
  void initState() {
    super.initState();
    _startSoundPlayer = StartSoundPlayer(_startSound);
    _soundDelayTimer = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(_playStartSoundIfAllowed()),
    );

    _timer = Timer.periodic(const Duration(milliseconds: 180), (timer) {
      if (!mounted) {
        return;
      }

      setState(() {
        _progress = (_progress + 0.045).clamp(0, 1);
        _stepIndex = (_progress * (_loadingSteps.length - 1))
            .floor()
            .clamp(0, _loadingSteps.length - 1);
      });

      if (_isReady) {
        timer.cancel();
        unawaited(_handleLoadingComplete());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _soundDelayTimer?.cancel();
    _startSoundPlayer.dispose();
    super.dispose();
  }

  Future<void> _playStartSoundIfAllowed() async {
    if (!mounted || _startSoundPlayed) {
      return;
    }

    final fleet = ref.read(fleetProvider);
    if (!fleet.isLoaded) {
      _soundDelayTimer?.cancel();
      _soundDelayTimer = Timer(
        const Duration(milliseconds: 100),
        () => unawaited(_playStartSoundIfAllowed()),
      );
      return;
    }

    if (!fleet.appSettings.playStartSound) {
      if (_showEnableSoundButton) {
        setState(() {
          _showEnableSoundButton = false;
        });
      }
      return;
    }

    final didStart = await _startSoundPlayer.play();
    if (!mounted) {
      return;
    }

    if (didStart) {
      _startSoundPlayed = true;
      if (_showEnableSoundButton) {
        setState(() {
          _showEnableSoundButton = false;
        });
      }
      return;
    }

    if (!_showEnableSoundButton) {
      setState(() {
        _showEnableSoundButton = true;
      });
    }
  }

  Future<void> _enableStartSound() async {
    if (_startSoundPlayed) {
      setState(() {
        _showEnableSoundButton = false;
      });
      return;
    }

    final fleet = ref.read(fleetProvider);
    if (!fleet.isLoaded || !fleet.appSettings.playStartSound) {
      return;
    }

    final didStart = await _startSoundPlayer.play();
    if (!mounted) {
      return;
    }

    if (!didStart) {
      setState(() {
        _showEnableSoundButton = true;
      });
      return;
    }

    _startSoundPlayed = true;
    setState(() {
      _showEnableSoundButton = false;
    });

    if (_isReady &&
        fleet.appSettings.autoOpenDashboardAfterLoading &&
        !_isLeaving) {
      unawaited(_openDashboard());
    }
  }

  Future<void> _handleLoadingComplete() async {
    if (_loadingCompleteHandled) {
      return;
    }
    _loadingCompleteHandled = true;

    while (mounted && !ref.read(fleetProvider).isLoaded) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    if (!mounted) {
      return;
    }

    if (ref.read(fleetProvider).appSettings.autoOpenDashboardAfterLoading &&
        !_showEnableSoundButton) {
      await _openDashboard();
    }
  }

  Future<void> _openDashboard() async {
    if (_isLeaving) {
      return;
    }
    _isLeaving = true;
    await _startSoundPlayer.fadeOut(
      duration: const Duration(milliseconds: 900),
    );
    if (mounted) {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fleet = ref.watch(fleetProvider);
    if (_isReady &&
        fleet.isLoaded &&
        fleet.appSettings.autoOpenDashboardAfterLoading &&
        !_showEnableSoundButton &&
        !_isLeaving) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_openDashboard());
        }
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF06172E),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth - 48;
          final availableHeight = constraints.maxHeight - 48;
          final posterWidth = (availableHeight * 2 / 3).clamp(
            280.0,
            availableWidth.clamp(280.0, 720.0),
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                _landingImage,
                fit: BoxFit.cover,
                opacity: const AlwaysStoppedAnimation(0.32),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF043A83).withValues(alpha: 0.18),
                      const Color(0xFF06172E).withValues(alpha: 0.88),
                    ],
                  ),
                ),
              ),
              SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: posterWidth,
                        maxHeight: availableHeight,
                      ),
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset(
                                _landingImage,
                                fit: BoxFit.cover,
                                semanticLabel: 'Modellflug-Heaven Landing Page',
                              ),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(24, 0, 24, 30),
                                  child: _LoadingPanel(
                                    progress: _progress,
                                    status: _loadingSteps[_stepIndex],
                                    isReady: _isReady,
                                    showEnableSoundButton:
                                        _showEnableSoundButton,
                                    onEnableSound: _enableStartSound,
                                    onOpenDashboard: _openDashboard,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  final double progress;
  final String status;
  final bool isReady;
  final bool showEnableSoundButton;
  final VoidCallback onEnableSound;
  final VoidCallback onOpenDashboard;

  const _LoadingPanel({
    required this.progress,
    required this.status,
    required this.isReady,
    required this.showEnableSoundButton,
    required this.onEnableSound,
    required this.onOpenDashboard,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: showEnableSoundButton
                ? Padding(
                    key: const ValueKey('enable-sound-button'),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FilledButton.icon(
                      onPressed: onEnableSound,
                      icon: const Icon(Icons.volume_up_rounded, size: 18),
                      label: const Text('Ton aktivieren'),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF22C55E).withValues(alpha: 0.94),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(190, 40),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('enable-sound-empty')),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: isReady
                ? FilledButton.icon(
                    key: const ValueKey('ready-button'),
                    onPressed: onOpenDashboard,
                    icon: const Icon(Icons.flight_takeoff_rounded),
                    label: const Text('Dashboard oeffnen'),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF0A84FF).withValues(alpha: 0.92),
                      minimumSize: const Size(190, 40),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                : Column(
                    key: const ValueKey('loading-panel'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 240),
                        opacity: 0.82,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.flight_takeoff_rounded,
                              color: Color(0xFF0A84FF),
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              status.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(progress * 100).round()}%',
                              style: const TextStyle(
                                color: Color(0xFFBFDBFE),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          value: progress,
                          color: const Color(0xFF0A84FF),
                          backgroundColor: Colors.white.withValues(alpha: 0.24),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
