import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_exception.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../state/providers.dart';
import '../widgets/common.dart';

/// The lucky wheel.
///
/// The server owns the prize table and the outcome. This screen draws whatever
/// segments it is given, then animates to the index the server returned — it
/// never picks a winner locally.
class LuckyWheelScreen extends ConsumerStatefulWidget {
  const LuckyWheelScreen({super.key});

  @override
  ConsumerState<LuckyWheelScreen> createState() => _LuckyWheelScreenState();
}

class _LuckyWheelScreenState extends ConsumerState<LuckyWheelScreen>
    with SingleTickerProviderStateMixin {
  static const _palette = [
    Color(0xFF7B2FF7),
    Color(0xFF00C2FF),
    Color(0xFF2ED47A),
    Color(0xFFFFC145),
    Color(0xFFFF6B6B),
    Color(0xFFFF4FA3),
  ];

  late final AnimationController _spinController;

  double _angle = 0;
  double _begin = 0;
  double _end = 0;
  bool _spinning = false;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addListener(() {
        setState(() => _angle = _begin + (_end - _begin) * _spinController.value);
      });
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _spin(List<WheelSegment> segments) async {
    if (_spinning || segments.isEmpty) return;

    setState(() => _spinning = true);

    try {
      final result = await ref.read(wheelApiProvider).spin();

      if (!mounted) return;

      await ref.read(walletProvider.notifier).applyLocalWallet(result.wallet);
      ref.invalidate(luckyWheelProvider);

      // Land the winning segment under the pointer at the bottom.
      final count = segments.length;
      final segmentAngle = 2 * math.pi / count;
      final resting = math.pi / 2 -
          (result.segmentIndex * segmentAngle + segmentAngle / 2);

      final current = _angle % (2 * math.pi);
      var target = resting;
      while (target < current) {
        target += 2 * math.pi;
      }
      target += 2 * math.pi * 5;

      _begin = _angle;
      _end = target;

      await _spinController.forward(from: 0);

      if (!mounted) return;

      showSnack(
        context,
        result.prizePoints > 0
            ? 'You won ${result.prizePoints} points!'
            : 'No prize this time. Try again tomorrow.',
      );
    } on ApiException catch (error) {
      if (mounted) showSnack(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _spinning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wheel = ref.watch(luckyWheelProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF140A28),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A1358), Color(0xFF140A28), Color(0xFF0B0714)],
          ),
        ),
        child: SafeArea(
          child: wheel.when(
            loading: () => const LoadingView(message: 'Loading the wheel…'),
            error: (error, _) => ErrorView(
              message: '$error',
              onRetry: () => ref.invalidate(luckyWheelProvider),
            ),
            data: (state) => Column(
              children: [
                const SizedBox(height: 6),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 19),
                    ),
                    const Spacer(),
                  ],
                ),
                const Text(
                  'LUCKY WHEEL',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Get rewards with a simple spin.',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: Center(
                    child: _Wheel(
                      segments: state.segments,
                      angle: _angle,
                      palette: _palette,
                    ),
                  ),
                ),
                _SpinCounter(
                  remaining: state.spinsRemaining,
                  limit: state.dailyLimit,
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 26),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: state.canSpin && !_spinning
                          ? () => _spin(state.segments)
                          : null,
                      icon: const Icon(Icons.casino_rounded, size: 20),
                      label: Text(
                        _spinning
                            ? 'Spinning…'
                            : state.canSpin
                                ? 'Spin the Wheel'
                                : 'Come back tomorrow',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.segments,
    required this.angle,
    required this.palette,
  });

  final List<WheelSegment> segments;
  final double angle;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight) * 0.94;

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: angle,
                child: CustomPaint(
                  size: Size.square(size),
                  painter: _WheelPainter(
                    segments: segments,
                    palette: palette,
                  ),
                ),
              ),
              // Hub
              Container(
                width: size * 0.17,
                height: size * 0.17,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFFFFE08A), Color(0xFFE8A317)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
              // Pointer at the bottom
              Positioned(
                bottom: -2,
                child: CustomPaint(
                  size: Size(size * 0.09, size * 0.11),
                  painter: _PointerPainter(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.segments, required this.palette});

  final List<WheelSegment> segments;
  final List<Color> palette;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    if (segments.isEmpty) return;

    final sweep = 2 * math.pi / segments.length;

    // Outer rim
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFFFFD54F),
    );

    final innerRadius = radius * 0.92;
    final innerRect = Rect.fromCircle(center: center, radius: innerRadius);

    for (var i = 0; i < segments.length; i++) {
      final start = i * sweep;
      final color = palette[i % palette.length];

      canvas.drawArc(
        innerRect,
        start,
        sweep,
        true,
        Paint()..color = color,
      );

      // Separator
      canvas.drawLine(
        center,
        center + Offset(math.cos(start) * innerRadius, math.sin(start) * innerRadius),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35)
          ..strokeWidth = 1.2,
      );

      // Label
      final mid = start + sweep / 2;
      final labelRadius = innerRadius * 0.66;
      final position = center +
          Offset(math.cos(mid) * labelRadius, math.sin(mid) * labelRadius);

      final painter = TextPainter(
        text: TextSpan(
          text: '${segments[i].points}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      painter.paint(
        canvas,
        position - Offset(painter.width / 2, painter.height / 2),
      );
    }

    // Rim stroke
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = const Color(0xFFE8A317),
    );

    canvas.drawCircle(
      center,
      radius * 0.92,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black.withValues(alpha: 0.25),
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) {
    // The rotation is applied by the parent's Transform, so the painter only
    // has to redraw when the prize table itself changes.
    if (oldDelegate.segments.length != segments.length) return true;

    for (var i = 0; i < segments.length; i++) {
      if (oldDelegate.segments[i].points != segments[i].points) return true;
    }

    return false;
  }
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, Paint()..color = const Color(0xFF2ED47A));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SpinCounter extends StatelessWidget {
  const _SpinCounter({required this.remaining, required this.limit});

  final int remaining;
  final int limit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.casino_outlined, color: AppTheme.gold, size: 16),
          const SizedBox(width: 8),
          Text(
            '$remaining of $limit spins left',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
