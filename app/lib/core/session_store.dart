import 'session.dart';
import 'session_store_stub.dart'
    if (dart.library.js_interop) 'session_store_web.dart';

/// Where the current [GameSession] is kept across a restart of the app.
///
/// On the web this is `localStorage`, and it is the thing that makes F5
/// harmless: the page reloads, Dart state is gone, and the session is read back
/// before the first frame so the game is rejoined rather than restarted.
///
/// Elsewhere it is a no-op. A native app is not reloaded out from under itself,
/// and a real key-value plugin would drag native code into a project that
/// deliberately has none (see the font note in pubspec.yaml).
class SessionStore {
  const SessionStore._();

  static const _key = 'jeopard.session.v1';

  /// Long enough to survive a reload, a dropped connection or a phone locking
  /// itself; short enough that a stale token is not offered up days later.
  static const maxAge = Duration(hours: 12);

  /// Synchronous on purpose: the app decides which screen to build on the very
  /// first frame, so there is nothing to wait for.
  static GameSession? read() {
    final raw = readRaw(_key);
    if (raw == null || raw.isEmpty) return null;
    final session = GameSession.decode(raw);
    if (session == null) {
      clear();
      return null;
    }
    if (DateTime.now().difference(session.savedAt) > maxAge) {
      clear();
      return null;
    }
    return session;
  }

  static void write(GameSession session) => writeRaw(_key, session.encode());

  static void clear() => removeRaw(_key);
}
