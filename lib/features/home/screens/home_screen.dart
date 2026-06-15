import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/recording.dart';
import '../../../data/repositories/recording_repository.dart';
import '../../../shared/widgets/encrypted_text.dart';
import '../../../shared/widgets/rainbow_button.dart';
import '../../../shared/widgets/session_stats.dart';
import '../../auth/providers/auth_provider.dart';
import '../../recording/start_practice_session.dart';

class HomeScreen extends StatefulWidget {
  /// Switches the shell to the Profile tab (avatar button).
  final VoidCallback? onOpenProfile;

  /// Switches the shell to the Recordings tab ("See all").
  final VoidCallback? onSeeAllRecordings;

  const HomeScreen({super.key, this.onOpenProfile, this.onSeeAllRecordings});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _introController;

  final RecordingRepository _repo = RecordingRepository();
  Stream<List<Recording>>? _recordingsStream;
  String? _streamUserId;

  // Reuses one Firestore listener instead of opening a new one on every
  // rebuild; only re-subscribes if the signed-in user actually changes.
  Stream<List<Recording>> _streamFor(String userId) {
    if (_streamUserId != userId) {
      _streamUserId = userId;
      _recordingsStream = _repo.watchRecordings(userId);
    }
    return _recordingsStream!;
  }

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _introController.dispose();
    super.dispose();
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 18) return 'Good afternoon,';
    return 'Good evening,';
  }

  String _displayName(User? user) {
    final displayName = user?.displayName;
    if (displayName != null && displayName.trim().isNotEmpty) {
      return displayName.trim();
    }
    final email = user?.email ?? '';
    final localPart = email.split('@').first;
    if (localPart.isEmpty) return 'there';
    return localPart[0].toUpperCase() + localPart.substring(1);
  }

  // Fades + slides a child in as part of the staggered intro animation.
  Widget _intro({required double start, required Widget child}) {
    final animation = CurvedAnimation(
      parent: _introController,
      curve: Interval(start, 1.0, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final userId = user?.uid;
    final name = _displayName(user);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ===== Greeting =====
              _intro(
                start: 0.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(),
                      style: const TextStyle(
                        color: AppColors.midMauve,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    EncryptedText(
                      text: name,
                      revealDelay: const Duration(milliseconds: 50),
                      revealedStyle: const TextStyle(
                        color: AppColors.wine,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.7,
                        height: 1.06,
                      ),
                      encryptedStyle: const TextStyle(
                        color: AppColors.softMauve,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.7,
                        height: 1.06,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ===== Hero =====
              _intro(
                start: 0.12,
                child: _HeroCard(onStart: () => startPracticeSession(context)),
              ),

              // ===== Averages (live from Firestore) =====
              if (userId != null)
                StreamBuilder<List<Recording>>(
                  stream: _streamFor(userId),
                  builder: (context, snapshot) {
                    final recordings = snapshot.data ?? [];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 14),
                        if (recordings.isNotEmpty) ...[
                          _intro(
                            start: 0.30,
                            child: SessionStatsCard(
                              recordings: recordings,
                              title: 'Average of all sessions',
                              includeCategories: true,
                              compact: true,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Pieces
// ============================================================================

// Graphite glass hero with an animated aurora and the rainbow CTA.
class _HeroCard extends StatelessWidget {
  final VoidCallback onStart;

  const _HeroCard({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80081026),
            blurRadius: 56,
            offset: Offset(0, 28),
            spreadRadius: -22,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: const Color(0xFF0E1116))),
            const Positioned.fill(child: _Aurora()),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Hero chip
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const Icon(Icons.videocam_rounded,
                            color: Colors.white, size: 18),
                      ),
                      // Live pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _PulsingDot(),
                            const SizedBox(width: 6),
                            Text(
                              'LIVE ANALYSIS',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Practice session',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Live feedback on confidence, eye contact and posture.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  RainbowButton(
                    onPressed: onStart,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome_rounded),
                        SizedBox(width: 9),
                        Text('Start practicing'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'About 10 minutes · uses camera and microphone',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Slow-moving blue/ice/mint radial glows inside the hero.
class _Aurora extends StatefulWidget {
  const _Aurora();

  @override
  State<_Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<_Aurora>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 19),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _glow(Alignment alignment, Color color, double alpha, double size) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        final drift = sin(t * pi) * 0.18;
        return Stack(
          children: [
            _glow(Alignment(-0.8 + drift, -0.6 + drift / 2),
                const Color(0xFF0A84FF), 0.62, 320),
            _glow(Alignment(0.9 - drift, -0.9 + drift),
                const Color(0xFF64D2FF), 0.42, 260),
            _glow(Alignment(0.4 + drift, 1.1 - drift),
                const Color(0xFF30D158), 0.34, 280),
          ],
        );
      },
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.35).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.success,
          boxShadow: [
            BoxShadow(color: AppColors.success, blurRadius: 8),
          ],
        ),
      ),
    );
  }
}
