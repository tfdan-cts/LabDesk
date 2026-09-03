import 'package:flutter/material.dart';

import '../models/machine_metrics.dart';
import '../theme/console_theme.dart';

/// One proportion over time, small enough to sit under a figure in a tile.
///
/// The axis is fixed at 0..100% and never rescales to the data: a line that
/// filled the box at 3% would read as a machine under load. One hue carries
/// magnitude; the status red is reserved for the moment the latest reading
/// crosses the same threshold the tile's bar uses, so the two never disagree.
/// Hovering reads the sample under the pointer in text tokens, not in the
/// series colour, and the newest segment draws in over [C.medium] rather than
/// popping, which is the whole of the animation budget: one short tween every
/// half minute, nothing running between probes.
class MetricSparkline extends StatefulWidget {
  const MetricSparkline({super.key, required this.points, this.label = ''});

  final List<MetricPoint> points;
  final String label;

  @override
  State<MetricSparkline> createState() => _MetricSparklineState();
}

/// Red only once the latest reading is past the tile bar's threshold.
Color sparklineColor(List<MetricPoint> points) =>
    points.isNotEmpty && points.last.value > 0.9 ? C.bad : C.accent;

String _pct(double v) => '${(v * 100).round()}%';

String _clock(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

class _MetricSparklineState extends State<MetricSparkline> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    if (pts.length < 2) return const SizedBox.shrink();
    final hovered = _hover == null ? null : pts[_hover!.clamp(0, pts.length - 1)];
    return Semantics(
      label:
          '${widget.label} history, ${pts.length} readings, latest ${_pct(pts.last.value)}',
      child: LayoutBuilder(builder: (context, c) {
        return MouseRegion(
          onHover: (e) => setState(() => _hover = _indexAt(e.localPosition.dx, c.maxWidth)),
          onExit: (_) => setState(() => _hover = null),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(pts.length),
                  tween: Tween(begin: 0, end: 1),
                  duration: C.medium,
                  curve: Curves.easeOutCubic,
                  builder: (_, reveal, __) => CustomPaint(
                    painter: _SparkPainter(pts, sparklineColor(pts), _hover, reveal),
                  ),
                ),
              ),
              if (hovered != null)
                Positioned(
                  top: -16,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_clock(hovered.at), style: C.data(size: 10, color: C.textFaint)),
                      Text(_pct(hovered.value), style: C.data(size: 10)),
                    ],
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  int _indexAt(double x, double width) {
    final n = widget.points.length;
    return (x / width * (n - 1)).round().clamp(0, n - 1);
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.points, this.color, this.hover, this.reveal);

  final List<MetricPoint> points;
  final Color color;
  final int? hover;
  final double reveal;

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    const pad = 1.5;
    final h = size.height - pad * 2;
    Offset at(int i) => Offset(
          i / (n - 1) * size.width,
          pad + h * (1 - points[i].value.clamp(0.0, 1.0)),
        );

    // Recessive baseline: the zero line, one hairline.
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5),
        Paint()..color = C.hairline);

    // The newest segment draws in; everything before it is already there.
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < n - 1; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final tip = Offset.lerp(at(n - 2), at(n - 1), reveal)!;
    line.lineTo(tip.dx, tip.dy);

    final area = Path.from(line)
      ..lineTo(tip.dx, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withOpacity(0.12));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final i = hover;
    if (i != null && i >= 0 && i < n) {
      final p = at(i);
      canvas.drawLine(Offset(p.dx, 0), Offset(p.dx, size.height),
          Paint()..color = C.textFaint.withOpacity(0.5));
      // Marker with a surface ring so it separates from the line under it.
      canvas.drawCircle(p, 4.5, Paint()..color = C.surface);
      canvas.drawCircle(p, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.points != points || old.hover != hover || old.reveal != reveal || old.color != color;
}
