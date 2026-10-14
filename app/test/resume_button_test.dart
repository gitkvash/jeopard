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
import 'package:jeopard_app/core/session_store.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/host/host_game_screen.dart';
import 'package:jeopard_app/role_screen.dart';
import 'package:jeopard_app/team/buzzer_screen.dart';
import 'package:jeopard_app/team/join_screen.dart';

import 'resume_test.dart' show lobbySnapshot;

void main() {
  setUp(() {
    SessionStore.debugKeepInMemory = true;
    SessionStore.clear();
  });

  tearDown(() {
    SessionStore.clear();
    SessionStore.debugKeepInMemory = false;
  });

  GameSession playerSession({String gameId = 'g-1', String code = 'S6HG3F'}) =>
      GameSession(
        gameId: gameId,
        joinCode: code,
        isHost: false,
        savedAt: DateTime.now(),
        playerId: 'p-1',
        playerToken: 'player-tok',
        playerName: 'ნინო',
        teamId: 't-1',
        teamName: 'მთიები',
      );

  GameSession hostSession({String gameId = 'g-1', String code = 'S6HG3F'}) =>
      GameSession(
        gameId: gameId,
        joinCode: code,
        isHost: true,
        savedAt: DateTime.now(),
        hostToken: 'host-tok',
      );

  Widget testApp({
    http.Client? client,
    Widget home = const RoleScreen(),
  }) {
    return ProviderScope(
      overrides: [
        if (client != null)
          restClientProvider.overrideWithValue(RestClient(client: client)),
      ],
      child: MaterialApp(
        theme: buildTheme(),
        home: home,
      ),
    );
  }

  testWidgets('RoleScreen shows return card when session is in SessionStore',
      (tester) async {
    SessionStore.write(playerSession());

    await tester.pumpWidget(testApp());
    await tester.pumpAndSettle();

    expect(find.text(L.returnToGame), findsOneWidget);
    expect(find.textContaining('ნინო · მთიები · კოდი: S6HG3F'), findsOneWidget);
    expect(find.text(L.iAmHost), findsOneWidget);
    expect(find.text(L.iAmPlayer), findsOneWidget);
  });

  testWidgets('tapping return card navigates into BuzzerScreen',
      (tester) async {
    SessionStore.write(playerSession());

    final client = MockClient((request) async {
      if (request.url.path == '/api/games/g-1') {
        return http.Response(
          jsonEncode(lobbySnapshot()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(testApp(client: client));
    await tester.pumpAndSettle();

    expect(find.text(L.returnToGame), findsOneWidget);
    await tester.tap(find.text(L.returnToGame));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(BuzzerScreen), findsOneWidget);
  });

  testWidgets('tapping return card for host session navigates into HostGameScreen',
      (tester) async {
    SessionStore.write(hostSession());

    final client = MockClient((request) async {
      if (request.url.path == '/api/games/g-1') {
        return http.Response(
          jsonEncode(lobbySnapshot()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(testApp(client: client));
    await tester.pumpAndSettle();

    expect(find.text(L.returnToGame), findsOneWidget);
    await tester.tap(find.text(L.returnToGame));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(HostGameScreen), findsOneWidget);
  });

  testWidgets('dismissing return card clears session and calls leavePlayer',
      (tester) async {
    SessionStore.write(playerSession());
    var leaveCalled = false;

    final client = MockClient((request) async {
      if (request.url.path == '/api/games/g-1/leave') {
        leaveCalled = true;
        return http.Response('', 204);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(testApp(client: client));
    await tester.pumpAndSettle();

    expect(find.text(L.returnToGame), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(leaveCalled, isTrue);
    expect(SessionStore.read(), isNull);
    expect(find.text(L.returnToGame), findsNothing);
  });

  testWidgets('host closing the return card asks first and deletes only on confirm',
      (tester) async {
    SessionStore.write(hostSession());
    var deleteCalled = false;

    final client = MockClient((request) async {
      if (request.method == 'DELETE' && request.url.path == '/api/games/g-1') {
        deleteCalled = true;
        return http.Response('', 204);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(testApp(client: client));
    await tester.pumpAndSettle();

    // Cancel: nothing is deleted and the card stays.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text(L.endGameConfirmMessage), findsOneWidget);
    await tester.tap(find.text(L.cancel));
    await tester.pumpAndSettle();
    expect(deleteCalled, isFalse);
    expect(SessionStore.read(), isNotNull);
    expect(find.text(L.returnToGame), findsOneWidget);

    // Confirm: the game is deleted and the card goes away.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text(L.endGameAction));
    await tester.pumpAndSettle();
    expect(deleteCalled, isTrue);
    expect(SessionStore.read(), isNull);
    expect(find.text(L.returnToGame), findsNothing);
  });

  testWidgets('joining a new game disconnects from old game', (tester) async {
    SessionStore.write(playerSession(gameId: 'old-g', code: 'OLDCOD'));
    var oldLeaveCalled = false;

    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/api/games/old-g/leave') {
        oldLeaveCalled = true;
        return http.Response('', 204);
      }
      if (request.method == 'POST' && request.url.path == '/api/games/NEWCOD/players') {
        return http.Response(
          jsonEncode({
            'gameId': 'new-g',
            'playerId': 'new-p',
            'playerToken': 'new-tok',
            'playerName': 'გიო',
            'teamId': 'new-t',
            'teamName': 'ლომები',
            'seat': 1,
            'solo': false,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.method == 'GET' && request.url.path == '/api/games/NEWCOD/lobby') {
        return http.Response(
          jsonEncode({
            'gameId': 'new-g',
            'joinCode': 'NEWCOD',
            'state': 'LOBBY',
            'teams': [],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(
        jsonEncode(lobbySnapshot()),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    await tester.pumpWidget(testApp(client: client, home: const JoinScreen()));
    await tester.pumpAndSettle();

    // Enter join code and name
    await tester.enterText(find.byType(TextField).first, 'NEWCOD');
    await tester.enterText(find.byType(TextField).last, 'გიო');
    await tester.pumpAndSettle();

    // Tap proceed button
    await tester.tap(find.widgetWithText(FilledButton, L.next2));
    await tester.pumpAndSettle();

    // In step 2, tap join solo
    await tester.tap(find.text(L.playSolo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(oldLeaveCalled, isTrue);
    expect(SessionStore.read()?.gameId, 'new-g');
    expect(find.byType(BuzzerScreen), findsOneWidget);
  });
}
