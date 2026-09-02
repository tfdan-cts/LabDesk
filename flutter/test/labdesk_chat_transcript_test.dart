import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/labdesk/models/chat_transcript.dart';

/// The transcript is the only thing that crosses the window channel between a
/// session and the console, so both ends read the same conversation. A field
/// lost in the round trip is a message the operator never sees.
void main() {
  final at = DateTime.utc(2026, 9, 1, 14, 5, 30);

  SessionChat sample() => SessionChat(
        id: '1180573903',
        peerLabel: 'homebox-devserver',
        direction: SessionDirection.outgoing,
        lines: [
          ChatLine(from: ChatFrom.mine, text: 'rebooting the box', at: at),
          ChatLine(
              from: ChatFrom.peer,
              text: 'go ahead',
              at: at.add(const Duration(seconds: 12))),
        ],
      );

  group('round trip', () {
    test('a transcript survives the channel unchanged', () {
      final back = decodeSessionChat(encodeSessionChat(sample()))!;

      expect(back.id, '1180573903');
      expect(back.peerLabel, 'homebox-devserver');
      expect(back.direction, SessionDirection.outgoing);
      expect(back.lines.length, 2);
      expect(back.lines.first.from, ChatFrom.mine);
      expect(back.lines.first.text, 'rebooting the box');
      expect(back.lines.first.at, at);
      expect(back.lines.last.from, ChatFrom.peer);
    });

    test('an incoming session keeps its direction', () {
      final chat = SessionChat(
        id: '7',
        peerLabel: 'a caller',
        direction: SessionDirection.incoming,
      );
      final back = decodeSessionChat(encodeSessionChat(chat))!;
      expect(back.direction, SessionDirection.incoming);
      expect(back.isOutgoing, isFalse);
      expect(back.lines, isEmpty);
    });
  });

  group('decoding what a window actually answers', () {
    test('a closed window answers nothing, and that is not a crash', () {
      expect(decodeSessionChat(null), isNull);
      expect(decodeSessionChat(''), isNull);
      expect(decodeSessionChat(42), isNull);
      expect(decodeSessionChat('not json'), isNull);
      expect(decodeSessionChat('[1,2]'), isNull);
    });

    test('a line missing its fields reads as an empty peer line, not an error',
        () {
      final chat = decodeSessionChat('{"id":"5","lines":[{}]}')!;
      expect(chat.id, '5');
      // No label was sent, so the id is what the operator is shown.
      expect(chat.peerLabel, '5');
      expect(chat.direction, SessionDirection.outgoing);
      expect(chat.lines.single.text, '');
      expect(chat.lines.single.from, ChatFrom.peer);
    });
  });

  group('mergeSessionChats', () {
    test('outgoing sessions come before incoming, then by label', () {
      final merged = mergeSessionChats([
        const SessionChat(
            id: '3', peerLabel: 'zeta', direction: SessionDirection.incoming),
        const SessionChat(
            id: '2', peerLabel: 'Beta', direction: SessionDirection.outgoing),
        const SessionChat(
            id: '1', peerLabel: 'alpha', direction: SessionDirection.outgoing),
      ]);

      expect(merged.map((s) => s.peerLabel), ['alpha', 'Beta', 'zeta']);
    });

    test('an id answered for twice keeps the fuller transcript', () {
      final thin = SessionChat(
        id: '1',
        peerLabel: 'a',
        direction: SessionDirection.outgoing,
        lines: [ChatLine(from: ChatFrom.mine, text: 'one', at: at)],
      );
      final full = thin.copyWith(lines: [
        ...thin.lines,
        ChatLine(from: ChatFrom.peer, text: 'two', at: at),
      ]);

      expect(mergeSessionChats([full, thin]).single.lines.length, 2);
      expect(mergeSessionChats([thin, full]).single.lines.length, 2);
    });

    test('the same id in both directions is two sessions, not one', () {
      final merged = mergeSessionChats([
        const SessionChat(
            id: '1', peerLabel: 'a', direction: SessionDirection.outgoing),
        const SessionChat(
            id: '1', peerLabel: 'a', direction: SessionDirection.incoming),
      ]);
      expect(merged.length, 2);
    });
  });
}
