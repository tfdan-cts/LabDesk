import 'dart:convert';
import 'dart:io';

import '../models/labnet.dart';

/// One HTTP exchange: status code and body text. Injected so the broker can
/// be exercised without a network and run on `HttpClient` in the application.
typedef HttpCall = Future<(int, String)> Function(
    String method, Uri url, Map<String, String> headers, String? body);

/// Signs one machine-plane request and hands back the three headers
/// lab-desk.net reads, or null when this process cannot speak for the machine.
///
/// The client cannot do this itself: the agent key is kept where an
/// interactive user cannot read it (`src/labdesk/identity.rs`), so the
/// privileged LabDesk process signs on request over IPC
/// (`src/labdesk/labnet.rs`) and only the answer crosses. `main_agent_sign` in
/// `src/flutter_ffi.rs` is the implementation; it answers "" when nobody could
/// speak for the machine, which is what an unenrolled machine gets.
typedef MachineSigner = Future<MachineSignature?> Function(
    String method, String path, String body);

/// The three headers `agentAuth` reads on `/agent/*`
/// (`src/worker/agent-auth.ts`): the machine id it looks the key up by, the
/// timestamp it bounds replay with, and the detached Ed25519 signature over
/// the method, the path, that timestamp and the hash of the body.
class MachineSignature {
  const MachineSignature({
    required this.machine,
    required this.ts,
    required this.sig,
  });

  final String machine;
  final String ts;
  final String sig;

  /// What `main_agent_sign` answers: `{"machine","ts","sig"}`, and `""` when
  /// this process holds no machine credential. Anything short of all three is
  /// read as "cannot sign" rather than sent as a partial credential.
  static MachineSignature? decode(String json) {
    try {
      final j = jsonDecode(json);
      if (j is! Map) return null;
      final machine = j['machine'], ts = j['ts'], sig = j['sig'];
      if (machine is! String || ts is! String || sig is! String) return null;
      if (machine.isEmpty || ts.isEmpty || sig.isEmpty) return null;
      return MachineSignature(machine: machine, ts: ts, sig: sig);
    } catch (_) {
      return null;
    }
  }

  Map<String, String> get headers => {
        'x-ld-machine': machine,
        'x-ld-ts': ts,
        'x-ld-sig': sig,
      };
}

/// What lab-desk.net answered when it refused.
class OverlayBrokerException implements Exception {
  const OverlayBrokerException(this.status, this.message,
      {this.machinePlane = false});
  final int status;
  final String message;

  /// The call never left this machine: the console holds no agent key, so a
  /// machine-plane request was refused before any network was touched.
  bool get refusedHere => status == OverlayBroker._refusedHere;

  /// Whether the refusal came from the machine plane, where 401 means the
  /// signature was refused and has nothing to do with an account.
  final bool machinePlane;

  /// The device's sign-in no longer holds; the console asks for it again.
  bool get signInAgain => status == 401 && !machinePlane;

  @override
  String toString() => message;
}

class Enrolment {
  const Enrolment({required this.setupKey, required this.managementUrl});
  final String setupKey;
  final String managementUrl;
}

/// A machine as lab-desk.net holds it: the id every labnet route names it by,
/// the peer id the client knows the same machine as, and what to call it on
/// screen.
class OrgMachine {
  const OrgMachine({
    required this.id,
    required this.peerId,
    required this.name,
  });

  /// `machine.id`, minted by the Worker at `/agent/enrol`.
  final String id;

  /// `machine.peerId`, the id in the connect box.
  final String peerId;
  final String name;
}

class SessionGrant {
  const SessionGrant({
    required this.id,
    required this.targetAddr,
    required this.targetIdPk,
  });
  final String id;

  /// `ip:port` on the overlay.
  final String targetAddr;

  /// The target's own id public key, so the direct session still runs the
  /// key exchange the rendezvous path performs.
  final String targetIdPk;
}

