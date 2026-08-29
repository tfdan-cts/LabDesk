import '../models/machine_metrics.dart';
import 'metrics_collector.dart';

enum ProbeState {
  /// Asked, nothing conclusive back yet.
  running,

  /// The machine answered and the answer held usable figures.
  complete,

  /// The machine was asked and did not produce figures: the command failed,
  /// the shell printed only noise, or nothing came back in time.
  failed,
}

class ProbeOutcome {
  const ProbeOutcome({
    required this.state,
    this.metrics = const [],
    this.exitCode,
    this.timedOut = false,
  });

  final ProbeState state;
  final List<Metric> metrics;

  /// The exit status the far shell reported, when it reported one. Null when
  /// the probe timed out, because then nothing ever said how it ended.
  final int? exitCode;

  final bool timedOut;
}

/// Frames one run of the health probe over a terminal channel.
///
/// The collector already knows how to read a machine's answer. This knows when
/// the answer is finished, which a PTY does not otherwise say: it is a byte
/// stream with a prompt at either end, not a request and a response.
///
/// The distinction it exists to preserve is between a probe that was never
/// attempted and one that ran and produced nothing. Health renders those
/// differently on purpose. Showing a failed probe as an idle screen is the same
/// class of lie as showing an unreachable machine as offline, which the peer
/// status work was written to stop.
class ProbeReader {
  final _buffer = StringBuffer();
  ProbeOutcome _outcome = const ProbeOutcome(state: ProbeState.running);

  ProbeOutcome get outcome => _outcome;

  bool get isFinished => _outcome.state != ProbeState.running;

  /// Feed whatever arrived from the channel. Chunks are bytes off a PTY, so a
  /// line can and does arrive in pieces.
  void feed(String chunk) {
    if (isFinished) return;
    _buffer.write(chunk);
    _tryFinish();
  }

  /// Nothing arrived in time. A machine that never answered is a different
  /// report from one that answered badly, so it is recorded as its own thing.
  void timedOut() {
    if (isFinished) return;
    _outcome = const ProbeOutcome(
      state: ProbeState.failed,
      timedOut: true,
    );
  }

  void _tryFinish() {
    final text = _buffer.toString();
    // A PTY echoes the command that was typed, and that text contains the
    // marker. Only a marker followed by an actual number is the shell
    // reporting a status, so the echo cannot end the probe on its own.
    final match =
        RegExp('${RegExp.escape(MetricsCollector.endMarker)}=(-?\\d+)')
            .firstMatch(text);
    if (match == null) return;

    final exitCode = int.tryParse(match.group(1)!);
    final metrics = MetricsCollector.parse(text);

    // An exit of zero with nothing usable in it is still a failure. The command
    // may have run against a shell that lacks what it needs, or the output may
    // have been swallowed; either way there is no measurement, and rendering
    // one would be inventing it.
    final ok = exitCode == 0 && metrics.isNotEmpty;
    _outcome = ProbeOutcome(
      state: ok ? ProbeState.complete : ProbeState.failed,
      metrics: ok ? metrics : const [],
      exitCode: exitCode,
    );
  }
}
