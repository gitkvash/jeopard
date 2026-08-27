import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeopard_app/core/providers.dart';
import 'package:jeopard_app/core/rest_client.dart';
import 'package:jeopard_app/core/session.dart';
import 'package:jeopard_app/host/host_game_screen.dart';
import 'package:jeopard_app/main.dart';
import 'package:jeopard_app/team/buzzer_screen.dart';

/// The reload path, end to end from the stored record: fetch the snapshot, then
/// walk back into the console this device was using.
Map<String, dynamic> lobbySnapshot() => {
      'gameId': 'g-1',
      'joinCode': 'S6HG3F',
      'state': 'LOBBY',
      'hostPlays': false,
      'roundId': 25,
      'roundIdx': 1,
      'finalRound': false,
      'progressRounds': true,
      'packageNumber': 7,
      'packageTitle': 'პაკეტი #7',
      'teams': [
        {
          'id': 't-1',
          'name': 'მთიები',
          'score': 0,
          'host': false,
          'seat': 1,
          'wager': null,
          'lockedOutOnCurrentClue': false,
          'players': [
            {'id': 'p-1', 'name': 'ნინო', 'host': false},
          ],
        },
      ],
      'board': const [],
      'currentClue': null,
      'buzzedTeamId': null,
      'buzzedPlayerId': null,
      'pickingTeamId': null,
      'answerRevealed': false,
      'answerPeeked': false,
      'tilesRemaining': 30,
      'seq': 0,
      'attribution': 'moazrovne.net',
    };

void main() {
  Widget resumeApp(GameSession session, {Map<String, dynamic>? snapshot}) {
    final client = MockClient((request) async => http.Response(
          jsonEncode(snapshot ?? lobbySnapshot()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ));

    return ProviderScope(
      overrides: [
        restClientProvider.overrideWithValue(RestClient(client: client)),
      ],
      child: MaterialApp(
        home: ResumeScreen(session: session, onGiveUp: () {}),
      ),
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

  testWidgets('a stored host session reopens the host console', (tester) async {
    await tester.pumpWidget(resumeApp(hostSession()));
    // The fetch is kicked off from a post-frame callback, so two pumps: one to
    // run it, one to build what it navigated to.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(HostGameScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Dispose the tree so the socket's reconnect timer does not outlive the test.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a stored player session reopens the buzzer', (tester) async {
    await tester.pumpWidget(resumeApp(playerSession()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byType(BuzzerScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a finished game is not resumed', (tester) async {
    final finished = lobbySnapshot()..['state'] = 'FINISHED';
    await tester.pumpWidget(resumeApp(hostSession(), snapshot: finished));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Nothing to come back to: hand control back rather than reopening a
    // console for a game that is over.
    expect(find.byType(HostGameScreen), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });
}
