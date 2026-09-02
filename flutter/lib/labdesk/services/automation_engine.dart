import '../../common/labdesk_peer_status.dart';
import '../models/automation_models.dart';
import '../models/machine_metrics.dart';

/// Evaluates the operator's rules against what the console can actually see.
///
/// Agentless, and it does not pretend otherwise. There is no server holding
/// these rules and nothing installed on the far machines: this runs inside the
/// console's own one second tick, on this machine, while LabDesk is open. Close
/// the application and nothing is evaluated until it is opened again.
///
/// Pure Dart with the clock passed in, which is what makes every rule below
/// testable to the minute rather than by waiting for one.
///
/// The three properties the tests exist to hold:
///
///   - **Edges are edges.** Coming online and going offline fire only on a
///     transition the console watched happen, between two consecutive ticks.
///     A machine that is already down when the console opens did not go down
///     while anyone was looking, and the unknown status is "nobody has asked",
///     not "it is down", so nothing transitions through it.
///   - **"for N minutes" means continuously.** The condition is timed from the
///     moment it became true and the timer is thrown away the instant it stops
///     being true. A flap resets it.
///   - **Schedules never catch up.** A slot that came due while the console was
///     closed is skipped, not replayed. The alternative is a console that opens
///     on Monday and runs sixty hourly commands at once.
class AutomationEngine {
  AutomationEngine([List<Rule> rules = const []]) : _rules = List.of(rules);

  List<Rule> _rules;

  final RunLog log = RunLog();

  /// Status as of the previous tick, which is what an edge is measured against.
  final _prevStatus = <String, LabDeskPeerStatus>{};

  /// Rules that have had their baseline tick. A rule fires nothing on the tick
  /// it first appears: the first one establishes what "before" was, and a rule
  /// loaded at start-up must not fire on whatever state the fleet happens to be
  /// in at the moment the console opened.
  final _baselined = <String>{};

  /// When a machine was last watched going offline. Absent means the console
  /// never saw the transition, so a duration cannot be claimed for it.
  final _offlineSince = <String, DateTime>{};

  /// When a level condition (a metric, an uptime) became true, per rule and
  /// machine. Cleared the moment it stops being true.
  final _trueSince = <String, DateTime>{};

  /// Level conditions that have already fired for the episode they are in.
  /// Cleared when the condition goes false, so one episode gets one firing.
  final _latched = <String>{};

  /// Per rule and machine, the earliest the rule may fire again.
  final _cooldownUntil = <String, DateTime>{};

  /// Interval schedules: when the next slot falls due.
  final _nextDue = <String, DateTime>{};

  /// Time-of-day schedules: the slot most recently accounted for, fired or
  /// baselined. Comparing against it is what stops a slot running twice.
  final _lastSlot = <String, DateTime>{};

  var _seq = 0;

  List<Rule> get rules => List.unmodifiable(_rules);

  /// Replace the rule list, dropping the state of rules that are gone.
  ///
  /// A rule that is edited keeps its id and therefore its cooldown and its
  /// baseline, so saving the editor does not re-arm every rule on the screen.
  set rules(List<Rule> next) {
    _rules = List.of(next);
    final live = {for (final r in _rules) r.id};
    _baselined.removeWhere((id) => !live.contains(id));
    _nextDue.removeWhere((id, _) => !live.contains(id));
    _lastSlot.removeWhere((id, _) => !live.contains(id));
    for (final map in [_trueSince, _cooldownUntil]) {
      map.removeWhere((k, _) => !live.contains(_ruleOfKey(k)));
    }
    _latched.removeWhere((k) => !live.contains(_ruleOfKey(k)));
  }

