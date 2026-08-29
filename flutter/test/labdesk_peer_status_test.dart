import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common/labdesk_peer_status.dart';

void main() {
  group('LabDeskPeerStatusStore', () {
    late LabDeskPeerStatusStore store;

    setUp(() => store = LabDeskPeerStatusStore());

    test('a peer nobody has asked about is unknown, not offline', () {
      expect(store.stateOf('1').status, LabDeskPeerStatus.unknown);
      expect(store.stateOf('1').lastChecked, isNull);
      expect(store.stateOf('1').lastSeenOnline, isNull);
    });

    test('a response marks the peers it names and nothing else', () {
      store.applyResponse(onlines: ['1'], offlines: ['2'], at: _t(0));

      expect(store.stateOf('1').status, LabDeskPeerStatus.online);
      expect(store.stateOf('2').status, LabDeskPeerStatus.offline);
      // '3' was never in a response, so nothing is known about it.
      expect(store.stateOf('3').status, LabDeskPeerStatus.unknown);
    });

    test('a peer absent from a later response keeps its previous state', () {
      store.applyResponse(onlines: ['1'], offlines: ['2'], at: _t(0));
      // A response about other peers entirely must not silently flip '1'.
      store.applyResponse(onlines: ['9'], offlines: [], at: _t(60));

      expect(store.stateOf('1').status, LabDeskPeerStatus.online);
      expect(store.stateOf('1').lastChecked, _t(0),
          reason: 'lastChecked should only move when the peer was actually asked about');
      expect(store.stateOf('2').status, LabDeskPeerStatus.offline);
    });

    test('lastSeenOnline records the last time a peer answered, and never rewinds', () {
      store.applyResponse(onlines: ['1'], offlines: [], at: _t(0));
      expect(store.stateOf('1').lastSeenOnline, _t(0));

      store.applyResponse(onlines: [], offlines: ['1'], at: _t(60));
      expect(store.stateOf('1').status, LabDeskPeerStatus.offline);
      expect(store.stateOf('1').lastSeenOnline, _t(0),
          reason: 'going offline must not erase when it was last reachable');

      store.applyResponse(onlines: ['1'], offlines: [], at: _t(120));
      expect(store.stateOf('1').lastSeenOnline, _t(120));
    });

    test('a failed query leaves every peer exactly as it was', () {
      store.applyResponse(onlines: ['1'], offlines: ['2'], at: _t(0));
      store.beginQuery(['1', '2']);
      // The Rust side now returns an error instead of "everything offline", so
      // no response arrives at all. Nothing may change.
      store.endQuery();

      expect(store.stateOf('1').status, LabDeskPeerStatus.online);
      expect(store.stateOf('2').status, LabDeskPeerStatus.offline);
      expect(store.stateOf('1').lastChecked, _t(0));
    });

    test('querying reports in flight without destroying the known state', () {
      store.applyResponse(onlines: ['1'], offlines: [], at: _t(0));
      expect(store.isQuerying, isFalse);

      store.beginQuery(['1']);
      expect(store.isQuerying, isTrue);
      expect(store.isQueryingPeer('1'), isTrue);
      expect(store.stateOf('1').status, LabDeskPeerStatus.online,
          reason: 'a refresh must not blank the dot it is refreshing');

      store.applyResponse(onlines: ['1'], offlines: [], at: _t(30));
      store.endQuery();
      expect(store.isQuerying, isFalse);
      expect(store.isQueryingPeer('1'), isFalse);
    });

    test('forgetting a peer drops it back to unknown', () {
      store.applyResponse(onlines: ['1'], offlines: [], at: _t(0));
      store.forget('1');
      expect(store.stateOf('1').status, LabDeskPeerStatus.unknown);
    });

    test('empty id strings are ignored rather than stored', () {
      // The Rust side sends comma separated lists, so splitting an empty
      // string yields ['']. That must not become a tracked peer.
      store.applyResponse(onlines: [''], offlines: [''], at: _t(0));
      expect(store.trackedIds, isEmpty);
    });

    test('counts summarise the fleet without inventing offline machines', () {
      store.applyResponse(onlines: ['1', '2'], offlines: ['3'], at: _t(0));
      expect(store.countOf(LabDeskPeerStatus.online), 2);
      expect(store.countOf(LabDeskPeerStatus.offline), 1);
      expect(store.countOf(LabDeskPeerStatus.unknown), 0,
          reason: 'unknown is only counted for peers the store has been told about');
    });
  });
}

DateTime _t(int seconds) =>
    DateTime.utc(2026, 1, 1).add(Duration(seconds: seconds));