/// The labnet routes on lab-desk.net.
///
/// They sit on TWO planes, and which plane a route is on decides what
/// authorizes it (plan section 0.4):
///
/// * The MACHINE plane, `/agent/overlay/*` (`src/worker/routes/agent-overlay.ts`).
///   lab-desk.net reads no `Authorization` header there at all: the caller is
///   whichever machine holds the secret half of `machine.agentPk`, proven by a
///   detached signature over the request. Every route on it acts on this
///   machine's own labnet identity, so nothing in the request names a machine
///   and there is nothing for a caller to choose.
/// * The HUMAN plane, `/api/overlay/*` (`src/worker/routes/overlay.ts`). Every
///   route calls `actor()`, which resolves the signed-in person and their
///   organization. These are the labnets an organization holds and the session
///   grant a technician opens.
///
/// ONE GAP, said rather than hidden. It is not closed in this file and not
/// papered over: a call that cannot be authorized is refused or left to the
/// server's own refusal rather than sent as something else.
///
/// * The HUMAN plane's credential does not resolve. The console holds the app
///   token `/api/login` mints (`bearerUser`, `src/worker/routes/client-api.ts`)
///   and `actor()` reads a Better Auth session, with no bearer plugin
///   registered (`src/worker/auth.ts`), so the token below names nobody and
///   those calls answer "Sign in first" until the Worker resolves an app token
///   into an actor. That is a Worker change, not a client one.
///
/// The MACHINE plane is signed for this process by the privileged LabDesk
/// process, which holds the agent key and answers over IPC (`main_agent_sign`,
/// `src/labdesk/labnet.rs`). [sign] answers null only when that process could
/// not speak for the machine, which is what a machine nobody has enrolled
/// gets, and every machine-plane call is then refused before the wire.
///
/// The human plane does not wait on the machine plane: everything an account
/// does to an organization's labnets is reachable with no agent key at all.
class OverlayBroker {
  OverlayBroker({
    required this.baseUrl,
    required this.token,
    this.sign = _noMachineKey,
    this.peerId = _noPeerId,
    this.machineIdOf = _asGiven,
    HttpCall? http,
  }) : _http = http ?? _httpClient;

  final String baseUrl;

  /// The account's own token, read afresh on every call so a re-sign-in is
  /// picked up at once.
  final String Function() token;

  /// The machine credential. A broker built without one speaks the human plane
  /// only, which is what a process that cannot read the agent key can do.
  final MachineSigner sign;

  /// This machine's own peer id: what the client calls it in the connect box
  /// and everywhere else it names a machine.
  final String Function() peerId;

  /// A peer id turned into the `machine.id` lab-desk.net names machines by,
  /// from the map [machines] reads. The default answers what it was given, for
  /// a caller that already holds machine ids.
  final String Function(String peerId) machineIdOf;

  final HttpCall _http;

  static Future<MachineSignature?> _noMachineKey(
          String method, String path, String body) async =>
      null;

  static String _noPeerId() => '';

  static String _asGiven(String peerId) => peerId;

  static List<Map> _rows(Object? v) =>
      v is List ? v.whereType<Map>().toList() : const [];

  static String _str(Object? v) => v is String ? v : '';

  /// What a machine with no credential of its own is told, before anything is
  /// sent: the machine plane would refuse it, and a doomed request every
  /// fifteen seconds is not a better answer than this one.
  static const _noKey =
      'This machine is not enrolled with an organization yet, so it cannot '
      'speak for itself on lab-desk.net. Enrol it under This machine.';

  /// The status on a refusal this client made itself, before any request. No
  /// HTTP status is 0, so a caller can tell one from anything a server said.
  static const _refusedHere = 0;

