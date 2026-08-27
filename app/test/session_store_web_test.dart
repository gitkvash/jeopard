@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jeopard_app/core/session.dart';
import 'package:jeopard_app/core/session_store.dart';

/// The half of [SessionStore] that only exists on the web, exercised where it
/// actually runs:
///
///     flutter test --platform chrome test/session_store_web_test.dart
///
/// The VM suite asserts the opposite (a no-op stub), so this file is the only
/// place the real localStorage path is covered.
void main() {
  setUp(SessionStore.clear);
  tearDown(SessionStore.clear);

  GameSession session({DateTime? at}) => GameSession(
        gameId: 'g-1',
        joinCode: 'S6HG3F',
        isHost: true,
        savedAt: at ?? DateTime.now(),
        hostToken: 'host-tok',
      );

  test('a written session is read back', () {
    SessionStore.write(session());

    final restored = SessionStore.read();
    expect(restored, isNotNull);
    expect(restored!.gameId, 'g-1');
    expect(restored.joinCode, 'S6HG3F');
    expect(restored.isHost, isTrue);
    expect(restored.hostToken, 'host-tok');
  });

  test('an overwritten session replaces the old one', () {
    final old = DateTime.now().subtract(const Duration(hours: 3));
    SessionStore.write(session(at: old));
    expect(SessionStore.read()!.savedAt.difference(old).inSeconds, 0);

    SessionStore.write(session().renew());
    final renewed = SessionStore.read()!;
    expect(renewed.savedAt.isAfter(old), isTrue);
  });

  test('nothing is read back after clear', () {
    SessionStore.write(session());
    SessionStore.clear();
    expect(SessionStore.read(), isNull);
  });

  test('a session older than the age limit is dropped, not offered', () {
    SessionStore.write(
      session(at: DateTime.now().subtract(SessionStore.maxAge * 2)),
    );
    expect(SessionStore.read(), isNull);
  });
}
