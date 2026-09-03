import '../models/overlay_state.dart';
import 'overlay_broker.dart';
import 'overlay_daemon.dart';
import 'overlay_enrolment.dart' show OptionWriter, bareIp;

/// What the client is told before a session so it dials the overlay first.
const kOverlayAddrOption = 'labdesk-overlay-addr-';
const kOverlayPkOption = 'labdesk-overlay-pk-';

/// A session grant from lab-desk.net, from asking for it to releasing it.
///
/// `prepare` asks for the rule, waits until this machine's daemon reports the
/// target peer Connected (the rule has to be signalled and the WireGuard
/// handshake completed before a socket can cross), then writes the address
/// hint and the target's id key for the client. Anything short of that writes
/// nothing, and the session goes the way it always has.
///
/// `noteOpenSessions` is fed the ids of the sessions the console can see; a
/// granted id that has gone is released and its hints cleared.
class OverlaySession {
  OverlaySession({
    required this.broker,
    required this.daemon,
    required this.setOption,
    Future<void> Function(Duration) sleep = Future.delayed,
    this.readyTimeout = const Duration(seconds: 10),
  }) : _sleep = sleep;

  final OverlayBroker broker;
  final OverlayDaemon daemon;
  final OptionWriter setOption;
  final Duration readyTimeout;
  final Future<void> Function(Duration) _sleep;

  /// Granted sessions by peer id, and whether the console has seen each open.
  final _grants = <String, ({SessionGrant grant, bool seenOpen})>{};

  /// True when the client was handed the overlay address for [peerId].
  Future<bool> prepare(String peerId) async {
    final SessionGrant grant;
    try {
      grant = await broker.session(peerId);
    } catch (_) {
      return false;
    }
    final ip = bareIp(grant.targetAddr.split(':').first);
    var status = await daemon.status();
    var ready = status.peerAt(ip)?.connected ?? false;
    for (var i = 1; !ready && i < readyTimeout.inSeconds; i++) {
      await _sleep(const Duration(seconds: 1));
      status = await daemon.status();
      ready = status.peerAt(ip)?.connected ?? false;
    }
    if (!ready) {
      await broker.endSession(grant.id);
      return false;
    }
    await setOption('$kOverlayAddrOption$peerId', grant.targetAddr);
    await setOption('$kOverlayPkOption$peerId', grant.targetIdPk);
    _grants[peerId] = (grant: grant, seenOpen: false);
    return true;
  }

  /// The peer ids of sessions the console currently sees open.
  Future<void> noteOpenSessions(Iterable<String> open) async {
    final openSet = open.toSet();
    for (final id in _grants.keys.toList()) {
      final g = _grants[id]!;
      if (openSet.contains(id)) {
        _grants[id] = (grant: g.grant, seenOpen: true);
      } else if (g.seenOpen) {
        await release(id);
      }
    }
  }

  /// Ends the grant for [peerId] whether or not the session ever opened.
  Future<void> release(String peerId) async {
    final g = _grants.remove(peerId);
    if (g == null) return;
    await setOption('$kOverlayAddrOption$peerId', '');
    await setOption('$kOverlayPkOption$peerId', '');
    await broker.endSession(g.grant.id);
  }

  bool get hasGrants => _grants.isNotEmpty;

  /// The daemon state the last readiness check saw, for the screen if wanted.
  OverlayState? lastStatus;
}
