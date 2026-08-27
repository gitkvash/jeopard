@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeopard_app/core/providers.dart';
import 'package:jeopard_app/core/rest_client.dart';
import 'package:jeopard_app/core/session.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/host/host_game_screen.dart';
import 'package:jeopard_app/role_screen.dart';
import 'package:jeopard_app/team/buzzer_screen.dart';

import 'resume_test.dart' show lobbySnapshot;

/// Leaving a game has to work from the state a *resumed* game leaves behind.
///
/// This is a regression test for a reported bug: the exit button popped the
/// navigator until the first route, which does nothing when the game screen is
/// itself the first route -- exactly what a reload produces, since resuming
/// replaces the home route. The button appeared dead.
void main() {
  Widget app(Widget home) {
    final client = MockClient((request) async => http.Response(
          jsonEncode(lobbySnapshot()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ));

    return ProviderScope(
      overrides: [
        restClientProvider.overrideWithValue(RestClient(client: client)),
      ],
      // No `home:` indirection and nothing pushed on top: the game screen is
      // the first and only route, as it is after a reload.
      child: MaterialApp(theme: buildTheme(), home: home),
    );
  }

  GameSession hostSession() => GameSession(
        gameId: 'g-1',
        joinCode: 'S6HG3F',
        isHost: true,
        savedAt: DateTime.now(),
        hostToken: 'host-tok',
      );

  GameSession playerSession() => GameSession(
        gameId: 'g-1',
        joinCode: 'S6HG3F',
        isHost: false,
        savedAt: DateTime.now(),
        playerId: 'p-1',
        playerToken: 'player-tok',
        playerName: 'ნინო',
        teamId: 't-1',
        teamName: 'მთიები',
      );

  /// Fixed pumps rather than `pumpAndSettle`: a lobby spinner and the buzzer's
  /// pulse never stop, so settling never happens.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.logout));
    await settle(tester);

    // The dialog asks first, and its confirm button carries the same label.
    expect(find.text(L.leaveGameHint), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, L.leaveGame).last);
    await settle(tester);
  }

  testWidgets('the host can leave a game that is the only route',
      (tester) async {
    await tester.pumpWidget(app(HostGameScreen(session: hostSession())));
    await tester.pump(const Duration(milliseconds: 20));

    await leave(tester);

    expect(find.byType(RoleScreen), findsOneWidget);
    expect(find.byType(HostGameScreen), findsNothing);
    expect(find.text(L.iAmHost), findsOneWidget);
  });

  testWidgets('a player can leave a game that is the only route',
      (tester) async {
    await tester.pumpWidget(app(BuzzerScreen(session: playerSession())));
    await tester.pump(const Duration(milliseconds: 20));

    await leave(tester);

    expect(find.byType(RoleScreen), findsOneWidget);
    expect(find.byType(BuzzerScreen), findsNothing);
  });

  testWidgets('cancelling leaves the game alone', (tester) async {
    await tester.pumpWidget(app(HostGameScreen(session: hostSession())));
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(find.byIcon(Icons.logout));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, L.cancel));
    await settle(tester);

    expect(find.byType(HostGameScreen), findsOneWidget);
    expect(find.byType(RoleScreen), findsNothing);
  });
}
