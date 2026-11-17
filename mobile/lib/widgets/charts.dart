import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// All charts are hand-drawn with CustomPaint - no charting package, as
/// specified in the build spec. Each one animates its value so the
/// dashboard feels alive on load.

/// Circular calorie-progress ring with a percentage in the middle.
class CalorieRing extends StatelessWidget {
  const CalorieRing({
    super.key,
    required this.progress,
    this.size = 92,
    this.strokeWidth = 10,
    this.color = AppColors.primary,
    this.trackColor = const Color(0xFFE2E5E3),
  });

  /// 0.0 - 1.0
  final double progress;
  final double size;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final value = progress.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(
              progress: animated,
              strokeWidth: strokeWidth,
              color: color,
              trackColor: trackColor,
            ),
            child: Center(
              child: Text(
                '${(animated * 100).round()}%',
                style: TextStyle(
                  fontSize: size * 0.22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDeep,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;

    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// Vertical "thermometer" gauge used by the macro cards.
class MacroGauge extends StatelessWidget {
  const MacroGauge({
    super.key,
    required this.value,
    required this.target,
    required this.color,
    this.height = 56,
    this.width = 12,
  });

  final double value;
  final double target;
  final Color color;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) {
    final fill = target <= 0 ? 0.0 : (value / target).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fill),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFECEFEE),
          borderRadius: BorderRadius.circular(width),
        ),
        alignment: Alignment.bottomCenter,
        child: Container(
          width: width,
          height: height * animated,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(width),
          ),
        ),
      ),
    );
  }
}

/// Compact bar chart of recent weigh-ins, used on the dashboard.
/// The most recent bar is highlighted.
class WeightBarChart extends StatelessWidget {
  const WeightBarChart({
    super.key,
    required this.values,
    this.height = 84,
  });

  final List<double> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Log a weigh-in to see your trend',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    // Pad the range so a flat series still renders visible bars.
    final range = (maxV - minV).abs() < 0.6 ? 0.6 : (maxV - minV);
    final floor = minV - range * 0.35;

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(
                  begin: 0,
                  end: ((values[i] - floor) / (maxV - floor)).clamp(0.15, 1.0),
                ),
                duration: Duration(milliseconds: 450 + i * 60),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => Container(
                  height: height * t,
                  decoration: BoxDecoration(
                    color: i == values.length - 1
                        ? AppColors.primary
                        : AppColors.mint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            if (i != values.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// Smooth weight-over-time line chart with a soft area fill, used on the
/// progress screen. Drawn with a Catmull-Rom-style cubic through the
/// points so it matches the curved line in the mockup.
class WeightLineChart extends StatelessWidget {
  const WeightLineChart({
    super.key,
    required this.values,
    this.height = 180,
  });

  final List<double> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            values.isEmpty
                ? 'No weigh-ins recorded yet'
                : 'Log another weigh-in to draw your trend',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => CustomPaint(
          painter: _LinePainter(values: values, reveal: t),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.values, required this.reveal});

  final List<double> values;
  final double reveal;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    final span = (maxV - minV).abs() < 0.5 ? 0.5 : (maxV - minV);
    final top = maxV + span * 0.25;
    final bottom = minV - span * 0.25;

    Offset pointAt(int i) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * (i / (values.length - 1));
      final y = size.height * ((top - values[i]) / (top - bottom));
      return Offset(x, y);
    }

    final points = [for (var i = 0; i < values.length; i++) pointAt(i)];

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final dx = (p1.dx - p0.dx) / 2;
      path.cubicTo(p0.dx + dx, p0.dy, p1.dx - dx, p1.dy, p1.dx, p1.dy);
    }

    // Area fill under the curve.
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()..color = AppColors.mintSoft.withValues(alpha: 0.9 * reveal),
    );

    // The stroke itself, revealed left-to-right.
    final metrics = path.computeMetrics().toList();
    final stroke = Paint()
      ..color = const Color(0xFF3E6B57)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final m in metrics) {
      canvas.drawPath(m.extractPath(0, m.length * reveal), stroke);
    }

    // Dots on each recorded point that has been revealed.
    final dot = Paint()..color = const Color(0xFF3E6B57);
    final dotRing = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (var i = 0; i < points.length; i++) {
      final progressAt = points.length == 1 ? 1.0 : i / (points.length - 1);
      if (progressAt > reveal) continue;
      canvas.drawCircle(points[i], 4.5, dot);
      canvas.drawCircle(points[i], 4.5, dotRing);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.reveal != reveal || !listEquals(old.values, values);

  static bool listEquals(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
