import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  static const _landingImage = 'assets/splash/landingpage_01.jpg';
  static const _loadingSteps = [
    'Flotte laden...',
    'Akkus pruefen...',
    'Flugbuch vorbereiten...',
    'Wartungen abgleichen...',
    'Startklar.',
  ];

  Timer? _timer;
  double _progress = 0;
  int _stepIndex = 0;

  bool get _isReady => _progress >= 1;

  @override
  void initState() {
    super.initState();
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
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                                semanticLabel: 'Modellflug App Landing Page',
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
                                    onOpenDashboard: () =>
                                        context.go('/dashboard'),
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
  final VoidCallback onOpenDashboard;

  const _LoadingPanel({
    required this.progress,
    required this.status,
    required this.isReady,
    required this.onOpenDashboard,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 240),
            opacity: isReady ? 0.94 : 0.82,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isReady
                      ? Icons.check_circle_rounded
                      : Icons.flight_takeoff_rounded,
                  color: isReady
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFF0A84FF),
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: isReady
                ? Padding(
                    key: const ValueKey('ready-button'),
                    padding: const EdgeInsets.only(top: 14),
                    child: FilledButton.icon(
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
                    ),
                  )
                : const SizedBox(
                    key: ValueKey('loading-space'),
                    height: 10,
                  ),
          ),
        ],
      ),
    );
  }
}
