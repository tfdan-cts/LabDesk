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
    // Before there are two readings there is no line to draw. Reserving the
    // full plot height for a sentence left it floating in the middle of the
    // card, unattached to the label that introduces it, so the collecting
    // state is a short note on the same left edge as everything above it.
    if (widget.samples.length < 2) {
      return SizedBox(
        height: 28,
        child: Row(
          children: [
            Container(width: 16, height: 1, color: C.hairline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Collecting. The first readings appear within a minute.',
                style: C.small(color: C.textFaint),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      child: Column(
        children: [
          Expanded(child: _plot()),
          const SizedBox(height: 6),
          // The window the line covers, said in figures. Without it the chart
          // claims a period it never names, and the reader has to hover to
          // find out how much time they are looking at.
          Row(
            children: [
              Text(_clock(widget.samples.first.at),
                  style: C.data(size: 10, color: C.textFaint)),
              const Spacer(),
              Text(_clock(widget.samples.last.at),
                  style: C.data(size: 10, color: C.textFaint)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _plot() {
    return LayoutBuilder(
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
}

String _clock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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

    // Recessive gridlines, drawn over the area and under the line. Beneath the
    // fill they were invisible for exactly the values the fill covers, which
    // is every value the chart is about.
    final grid = Paint()
      ..color = C.hairline
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final gy = y(top * i / 2);
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }

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

/// The fleet's current mix, as one mark.
///
/// Sits directly under the three counts in the same order, so the counts are
/// its labels and the two read as one object rather than as a number column
/// next to a chart. Not a chart of anything over time: it is the same reading
/// the counts are, given a shape.
class FleetMixBar extends StatelessWidget {
  const FleetMixBar({
    super.key,
    required this.online,
    required this.offline,
    required this.unknown,
    this.height = 8,
  });

  final int online;
  final int offline;
  final int unknown;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: CustomPaint(
          painter: _MixPainter(online: online, offline: offline, unknown: unknown),
        ),
      );
}

class _MixPainter extends CustomPainter {
  _MixPainter({required this.online, required this.offline, required this.unknown});

  final int online;
  final int offline;
  final int unknown;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    final track = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.drawRRect(track, Paint()..color = C.hairline);

    final total = online + offline + unknown;
    if (total == 0) return;

    // The segments are cut from the track and separated by a gap of the
    // background, so two adjacent runs stay countable without a second colour.
    const gap = 3.0;
    final runs = [
      (online, C.ok, false),
      (offline, C.bad, false),
      (unknown, C.idle, true),
    ].where((e) => e.$1 > 0).toList();
    final free = size.width - gap * (runs.length - 1);

    var x = 0.0;
    for (final (count, colour, pending) in runs) {
      final w = free * count / total;
      final rect = Rect.fromLTWH(x, 0, w, size.height);
      final seg = RRect.fromRectAndRadius(rect, r);
      if (pending) {
        // Unknown is drawn open and ticked rather than solid: an operator who
        // cannot separate the two hues still sees that this run is a run of
        // missing readings and not a run of failures.
        canvas.save();
        canvas.clipRRect(seg);
        final tick = Paint()..color = C.idle;
        for (var tx = rect.left + 1; tx < rect.right; tx += 6) {
          canvas.drawRect(Rect.fromLTWH(tx, 0, 1.5, size.height), tick);
        }
        canvas.restore();
      } else {
        canvas.drawRRect(seg, Paint()..color = colour);
      }
      x += w + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _MixPainter old) =>
      old.online != online || old.offline != offline || old.unknown != unknown;
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
    this.width = 88,
    this.height = 18,
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
    const gap = 3.0;
    final n = history.length;
    final w = (size.width - gap * (n - 1)) / n;
    for (var i = 0; i < n; i++) {
      final v = history[i];
      final rect = Rect.fromLTWH(i * (w + gap), 0, w, size.height);
      if (v == null) {
        // A cell with no reading is drawn as an outline. Filled in a grey it
        // read as either a gap in the strip or a third state of the machine;
        // an empty cell reads as what it is, a check that was never made.
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(1.5)),
          Paint()
            ..color = C.idle
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
        continue;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        Paint()..color = v ? C.ok : C.bad,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StripPainter old) => old.history != history;
}

/// What the strip's cells mean, spelled out.
///
/// The strip is the one place on the screen where a mark carries state with no
/// word beside it, so the words live here instead of only in a tooltip.
///
/// The words are the product's three: Online, Offline, Unknown. This legend
/// used to say reachable, unreachable and not checked, which named the same
/// three states a second way twelve rows under the card that had already named
/// them, and left the operator to work out that they were the same thing.
class AvailabilityLegend extends StatelessWidget {
  const AvailabilityLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(String label, Color colour, bool open) => Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 12,
                decoration: BoxDecoration(
                  color: open ? null : colour,
                  border: open ? Border.all(color: colour, width: 1) : null,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              const SizedBox(width: 6),
              Text(label, style: C.micro()),
            ],
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        item('Online', C.ok, false),
        item('Offline', C.bad, false),
        item('Unknown', C.idle, true),
      ],
    );
  }
}
