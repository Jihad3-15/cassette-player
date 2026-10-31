import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Cover art from a local file, falling back to a cassette illustration.
/// Never loads anything from the network.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.path,
    this.size,
    this.borderRadius = 8,
    this.cacheSize,
  });

  final String? path;

  /// Square size. When null the artwork fills its parent.
  final double? size;
  final double borderRadius;

  /// Decode size in logical pixels, to keep memory low in lists and grids.
  final double? cacheSize;

  @override
  Widget build(BuildContext context) {
    final p = path;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decode = cacheSize ?? size;
    final int? cacheWidth = decode == null ? null : (decode * dpr).round();

    final Widget fallback = CassettePlaceholder(compact: (size ?? 999) < 72);
    final Widget child = p == null || p.isEmpty
        ? fallback
        : Image.file(
            File(p),
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => fallback,
          );

    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: child,
    );
    if (size != null) {
      return SizedBox.square(dimension: size, child: clipped);
    }
    return AspectRatio(aspectRatio: 1, child: clipped);
  }
}

/// A drawn cassette tape used when a track has no artwork.
class CassettePlaceholder extends StatelessWidget {
  const CassettePlaceholder({super.key, this.compact = false, this.spin});

  /// Small sizes show a simple icon instead of the full illustration.
  final bool compact;

  /// Optional reel rotation (0..1 turns), used by the Now Playing page.
  final Animation<double>? spin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (compact) {
      return ColoredBox(
        color: scheme.primaryContainer,
        child: Center(
          child: Icon(Icons.music_note_rounded,
              color: scheme.onPrimaryContainer),
        ),
      );
    }
    final s = spin;
    return ColoredBox(
      color: scheme.primaryContainer,
      child: s == null
          ? CustomPaint(
              painter: _CassettePainter(scheme: scheme, turns: 0),
              child: const SizedBox.expand(),
            )
          : AnimatedBuilder(
              animation: s,
              builder: (context, _) => CustomPaint(
                painter: _CassettePainter(scheme: scheme, turns: s.value),
                child: const SizedBox.expand(),
              ),
            ),
    );
  }
}

class _CassettePainter extends CustomPainter {
  _CassettePainter({required this.scheme, required this.turns});

  final ColorScheme scheme;
  final double turns;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Cassette body.
    final bodyW = w * 0.82;
    final bodyH = bodyW * 0.63;
    final body = Rect.fromCenter(
        center: Offset(w / 2, h / 2), width: bodyW, height: bodyH);
    final bodyPaint = Paint()..color = scheme.onPrimaryContainer;
    canvas.drawRRect(
        RRect.fromRectAndRadius(body, Radius.circular(bodyW * 0.05)),
        bodyPaint);

    // Label strip.
    final label = Rect.fromLTWH(body.left + bodyW * 0.07,
        body.top + bodyH * 0.09, bodyW * 0.86, bodyH * 0.56);
    canvas.drawRRect(
        RRect.fromRectAndRadius(label, Radius.circular(bodyW * 0.03)),
        Paint()..color = scheme.primary);
    final stripe = Rect.fromLTWH(
        label.left, label.top + label.height * 0.12, label.width, label.height * 0.12);
    canvas.drawRect(stripe, Paint()..color = scheme.tertiary);

    // Tape window.
    final window = Rect.fromCenter(
      center: Offset(w / 2, label.top + label.height * 0.62),
      width: label.width * 0.62,
      height: label.height * 0.42,
    );
    canvas.drawRRect(
        RRect.fromRectAndRadius(window, Radius.circular(window.height / 2)),
        Paint()..color = scheme.surface);

    // Reels.
    final reelR = window.height * 0.36;
    final leftC = Offset(window.left + window.height / 2, window.center.dy);
    final rightC = Offset(window.right - window.height / 2, window.center.dy);
    final tapePaint = Paint()..color = scheme.onSurface.withValues(alpha: 0.75);
    canvas.drawCircle(leftC, reelR * 1.25, tapePaint);
    canvas.drawCircle(rightC, reelR * 0.95, tapePaint);
    for (final c in [leftC, rightC]) {
      _drawReel(canvas, c, reelR * 0.62);
    }

    // Bottom trapezoid with screw holes.
    final trap = Path()
      ..moveTo(body.left + bodyW * 0.2, body.bottom)
      ..lineTo(body.left + bodyW * 0.26, body.bottom - bodyH * 0.2)
      ..lineTo(body.right - bodyW * 0.26, body.bottom - bodyH * 0.2)
      ..lineTo(body.right - bodyW * 0.2, body.bottom)
      ..close();
    canvas.drawPath(trap, Paint()..color = scheme.primary.withValues(alpha: 0.35));
    final holePaint = Paint()..color = scheme.primaryContainer;
    final holeY = body.bottom - bodyH * 0.1;
    for (final fx in [0.36, 0.64]) {
      canvas.drawCircle(Offset(body.left + bodyW * fx, holeY), bodyW * 0.018, holePaint);
    }
  }

  void _drawReel(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(c, r, Paint()..color = scheme.surface);
    final spoke = Paint()
      ..color = scheme.onSurface
      ..strokeWidth = r * 0.22
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final a = turns * 2 * math.pi + i * 2 * math.pi / 3;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * (r * 0.3),
        c + Offset(math.cos(a), math.sin(a)) * (r * 0.85),
        spoke,
      );
    }
  }

  @override
  bool shouldRepaint(_CassettePainter oldDelegate) =>
      oldDelegate.turns != turns || oldDelegate.scheme != scheme;
}
