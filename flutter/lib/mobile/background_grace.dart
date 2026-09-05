/// When a backgrounded session should be closed rather than left open.
///
/// The phone must not hold a remote session open while it is in a pocket. The
/// far end has no way to tell a backgrounded phone from an attentive one, so
/// the machine keeps showing somebody connected to it, and on the phone's side
/// the session is one that nobody asked to keep.
///
/// A grace exists because switching apps for a moment is not leaving. Twenty
/// seconds covers looking something up and coming back; longer than that and
/// the session is being held rather than used.
///
/// Deliberately clock-free. It is handed the time it should reason about, so
/// the policy can be tested without waiting and so the two places that need it
/// can ask the same question. Those two places are different for a reason:
///
///  * While iOS still gives the app runtime after backgrounding, a timer set
///    for [remaining] fires and the session is closed properly, with a
///    disconnect the far end sees.
///  * If iOS suspends the process first, no timer fires at all. The elapsed
///    time is therefore checked again on the way back to the foreground, using
///    the wall clock, and a session that outlived its grace while suspended is
///    closed then rather than resumed.
class BackgroundGrace {
  BackgroundGrace({this.grace = const Duration(seconds: 20)});

  final Duration grace;

  DateTime? _since;

  bool get isBackgrounded => _since != null;

  void onBackground(DateTime at) => _since = at;

  void onForeground() => _since = null;

  /// Whether the session should be closed now.
  bool isDue(DateTime now) {
    final since = _since;
    if (since == null) return false;
    final elapsed = now.difference(since);
    // A clock that jumped backwards gives a negative elapsed time. That is not
    // a grace that has run out, and closing a live session over it would be a
    // bug the operator experiences as the app dropping them at random.
    if (elapsed.isNegative) return false;
    return elapsed >= grace;
  }

  /// How much of the grace is left, for setting a timer. Zero in the
  /// foreground, and zero once it has run out.
  Duration remaining(DateTime now) {
    final since = _since;
    if (since == null) return Duration.zero;
    final left = grace - now.difference(since);
    return left.isNegative ? Duration.zero : left;
  }
}
