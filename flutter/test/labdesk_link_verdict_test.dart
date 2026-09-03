import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/labdesk/services/link_verdict.dart';

/// What a headless machine link does with a session message box.
///
/// A link has no window and nobody watching it, so a dialog the client would
/// normally raise must become one of two things: a reason the link failed,
/// which the console prints, or nothing, because the session is still
/// connecting. It must never become a dialog in the main window: the buttons
/// on those dialogs close the current tab, and in the main window the current
/// tab is the application.
void main() {
  group('linkFailure', () {
    test('a connection error is the failure reason, verbatim', () {
      expect(linkFailure('error', 'Connection Error', 'ID does not exist'),
          'ID does not exist');
      expect(
          linkFailure('error', 'Connection Error',
              'Failed to connect to rendezvous server'),
          'Failed to connect to rendezvous server');
    });

    test('any error-typed box fails the link', () {
      expect(linkFailure('custom-error', '', 'Offline'), 'Offline');
    });

    test('password prompts fail the link, saying which', () {
      expect(linkFailure('input-password', 'Password Required', ''),
          contains('no password'));
      expect(linkFailure('re-input-password', 'Wrong Password', ''),
          contains('refused'));
    });

    test('prompts nobody can answer fail the link', () {
      expect(linkFailure('input-2fa', '', ''), isNotNull);
      expect(linkFailure('session-login', '', ''), isNotNull);
      expect(linkFailure('terminal-admin-login-password', '', ''), isNotNull);
    });

    test('progress and success are not failures', () {
      expect(linkFailure('connecting', 'Connecting...', ''), isNull);
      expect(linkFailure('success', 'Connected', ''), isNull);
      expect(linkFailure('wait-remote-accept-nook', '', ''), isNull);
    });
  });
}
