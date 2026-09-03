import 'dart:convert';
import 'dart:io';

import '../models/labnet.dart';

/// One HTTP exchange: status code and body text. Injected so the broker can
/// be exercised without a network and run on `HttpClient` in the application.
typedef HttpCall = Future<(int, String)> Function(
    String method, Uri url, Map<String, String> headers, String? body);

/// What lab-desk.net answered when it refused.
class OverlayBrokerException implements Exception {
  const OverlayBrokerException(this.status, this.message);
  final int status;
  final String message;

  /// The device's sign-in no longer holds; the console asks for it again.
  bool get signInAgain => status == 401;

  @override
  String toString() => message;
}

class Enrolment {
  const Enrolment({required this.setupKey, required this.managementUrl});
  final String setupKey;
  final String managementUrl;
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

/// The labnet routes on lab-desk.net, spoken with the device's own sign-in
/// token, read afresh on every call so a re-sign-in is picked up at once.
class OverlayBroker {
  OverlayBroker({
    required this.baseUrl,
    required this.token,
    HttpCall? http,
  }) : _http = http ?? _httpClient;

  final String baseUrl;
  final String Function() token;
  final HttpCall _http;

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

  Future<Map<String, dynamic>> _call(String method, String path,
      [Map<String, dynamic>? body]) async {
    final headers = {
      'authorization': 'Bearer ${token()}',
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
    };
    final (status, text) = await _http(method, Uri.parse('$baseUrl$path'),
        headers, body == null ? null : jsonEncode(body));
    Map<String, dynamic> json = const {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {}
    if (status < 200 || status >= 300) {
      final message = json['error'];
      throw OverlayBrokerException(
          status, message is String && message.isNotEmpty ? message : 'lab-desk.net answered $status');
    }
    return json;
  }

  Future<Enrolment> enrol() async {
    final j = await _call('POST', '/api/overlay/enrol', {});
    return Enrolment(setupKey: '${j['setupKey']}', managementUrl: '${j['managementUrl']}');
  }

  Future<void> reportSelf({
    required String overlayIp,
    required String publicKey,
    required String idPk,
    required int directPort,
  }) =>
      _call('POST', '/api/overlay/self', {
        'overlayIp': overlayIp,
        'publicKey': publicKey,
        'idPk': idPk,
        'directPort': directPort,
      });

  Future<void> revoke() => _call('DELETE', '/api/overlay/enrol');

  Future<SessionGrant> session(String targetId) async {
    final j = await _call('POST', '/api/overlay/session', {'target': targetId});
    return SessionGrant(
        id: '${j['id']}', targetAddr: '${j['targetAddr']}', targetIdPk: '${j['targetIdPk']}');
  }

  /// Best effort: a session that is over is over whether or not the release
  /// lands; the server sweeps what a dead client leaves behind.
  Future<void> endSession(String id) async {
    try {
      await _call('DELETE', '/api/overlay/session/$id');
    } catch (_) {}
  }

  Future<LabnetInbox> inbox() async =>
      LabnetInbox.fromJson(await _call('GET', '/api/overlay/inbox'));

  Future<Labnet> createLabnet(String name) async {
    final j = await _call('POST', '/api/overlay/labnets', {'name': name});
    return Labnet(id: '${j['id']}', name: '${j['name']}', fullAccess: j['fullAccess'] == true, owner: true);
  }

  Future<void> setFullAccess(String id, bool on) =>
      _call('PATCH', '/api/overlay/labnets/$id', {'fullAccess': on});

  Future<void> deleteLabnet(String id) => _call('DELETE', '/api/overlay/labnets/$id');

  Future<void> invite(String labnetId, String deviceId) =>
      _call('POST', '/api/overlay/labnets/$labnetId/invite', {'deviceId': deviceId});

  Future<void> decide(String labnetId, {required bool approve}) =>
      _call('POST', '/api/overlay/invites/$labnetId/decide', {'approve': approve});

  Future<void> leave(String labnetId) => _call('POST', '/api/overlay/labnets/$labnetId/leave', {});

  Future<void> removeMember(String labnetId, String deviceId) =>
      _call('DELETE', '/api/overlay/labnets/$labnetId/members/$deviceId');
}
