@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jeopard_app/core/models.dart';
import 'package:jeopard_app/core/session.dart';
import 'package:jeopard_app/core/session_store.dart';

/// A browser reload throws away every bit of Dart state, so the only thing
/// standing between F5 and a lost game is this record surviving it.
void main() {
  CreatedGame created({bool hostPlays = false}) => CreatedGame(
        gameId: 'g-1',
        joinCode: 'ABC234',
        hostToken: 'host-tok',
        hostTeamId: hostPlays ? 't-host' : null,
        hostPlayerId: hostPlays ? 'p-host' : null,
        hostPlayerToken: hostPlays ? 'p-tok' : null,
      );

  JoinedPlayer joined() => JoinedPlayer(
        gameId: 'g-1',
        playerId: 'p-9',
        playerToken: 'player-tok',
        playerName: 'ნინო',
        teamId: 't-2',
        teamName: 'მთიები',
        seat: 2,
      );

  group('GameSession', () {
    test('a created game keeps the host token, which is what drives the game',
        () {
      final session = GameSession.fromCreated(created());
      expect(session.isHost, isTrue);
      expect(session.hostToken, 'host-tok');
      expect(session.joinCode, 'ABC234');
      expect(session.isUsable, isTrue);
    });

    test('a host that also plays keeps its own team and player token', () {
      final session = GameSession.fromCreated(created(hostPlays: true));
      expect(session.hostTeamId, 't-host');
      expect(session.playerToken, 'p-tok');
    });

    test('a joined player keeps the player token, not a team token', () {
      final session = GameSession.fromJoined(joined(), joinCode: 'ABC234');
      expect(session.isHost, isFalse);
      expect(session.playerToken, 'player-tok');
      expect(session.teamId, 't-2');
      expect(session.teamName, 'მთიები');
      expect(session.playerName, 'ნინო');
      expect(session.seat, 2);
      expect(session.isUsable, isTrue);
    });

    test('survives a round trip through storage', () {
      final before = GameSession.fromJoined(joined(), joinCode: 'ABC234');
      final after = GameSession.decode(before.encode())!;

      expect(after.gameId, before.gameId);
      expect(after.joinCode, before.joinCode);
      expect(after.isHost, before.isHost);
      expect(after.playerToken, before.playerToken);
      expect(after.teamId, before.teamId);
      expect(after.playerName, before.playerName);
      expect(after.savedAt.toIso8601String(),
          before.savedAt.toIso8601String());
    });

    test('renew moves the timestamp without touching the identity', () {
      final old = GameSession.fromCreated(
        created(),
        at: DateTime.now().subtract(const Duration(hours: 5)),
      );
      final renewed = old.renew();

      expect(renewed.savedAt.isAfter(old.savedAt), isTrue);
      expect(renewed.gameId, old.gameId);
      expect(renewed.hostToken, old.hostToken);
      expect(renewed.isHost, old.isHost);
    });

    test('a record with no usable token is refused rather than half-restored',
        () {
      // Host with no host token: it could rejoin and then fail on every action.
      final noToken = GameSession(
        gameId: 'g-1',
        joinCode: 'ABC234',
        isHost: true,
        savedAt: DateTime.now(),
      );
      expect(noToken.isUsable, isFalse);
      expect(GameSession.decode(noToken.encode()), isNull);
    });

    test('garbage in storage is treated as no session at all', () {
      expect(GameSession.decode(''), isNull);
      expect(GameSession.decode('not json'), isNull);
      expect(GameSession.decode('[]'), isNull);
      expect(GameSession.decode('{"joinCode":"ABC234"}'), isNull);
    });
  });

  group('SessionStore', () {
    test('reads back nothing off the web, where there is no localStorage', () {
      // The stub implementation is deliberate: a native app is not reloaded out
      // from under itself, and a key-value plugin would drag native code into a
      // project that has none.
      SessionStore.write(GameSession.fromJoined(joined(), joinCode: 'ABC234'));
      expect(SessionStore.read(), isNull);
    });

    test('the age limit is short enough that a stale token is not offered', () {
      expect(SessionStore.maxAge.inHours, lessThanOrEqualTo(24));
    });
  });
}
