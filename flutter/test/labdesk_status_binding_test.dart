import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common/labdesk_peer_status.dart';
import 'package:flutter_hbb/common/labdesk_status_binding.dart';

/// The binding is what the real client calls. It is kept free of FFI and of
/// peer_model so it stays testable outside CI, where the generated bridge does
/// not exist.
void main() {
  group('LabDeskStatusBinding', () {
    late LabDeskPeerStatusStore store;
    late LabDeskStatusBinding binding;

    setUp(() {
      store = LabDeskPeerStatusStore();
      binding = LabDeskStatusBinding(store);
    });

    test('parses the comma separated lists the client sends', () {
      binding.onOnlineStateEvent(
        onlines: '101,102',
        offlines: '201',
        at: _t(0),
      );

      expect(store.stateOf('101').status, LabDeskPeerStatus.online);
      expect(store.stateOf('102').status, LabDeskPeerStatus.online);
      expect(store.stateOf('201').status, LabDeskPeerStatus.offline);
    });

    test('an empty list is not a peer', () {
      // Splitting '' yields [''], which must not become a tracked machine.
      binding.onOnlineStateEvent(onlines: '', offlines: '', at: _t(0));
      expect(store.trackedIds, isEmpty);
    });

    test('whitespace around ids is tolerated', () {
      binding.onOnlineStateEvent(onlines: ' 101 , 102 ', offlines: '', at: _t(0));
      expect(store.stateOf('101').status, LabDeskPeerStatus.online);
      expect(store.stateOf('102').status, LabDeskPeerStatus.online);
    });

    test('a query that never answers leaves the previous state alone', () {
      binding.onOnlineStateEvent(onlines: '101', offlines: '202', at: _t(0));
      binding.beginQuery(['101', '202']);
      expect(binding.isQuerying, isTrue);

      // The Rust side now returns an error rather than "everything offline",
      // so no event arrives at all. The timeout must not invent a result.
      binding.onQueryFailedOrTimedOut();

      expect(binding.isQuerying, isFalse);
      expect(store.stateOf('101').status, LabDeskPeerStatus.online);
      expect(store.stateOf('202').status, LabDeskPeerStatus.offline);
    });

    test('history records one slot per check, oldest first, capped', () {
      for (var i = 0; i < LabDeskStatusBinding.historyLength + 4; i++) {
        binding.onOnlineStateEvent(
          onlines: i.isEven ? '101' : '',
          offlines: i.isEven ? '' : '101',
          at: _t(i * 30),
        );
      }
      final h = binding.historyOf('101');
      expect(h.length, LabDeskStatusBinding.historyLength);
      // The last recorded check is the most recent one, which was odd -> down.
      expect(h.last, isFalse);
    });

    test('history only records machines the response named', () {
      binding.onOnlineStateEvent(onlines: '101', offlines: '', at: _t(0));
      binding.onOnlineStateEvent(onlines: '999', offlines: '', at: _t(30));

      // '101' was not in the second response, so it gains no second slot.
      expect(binding.historyOf('101').length, 1);
      expect(binding.historyOf('999').length, 1);
    });

    test('a fleet sample is recorded per response for the session chart', () {
      binding.onOnlineStateEvent(onlines: '1,2,3', offlines: '4', at: _t(0));
      binding.onOnlineStateEvent(onlines: '1,2', offlines: '3,4', at: _t(30));

      expect(binding.samples.length, 2);
      expect(binding.samples.first.online, 3);
      expect(binding.samples.first.total, 4);
      expect(binding.samples.last.online, 2);
      expect(binding.samples.last.total, 4);
    });

    test('forgetting a machine clears its history too', () {
      binding.onOnlineStateEvent(onlines: '101', offlines: '', at: _t(0));
      binding.forget('101');
      expect(binding.historyOf('101'), isEmpty);
      expect(store.stateOf('101').status, LabDeskPeerStatus.unknown);
    });
  });
}

DateTime _t(int seconds) => DateTime.utc(2026, 1, 1).add(Duration(seconds: seconds));
