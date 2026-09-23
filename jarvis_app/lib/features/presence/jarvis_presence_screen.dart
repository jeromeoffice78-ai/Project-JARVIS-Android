import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../voice/jarvis_voice_screen.dart';

class JarvisPresenceScreen
    extends StatefulWidget {
  const JarvisPresenceScreen({super.key});

  @override
  State<JarvisPresenceScreen> createState() =>
      _JarvisPresenceScreenState();
}

class _JarvisPresenceScreenState
    extends State<JarvisPresenceScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration:
          const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'JARVIS Presence',
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (
                BuildContext context,
                Widget? child,
              ) {
                return CustomPaint(
                  painter: _JarvisPainter(
                    phase:
                        _controller.value,
                    primary:
                        Theme.of(context)
                            .colorScheme
                            .primary,
                  ),
                  child:
                      const SizedBox.expand(),
                );
              },
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.fromLTRB(
              16,
              8,
              16,
              24,
            ),
            child: Column(
              children: <Widget>[
                Text(
                  'JARVIS ONLINE',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(
                        fontWeight:
                            FontWeight.bold,
                        letterSpacing: 3,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Visible companion interface • voice • vision • memory • autonomous tools',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder:
                            (BuildContext
                                    context) =>
                                const JarvisVoiceScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.mic),
                  label: const Text(
                    'Talk to Jarvis',
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

class _JarvisPainter extends CustomPainter {
  const _JarvisPainter({
    required this.phase,
    required this.primary,
  });

  final double phase;
  final Color primary;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(
      size.width / 2,
      size.height * 0.43,
    );

    final double pulse =
        0.5 +
        0.5 *
            math.sin(
              phase * math.pi * 2,
            );

    final Paint glow = Paint()
      ..color = primary.withValues(
        alpha: 0.08 + pulse * 0.10,
      )
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      center,
      math.min(
            size.width,
            size.height,
          ) *
          (0.34 + pulse * 0.015),
      glow,
    );

    final Paint ring = Paint()
      ..color = primary.withValues(
        alpha: 0.35,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (int i = 0; i < 4; i++) {
      final double radius =
          58 + i * 34 + pulse * 7;

      canvas.save();
      canvas.translate(
        center.dx,
        center.dy,
      );
      canvas.rotate(
        phase *
                math.pi *
                2 *
                (i.isEven ? 1 : -1) +
            i * 0.45,
      );
      final Rect oval = Rect.fromCenter(
        center: Offset.zero,
        width: radius * 2.2,
        height: radius * 0.72,
      );
      canvas.drawOval(oval, ring);
      canvas.restore();
    }

    final Paint body = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          primary.withValues(alpha: 0.95),
          primary.withValues(alpha: 0.22),
        ],
      ).createShader(
        Rect.fromCenter(
          center: center,
          width: 180,
          height: 300,
        ),
      );

    final Path torso = Path()
      ..moveTo(
        center.dx - 72,
        center.dy + 72,
      )
      ..quadraticBezierTo(
        center.dx - 102,
        center.dy + 145,
        center.dx - 52,
        center.dy + 228,
      )
      ..lineTo(
        center.dx + 52,
        center.dy + 228,
      )
      ..quadraticBezierTo(
        center.dx + 102,
        center.dy + 145,
        center.dx + 72,
        center.dy + 72,
      )
      ..quadraticBezierTo(
        center.dx,
        center.dy + 98,
        center.dx - 72,
        center.dy + 72,
      )
      ..close();

    canvas.drawPath(torso, body);

    final Rect head = Rect.fromCenter(
      center: Offset(
        center.dx,
        center.dy - 28,
      ),
      width: 126,
      height: 154,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        head,
        const Radius.circular(54),
      ),
      body,
    );

    final Paint dark = Paint()
      ..color =
          Colors.black.withValues(alpha: 0.78);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(
            center.dx,
            center.dy - 20,
          ),
          width: 102,
          height: 112,
        ),
        const Radius.circular(42),
      ),
      dark,
    );

    final Paint eye = Paint()
      ..color = primary.withValues(
        alpha: 0.82 + pulse * 0.18,
      )
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(
        center.dx - 35,
        center.dy - 38,
      ),
      Offset(
        center.dx - 10,
        center.dy - 34,
      ),
      eye,
    );
    canvas.drawLine(
      Offset(
        center.dx + 10,
        center.dy - 34,
      ),
      Offset(
        center.dx + 35,
        center.dy - 38,
      ),
      eye,
    );

    final double mouth =
        5 + pulse * 7;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(
            center.dx,
            center.dy + 6,
          ),
          width: 42,
          height: mouth,
        ),
        const Radius.circular(8),
      ),
      eye,
    );

    final Paint core = Paint()
      ..color = primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    canvas.drawCircle(
      Offset(
        center.dx,
        center.dy + 134,
      ),
      24 + pulse * 3,
      core,
    );
  }

  @override
  bool shouldRepaint(
    covariant _JarvisPainter oldDelegate,
  ) {
    return oldDelegate.phase != phase ||
        oldDelegate.primary != primary;
  }
}
