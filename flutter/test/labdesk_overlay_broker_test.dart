import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/labdesk/services/overlay_broker.dart';

/// The labnet routes on lab-desk.net, spoken by a broker over a fake wire.
class _Wire {
  final calls = <({String method, String url, Map<String, String> headers, String? body})>[];
  int status = 200;
  Object reply = const {};
  Future<(int, String)> call(String method, Uri url, Map<String, String> headers, String? body) async {
    calls.add((method: method, url: url.toString(), headers: headers, body: body));
    return (status, jsonEncode(reply));
  }
}

void main() {
  var token = 'tok-1';
  _Wire wire = _Wire();
  OverlayBroker broker() => OverlayBroker(baseUrl: 'https://lab-desk.net', token: () => token, http: wire.call);
  setUp(() {
    token = 'tok-1';
    wire = _Wire();
  });

  test('every call carries the device token read at that moment', () async {
    wire.reply = {'setupKey': 'SK', 'managementUrl': 'https://nb.lab-desk.net'};
    final b = broker();
    await b.enrol();
    token = 'tok-2';
    await b.enrol();
    expect(wire.calls.map((c) => c.headers['authorization']), ['Bearer tok-1', 'Bearer tok-2']);
    expect(wire.calls.first.url, 'https://lab-desk.net/api/overlay/enrol');
    expect(wire.calls.first.method, 'POST');
  });

  test('a session grant carries the address and the id key', () async {
    wire.reply = {'id': 's1', 'targetAddr': '100.64.0.9:21118', 'targetIdPk': 'pk='};
    final g = await broker().session('1180573903');
    expect(g.id, 's1');
    expect(g.targetAddr, '100.64.0.9:21118');
    expect(g.targetIdPk, 'pk=');
    expect(jsonDecode(wire.calls.single.body!), {'target': '1180573903'});
  });

  test('a refusal surfaces the server\'s own sentence and whether to sign in again', () async {
    wire.status = 401;
    wire.reply = {'error': 'Unauthorized'};
    await expectLater(broker().session('1'), throwsA(isA<OverlayBrokerException>().having((e) => e.signInAgain, 'signInAgain', isTrue)));
    wire.status = 409;
    wire.reply = {'error': 'That machine has not come up on labnet yet.'};
    await expectLater(broker().session('1'), throwsA(isA<OverlayBrokerException>()
        .having((e) => e.message, 'message', 'That machine has not come up on labnet yet.')
        .having((e) => e.signInAgain, 'signInAgain', isFalse)));
  });

  test('ending a session never throws', () async {
    wire.status = 500;
    wire.reply = 'not json';
    await broker().endSession('s1');
    expect(wire.calls.single.method, 'DELETE');
    expect(wire.calls.single.url, endsWith('/api/overlay/session/s1'));
  });

  test('the inbox is read into invitations and labnets with their members', () async {
    wire.reply = {
      'device': {'enrolled': true, 'overlayIp': '100.64.0.3'},
      'invitations': [{'labnetId': 'L1', 'name': 'Office', 'invitedBy': 'owner@example.com'}],
      'labnets': [{'id': 'L2', 'name': 'Lab', 'fullAccess': true, 'owner': false,
        'members': [{'deviceId': '111', 'status': 'approved', 'overlayIp': '100.64.0.5'}, {'deviceId': '222', 'status': 'pending', 'overlayIp': null}]}],
    };
    final inbox = await broker().inbox();
    expect(inbox.enrolled, isTrue);
    expect(inbox.overlayIp, '100.64.0.3');
    expect(inbox.invitations.single.name, 'Office');
    expect(inbox.invitations.single.invitedBy, 'owner@example.com');
    final l = inbox.labnets.single;
    expect(l.fullAccess, isTrue);
    expect(l.owner, isFalse);
    expect(l.members.map((m) => m.approved), [true, false]);
    expect(l.members.last.overlayIp, isNull);
  });

  test('self report and the labnet actions hit their routes with the right bodies', () async {
    final b = broker();
    await b.reportSelf(overlayIp: '100.64.0.3', publicKey: 'wg=', idPk: 'id=', directPort: 21118);
    await b.setFullAccess('L1', true);
    await b.invite('L1', '333');
    await b.decide('L1', approve: false);
    await b.leave('L1');
    await b.removeMember('L1', '333');
    await b.revoke();
    expect(wire.calls.map((c) => '${c.method} ${Uri.parse(c.url).path}'), [
      'POST /api/overlay/self',
      'PATCH /api/overlay/labnets/L1',
      'POST /api/overlay/labnets/L1/invite',
      'POST /api/overlay/invites/L1/decide',
      'POST /api/overlay/labnets/L1/leave',
      'DELETE /api/overlay/labnets/L1/members/333',
      'DELETE /api/overlay/enrol',
    ]);
    expect(jsonDecode(wire.calls[0].body!), {'overlayIp': '100.64.0.3', 'publicKey': 'wg=', 'idPk': 'id=', 'directPort': 21118});
    expect(jsonDecode(wire.calls[1].body!), {'fullAccess': true});
    expect(jsonDecode(wire.calls[3].body!), {'approve': false});
  });
}