  /// One evaluation pass. Returns what the caller should carry out, in rule
  /// order and then machine id order, so the same inputs always produce the
  /// same list.
  ///
  /// [status] is reachability per machine, [metrics] the latest probe figures
  /// per monitored machine, and [machines] every machine the console knows
  /// about. A machine missing from [status] reads as unknown rather than as
  /// offline, which is the same distinction the fleet table draws.
  List<Firing> tick({
    required DateTime now,
    required Map<String, LabDeskPeerStatus> status,
    required Map<String, List<Metric>> metrics,
    required Set<String> machines,
  }) {
    final ids = machines.toList()..sort();
    final out = <Firing>[];

    // Offline durations are a property of the machine, not of any one rule, so
    // they are tracked once per tick before the rules are walked.
    for (final id in ids) {
      final prev = _prevStatus[id];
      final next = status[id] ?? LabDeskPeerStatus.unknown;
      if (prev == LabDeskPeerStatus.online &&
          next == LabDeskPeerStatus.offline) {
        _offlineSince[id] = now;
      } else if (next != LabDeskPeerStatus.offline) {
        // Online again, or nobody knows any more. Either way the console can no
        // longer say the machine has been down continuously since anything.
        _offlineSince.remove(id);
      }
    }

    for (final rule in _rules) {
      final baselining = !_baselined.contains(rule.id);
      _baselined.add(rule.id);
      if (!rule.enabled) {
        // Still baselined above, so enabling a rule does not fire it on
        // whatever the fleet looks like at that moment.
        continue;
      }

      final targets = _targetsOf(rule, ids);
      final due = _scheduleDue(rule, now, baselining);

      for (final id in targets) {
        final key = _key(rule.id, id);
        final fire = switch (rule.trigger) {
          CameOnline() => !baselining &&
              _prevStatus[id] == LabDeskPeerStatus.offline &&
              (status[id] ?? LabDeskPeerStatus.unknown) ==
                  LabDeskPeerStatus.online,
          WentOffline(:final forMinutes) =>
            _offlineFires(key, id, now, status, forMinutes, baselining),
          MetricAbove(:final metric, :final threshold, :final forMinutes) =>
            _levelFires(
              key,
              now,
              _pctOf(metrics[id], metric.label).let((v) => v > threshold),
              forMinutes,
              baselining,
            ),
          UptimeAbove(:final days) => _levelFires(
              key,
              now,
              _uptimeDaysOf(metrics[id]).let((v) => v > days),
              0,
              baselining,
            ),
          Schedule() => due,
        };

        if (!fire) continue;
        final until = _cooldownUntil[key];
        if (until != null && now.isBefore(until)) continue;
        if (rule.cooldown > Duration.zero) {
          _cooldownUntil[key] = now.add(rule.cooldown);
        }
        out.add(_emit(rule, id, now));
      }
    }

    _prevStatus
      ..removeWhere((id, _) => !machines.contains(id))
      ..addAll({
        for (final id in ids) id: status[id] ?? LabDeskPeerStatus.unknown,
      });

    return out;
  }

  /// Run a rule against its targets now, whatever its trigger says.
  ///
  /// This is the screen's "Run now", which exists so a rule can be tried
  /// without waiting for the condition it was written for. It ignores the
  /// trigger and the cooldown, because the operator asking for it is the
  /// condition, but it logs identically so the result shows up in the same
  /// place as a real firing.
  List<Firing> runNow({
    required String ruleId,
    required DateTime now,
    required Set<String> machines,
  }) {
    final rule = ruleById(ruleId);
    if (rule == null) return const [];
    final ids = machines.toList()..sort();
    return [for (final id in _targetsOf(rule, ids)) _emit(rule, id, now)];
  }

  Rule? ruleById(String id) {
    for (final r in _rules) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Record how a firing turned out. Passed straight through to the log so the
  /// caller has one object to talk to.
  void recordOutcome(String firingId, bool ok, [String? detail]) =>
      log.recordOutcome(firingId, ok, detail);

  // -------------------------------------------------------------------------

  Firing _emit(Rule rule, String machineId, DateTime at) {
    final firing = Firing(
      id: '${rule.id}:$machineId:${at.microsecondsSinceEpoch}:${_seq++}',
      rule: rule,
      machineId: machineId,
      action: rule.action,
      at: at,
    );
    log.add(firing);
    return firing;
  }

  List<String> _targetsOf(Rule rule, List<String> sortedIds) {
    if (rule.targetsAll) return sortedIds;
    return [
      for (final id in sortedIds)
        if (rule.targets.contains(id)) id,
    ];
  }

  bool _offlineFires(
    String key,
    String machineId,
    DateTime now,
    Map<String, LabDeskPeerStatus> status,
    int? forMinutes,
    bool baselining,
  ) {
    final since = _offlineSince[machineId];
    if (since == null) {
      _latched.remove(key);
      return false;
    }
    if (baselining) return false;
    if (forMinutes == null) {
      // The bare transition: fires on the tick the console saw it happen.
      return since == now;
    }
    if (_latched.contains(key)) return false;
    if (now.difference(since) < Duration(minutes: forMinutes)) return false;
    _latched.add(key);
    return true;
  }

  /// A condition that is either true or false right now, held for a while.
  ///
  /// Latched per episode: it fires once when the condition has held long
  /// enough and stays quiet until the condition goes false and comes back. A
  /// disk that is full stays full, and one alert an hour about it is a
  /// cooldown decision, not something the trigger should invent by itself.
  bool _levelFires(
    String key,
    DateTime now,
    bool? holds,
    int forMinutes,
    bool baselining,
  ) {
    if (holds != true) {
      // False, or nothing to read. Either way the run is over: an unmonitored
      // machine cannot be said to still be over its threshold.
      _trueSince.remove(key);
      _latched.remove(key);
      return false;
    }
    final since = _trueSince[key] ??= now;
    if (baselining) return false;
    if (_latched.contains(key)) return false;
    if (now.difference(since) < Duration(minutes: forMinutes)) return false;
    _latched.add(key);
    return true;
  }

  /// Whether a schedule rule is due on this tick, and bookkeeping for the next.
  ///
  /// Evaluated once per rule rather than per machine, so every target of one
  /// schedule fires on the same tick.
  bool _scheduleDue(Rule rule, DateTime now, bool baselining) {
    final t = rule.trigger;
    if (t is! Schedule) return false;

    if (t.isAtTime) {
      final slot = _slotFor(t, now);
      if (slot == null) return false;
      if (baselining) {
        // Whatever slot has already passed today is accounted for without
        // running it. This is the "no catch-up" rule.
        _lastSlot[rule.id] = slot;
        return false;
      }
      if (_lastSlot[rule.id] == slot) return false;
      _lastSlot[rule.id] = slot;
      return true;
    }

    final every = t.every!;
    if (baselining) {
      _nextDue[rule.id] = now.add(every);
      return false;
    }
    final next = _nextDue[rule.id];
    if (next == null) {
      _nextDue[rule.id] = now.add(every);
      return false;
    }
    if (now.isBefore(next)) return false;
    // From now, not from the slot that was missed: a console that was closed
    // for six hours owes one run, not twenty-four.
    _nextDue[rule.id] = now.add(every);
    return true;
  }

  /// Today's occurrence of a time-of-day schedule, or null when today is not
  /// one of its days or the time has not come round yet.
  DateTime? _slotFor(Schedule s, DateTime now) {
    if (s.weekdays.isNotEmpty && !s.weekdays.contains(now.weekday)) return null;
    final slot = DateTime(now.year, now.month, now.day, s.hour!, s.minute!);
    return now.isBefore(slot) ? null : slot;
  }

  double? _pctOf(List<Metric>? metrics, String label) {
    for (final m in metrics ?? const <Metric>[]) {
      if (m.label != label) continue;
      if (!m.isAvailable) return null;
      final r = m.ratio;
      if (r != null) return r * 100;
      return double.tryParse(m.value!);
    }
    return null;
  }

  /// Whole days of uptime, read back out of the probe's formatted figure.
  ///
  /// The metric carries "12d 3h" rather than a number of seconds, so anything
  /// under a day reads as zero. That is enough for a trigger whose threshold is
  /// in days, and it is honest about what the figure actually holds.
  int? _uptimeDaysOf(List<Metric>? metrics) {
    for (final m in metrics ?? const <Metric>[]) {
      if (m.label != 'Uptime') continue;
      if (!m.isAvailable) return null;
      final d = RegExp(r'(\d+)\s*d').firstMatch(m.value!);
      return d == null ? 0 : int.parse(d.group(1)!);
    }
    return null;
  }

  static String _key(String ruleId, String machineId) =>
      '$ruleId\u0000$machineId';

  static String _ruleOfKey(String key) => key.split('\u0000').first;
}

/// Lets a nullable measurement answer a comparison without losing the
/// difference between "false" and "there is no figure".
extension _NullableCompare<T> on T? {
  bool? let(bool Function(T) test) {
    final v = this;
    return v == null ? null : test(v);
  }
}

/// One thing the engine decided should happen.
class Firing {
  const Firing({
    required this.id,
    required this.rule,
    required this.machineId,
    required this.action,
    required this.at,
  });

