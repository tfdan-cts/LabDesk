import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/reach_sample.dart';
import '../theme/console_theme.dart';

export '../models/reach_sample.dart' show ReachSample;

/// Reachability over the current session.
///
/// The job is change over time, so this is an area chart. One series, so no
/// legend: the panel title names it. The window is deliberately the session
/// only, because nothing retains history while LabDesk is closed and a chart
/// implying otherwise would be a lie.
class ReachabilityChart extends StatefulWidget {
  const ReachabilityChart({
    super.key,
    required this.samples,
    this.height = 132,
  });

  final List<ReachSample> samples;
  final double height;

  @override
  State<ReachabilityChart> createState() => _ReachabilityChartState();
}

class _ReachabilityChartState extends State<ReachabilityChart> {
  int? _hoverIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.samples.length < 2) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'Collecting. The first readings appear within a minute.',
            style: C.small(color: C.textFaint),
          ),
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, box) {
          return MouseRegion(
            onExit: (_) => setState(() => _hoverIndex = null),
            onHover: (e) {
              final i = _indexAt(e.localPosition.dx, box.maxWidth);
              if (i != _hoverIndex) setState(() => _hoverIndex = i);
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ReachPainter(
                      samples: widget.samples,
                      hoverIndex: _hoverIndex,
                    ),
                  ),
                ),
                if (_hoverIndex != null)
                  _Readout(
                    sample: widget.samples[_hoverIndex!],
                    x: _xFor(_hoverIndex!, box.maxWidth),
                    width: box.maxWidth,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  int _indexAt(double dx, double width) {
    final n = widget.samples.length;
    final t = (dx / width).clamp(0.0, 1.0);
    return (t * (n - 1)).round().clamp(0, n - 1);
  }

  double _xFor(int i, double width) =>
      width * (i / (widget.samples.length - 1));
}

/// The hover readout. Values wear text tokens; the coloured mark beside them
/// carries identity, so the number is never tinted by the series colour.
class _Readout extends StatelessWidget {
  const _Readout({required this.sample, required this.x, required this.width});

  final ReachSample sample;
  final double x;
  final double width;

  @override
  Widget build(BuildContext context) {
    const w = 132.0;
    final left = (x - w / 2).clamp(0.0, math.max(0.0, width - w)).toDouble();
    return Positioned(
      left: left,
      top: 0,
      child: Container(
        width: w,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: C.surfaceHi,
          borderRadius: C.roundedSm,
          border: Border.all(color: C.hairline),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_clock(sample.at), style: C.data(size: 11, color: C.textFaint)),
            const SizedBox(height: 5),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(color: C.ok, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Text('${sample.online} of ${sample.total}', style: C.small(color: C.text)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _ReachPainter extends CustomPainter {
  _ReachPainter({required this.samples, required this.hoverIndex});

  final List<ReachSample> samples;
  final int? hoverIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final n = samples.length;
    // The axis is machine count, so it starts at zero and tops out at the
    // fleet size. Not auto-scaled: a chart that rescales its own baseline
    // makes a one-machine dip look like a collapse.
    final maxV = samples.map((s) => s.total).reduce(math.max).toDouble();
    final top = maxV == 0 ? 1.0 : maxV;

    double x(int i) => size.width * (i / (n - 1));
    double y(num v) => size.height - (v / top) * (size.height - 6) - 3;

    // Recessive gridlines. Present so values can be read, quiet enough that
    // the data stays the loudest thing.
    final grid = Paint()
      ..color = C.hairline.withOpacity(0.55)
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final gy = y(top * i / 2);
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }

    final path = Path();
    final fill = Path();
    for (var i = 0; i < n; i++) {
      final p = Offset(x(i), y(samples[i].online));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
        fill.moveTo(p.dx, size.height);
        fill.lineTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
        fill.lineTo(p.dx, p.dy);
      }
    }
    fill.lineTo(x(n - 1), size.height);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x383FCF8E), Color(0x003FCF8E)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = C.ok
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    if (hoverIndex != null) {
      final hx = x(hoverIndex!);
      canvas.drawLine(
        Offset(hx, 0),
        Offset(hx, size.height),
        Paint()
          ..color = C.textFaint.withOpacity(0.5)
          ..strokeWidth = 1,
      );
      final hy = y(samples[hoverIndex!].online);
      // A surface ring so the marker reads against the fill it sits on.
      canvas.drawCircle(Offset(hx, hy), 5.5, Paint()..color = C.surface);
      canvas.drawCircle(Offset(hx, hy), 4, Paint()..color = C.ok);
    }
  }

  @override
  bool shouldRepaint(covariant _ReachPainter old) =>
      old.hoverIndex != hoverIndex || old.samples != samples;
}

/// A per-machine availability strip.
///
/// Small multiples: one row per machine, each cell a check. Reads as a pattern
/// of when a machine was up, which a single status dot cannot express. Cells
/// carry a 2px surface gap so adjacent states stay separable.
class AvailabilityStrip extends StatelessWidget {
  const AvailabilityStrip({
    super.key,
    required this.history,
    this.width = 74,
    this.height = 16,
  });

  /// Oldest first. Null means the machine was never checked in that slot.
  final List<bool?> history;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: CustomPaint(painter: _StripPainter(history)),
      );
}

class _StripPainter extends CustomPainter {
  _StripPainter(this.history);

  final List<bool?> history;

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;
    const gap = 2.0;
    final n = history.length;
    final w = (size.width - gap * (n - 1)) / n;
    for (var i = 0; i < n; i++) {
      final v = history[i];
      final paint = Paint()
        ..color = switch (v) {
          true => C.ok,
          false => C.bad,
          null => C.hairline,
        };
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * (w + gap), 0, w, size.height),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StripPainter old) => old.history != history;
}
