/// What a session message box means to a headless machine link.
///
/// Returns the reason the link cannot become ready, or null when the box is
/// progress the link should keep waiting through. Pure, so it is testable
/// without the FFI layer; the link owns the wiring.
String? linkFailure(String type, String title, String text) {
  if (type.contains('error') || title == 'Connection Error') {
    return text.isEmpty ? (title.isEmpty ? 'connection error' : title) : text;
  }
  switch (type) {
    case 'input-password':
      return 'no password is saved for this machine';
    case 're-input-password':
      return 'the machine refused the saved password';
    case 'input-2fa':
      return 'the machine wants a 2FA code';
    case 'session-login':
    case 'session-re-login':
    case 'session-login-password':
    case 'terminal-admin-login':
    case 'terminal-admin-login-password':
      return 'the machine wants an OS login the console cannot give';
  }
  return null;
}