  static Future<(int, String)> _httpClient(
      String method, Uri url, Map<String, String> headers, String? body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.openUrl(method, url);
      headers.forEach(req.headers.set);
      if (body != null) req.write(body);
      final res = await req.close();
      return (res.statusCode, await res.transform(utf8.decoder).join());
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _send(String method, String path,
      Map<String, String> credential, String? body, bool machinePlane) async {
    final headers = {
      ...credential,
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
    };
    final (status, text) =
        await _http(method, Uri.parse('$baseUrl$path'), headers, body);
    Map<String, dynamic> json = const {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {}
    if (status < 200 || status >= 300) {
      final message = json['error'];
      throw OverlayBrokerException(
          status,
          message is String && message.isNotEmpty
              ? message
              : 'lab-desk.net answered $status',
          machinePlane: machinePlane);
    }
    return json;
  }

  /// A call on the human plane, carrying the account's token and no signature.
  Future<Map<String, dynamic>> _human(String method, String path,
          [Map<String, dynamic>? body]) =>
      _send(method, path, {'authorization': 'Bearer ${token()}'},
          body == null ? null : jsonEncode(body), false);

  /// A call on the machine plane, carrying the signature and no token.
  ///
  /// The body is encoded once and signed as the bytes that go on the wire: the
  /// server hashes what it received, so a body re-encoded between signing and
  /// sending would be refused.
  Future<Map<String, dynamic>> _machine(String method, String path,
      [Map<String, dynamic>? body]) async {
    final text = body == null ? null : jsonEncode(body);
    final signature = await sign(method, path, text ?? '');
    if (signature == null) {
      throw const OverlayBrokerException(_refusedHere, _noKey,
          machinePlane: true);
    }
    return _send(method, path, signature.headers, text, true);
  }

  Future<Enrolment> enrol() async {
    final j = await _machine('POST', '/agent/overlay/enrol', {});
    return Enrolment(
        setupKey: '${j['setupKey']}', managementUrl: '${j['managementUrl']}');
  }

  Future<void> reportSelf({
    required String overlayIp,
    required String publicKey,
    required String idPk,
    required int directPort,
  }) =>
      _machine('POST', '/agent/overlay/self', {
        'overlayIp': overlayIp,
        'publicKey': publicKey,
        'idPk': idPk,
        'directPort': directPort,
      });

  Future<void> revoke() => _machine('DELETE', '/agent/overlay/enrol');

  /// A one-way path to the machine the client knows as [targetPeerId].
  ///
  /// TWO ID DOMAINS MEET HERE, and this is the only place they may. The client
  /// names a machine by its peer id; every labnet route resolves a machine
  /// through `actor()` against `machine.id`, which the Worker minted at
  /// `/agent/enrol` and which no peer id is (`src/worker/routes/overlay.ts`).
  /// Both ends are mapped, the controlling one included: a device id in a
  /// request body is never an authorization subject, so naming this machine
  /// costs nothing and the server checks both against the caller's
  /// organization. An id [machineIdOf] does not hold is sent empty rather than
  /// as a peer id, because a machine lab-desk.net cannot name is one it must
  /// refuse.
  Future<SessionGrant> session(String targetPeerId) async {
    final j = await _human('POST', '/api/overlay/session', {
      'controller': machineIdOf(peerId()),
      'target': machineIdOf(targetPeerId),
    });
    return SessionGrant(
        id: '${j['id']}',
        targetAddr: '${j['targetAddr']}',
        targetIdPk: '${j['targetIdPk']}');
  }

  /// Best effort: a session that is over is over whether or not the release
  /// lands; the server sweeps what a dead client leaves behind.
  Future<void> endSession(String id) async {
    try {
      await _human('DELETE', '/api/overlay/session/$id');
    } catch (_) {}
  }

  /// The organization's machines (`GET /api/org/machines`,
  /// `src/worker/routes/org.ts`), narrowed by the server to the caller's org
  /// and fleets. It is the only route on which `machine.id` and the peer id
  /// appear together, so it is both the map [machineIdOf] is built from and the
  /// console's own list of the machines an account may invite.
  Future<List<OrgMachine>> machines() async {
    final j = await _human('GET', '/api/org/machines');
    return [
      for (final m in _rows(j['machines']))
        OrgMachine(
          id: _str(m['id']),
          peerId: _str(m['peerId']),
          name: _str(m['displayName']).isNotEmpty
              ? _str(m['displayName'])
              : _str(m['hostname']),
        ),
    ];
  }

  /// What the Network section shows, read off BOTH planes because the two
  /// halves belong to two different subjects.
  ///
  /// * This machine's own standing and the invitations waiting on it come from
  ///   `GET /agent/overlay/inbox`, which answers for the machine that signed
  ///   and for no other (`src/worker/routes/agent-overlay.ts`).
  /// * The labnets come from `GET /api/overlay/labnets`, the route that
  ///   replaced the old console inbox (`src/worker/routes/overlay.ts`). It
  ///   answers the ORGANIZATION's labnets, which is what the person managing
  ///   them is looking at. The machine plane's own list is deliberately not
  ///   read: it holds only labnets this machine has joined, so a labnet just
  ///   created, or one whose members are still deciding, would be missing from
  ///   the screen of the technician who made it.
  ///
  /// The keys are the Worker's, not the client's: a member is `machineId` and
  /// there is no `owner` on either route.
  Future<LabnetInbox> inbox() async {
    final mine = await _mine();
    final theirs = await _human('GET', '/api/overlay/labnets');
    final device = mine['device'] is Map ? mine['device'] as Map : const {};
    return LabnetInbox(
      enrolled: device['enrolled'] == true,
      overlayIp:
          device['overlayIp'] is String ? device['overlayIp'] as String : null,
      invitations: [
        for (final i in _rows(mine['invitations']))
          LabnetInvitation(
            labnetId: _str(i['labnetId']),
            name: _str(i['name']),
            invitedBy: _str(i['invitedBy']),
          ),
      ],
      labnets: [
        for (final l in _rows(theirs['labnets']))
          Labnet(
            id: _str(l['id']),
            name: _str(l['name']),
            fullAccess: l['fullAccess'] == true,
            // Every labnet this route answers is one the same caller may
            // manage: it is scoped to their organization and narrowed to their
            // fleets by the predicate `ownedLabnet` applies to every write
            // (`narrowed`, src/worker/routes/overlay.ts). What their role may
            // then do with it is `rule:write`, which the server checks on each
            // call and this client does not model.
            owner: true,
            members: [
              for (final m in _rows(l['members']))
                LabnetMember(
                  deviceId: _str(m['machineId']),
                  status: _str(m['status']),
                  overlayIp:
                      m['overlayIp'] is String ? m['overlayIp'] as String : null,
                ),
            ],
          ),
      ],
    );
  }

  /// This machine's own half of the inbox, or nothing at all when this process
  /// holds no machine credential.
  ///
  /// A machine with no key is certainly not enrolled and has no invitation
  /// waiting, and the labnets the account manages are still worth showing, so
  /// the one refusal this client makes for itself is not raised. Every answer
  /// the server actually gave is.
  Future<Map<String, dynamic>> _mine() async {
    try {
      return await _machine('GET', '/agent/overlay/inbox');
    } on OverlayBrokerException catch (e) {
      if (e.status == _refusedHere) return const {};
      rethrow;
    }
  }

  Future<Labnet> createLabnet(String name) async {
    final j = await _human('POST', '/api/overlay/labnets', {'name': name});
    return Labnet(
        id: '${j['id']}',
        name: '${j['name']}',
        fullAccess: j['fullAccess'] == true,
        owner: true);
  }

  Future<void> setFullAccess(String id, bool on) =>
      _human('PATCH', '/api/overlay/labnets/$id', {'fullAccess': on});

  Future<void> deleteLabnet(String id) =>
      _human('DELETE', '/api/overlay/labnets/$id');

  /// [machineId] is a `machine.id`, which is what `actor()` resolves the
  /// invited machine against, and it is what [machines] hands the console to
  /// offer. A peer id here is answered "No such machine."
  Future<void> invite(String labnetId, String machineId) =>
      _human('POST', '/api/overlay/labnets/$labnetId/invite',
          {'machine': machineId});

  /// The invited machine decides for itself, which is why this is on the
  /// machine plane: the owner who sent the invitation holds a console
  /// credential, and a console credential answering for a machine is exactly
  /// what plan section 0.4 removes.
  Future<void> decide(String labnetId, {required bool approve}) =>
      _machine('POST', '/agent/overlay/invites/$labnetId/decide',
          {'approve': approve});

  Future<void> leave(String labnetId) =>
      _machine('POST', '/agent/overlay/labnets/$labnetId/leave', {});

  /// [machineId] is a `machine.id`, the same id the member came back as.
  Future<void> removeMember(String labnetId, String machineId) =>
      _human('DELETE', '/api/overlay/labnets/$labnetId/members/$machineId');
}