  /// Unique per firing, and the handle the outcome is recorded against.
  final String id;

  final Rule rule;
  final String machineId;
  final AutomationAction action;
  final DateTime at;
}

/// One line in the log: what fired, against what, and how it went.
class RunLogEntry {
  const RunLogEntry({
    required this.firingId,
    required this.ruleId,
    required this.ruleName,
    required this.machineId,
    required this.action,
    required this.at,
    this.ok,
    this.detail,
  });

  final String firingId;
  final String ruleId;
  final String ruleName;
  final String machineId;
  final AutomationAction action;
  final DateTime at;

  /// Null while the caller has not said yet. Rendered as "running", never as a
  /// failure: an action still in flight is not one that went wrong.
  final bool? ok;

  final String? detail;

  RunLogEntry _with(bool ok, String? detail) => RunLogEntry(
        firingId: firingId,
        ruleId: ruleId,
        ruleName: ruleName,
        machineId: machineId,
        action: action,
        at: at,
        ok: ok,
        detail: detail,
      );
}

/// The last 200 firings, newest first.
///
/// Capped because this runs for as long as the console is open and an interval
/// rule can produce a line a minute. Two hundred is enough to answer "did that
/// rule run" without the list becoming the reason the console holds memory.
class RunLog {
  static const capacity = 200;

  final _entries = <RunLogEntry>[];

  List<RunLogEntry> get entries => List.unmodifiable(_entries);

  int get length => _entries.length;

  void add(Firing f) {
    _entries.insert(
      0,
      RunLogEntry(
        firingId: f.id,
        ruleId: f.rule.id,
        ruleName: f.rule.name,
        machineId: f.machineId,
        action: f.action,
        at: f.at,
      ),
    );
    if (_entries.length > capacity) {
      _entries.removeRange(capacity, _entries.length);
    }
  }

  /// Attach an outcome to a firing. A firing that has already aged out of the
  /// log is ignored rather than resurrected out of order.
  void recordOutcome(String firingId, bool ok, [String? detail]) {
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i].firingId == firingId) {
        _entries[i] = _entries[i]._with(ok, detail);
        return;
      }
    }
  }

  /// The most recent entry for a rule, for the "last fired" column.
  RunLogEntry? lastFor(String ruleId) {
    for (final e in _entries) {
      if (e.ruleId == ruleId) return e;
    }
    return null;
  }

  void clear() => _entries.clear();
}
