@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeopard_app/core/game_feed.dart';
import 'package:jeopard_app/core/models.dart';
import 'package:jeopard_app/core/providers.dart';
import 'package:jeopard_app/core/rest_client.dart';
import 'package:jeopard_app/core/session.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/team/buzzer_screen.dart';
import 'package:jeopard_app/widgets/stage.dart';

/// The buzzer goes the moment the finger lands -- not when it lifts -- and the
/// press says how long this device had been showing the open buzzer, which is
/// what the server ranks presses by.
void main() {
  Map<String, dynamic> snapshot({
    String state = 'BUZZ_OPEN',
    int clueId = 1,
    int seq = 1,
  }) => {
    'gameId': 'g-1',
    'joinCode': 'S6HG3F',
    'state': state,
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
        'solo': false,
        'players': [
          {'id': 'p-1', 'name': 'ანა', 'host': false},
        ],
      },
    ],
    'board': const [],
    'currentClue': {
      'clueId': clueId,
      'topicName': 'თემა',
      'value': 10,
      'question': 'კითხვა',
      'answer': null,
      'correctionNote': null,
      'lockedOutTeamIds': const [],
    },
    'buzzedTeamId': null,
    'buzzedPlayerId': null,
    'pickingTeamId': null,
    'answerRevealed': false,
    'answerPeeked': false,
    'tilesRemaining': 30,
    'playersPickClues': false,
    'seq': seq,
    'attribution': 'moazrovne.net',
  };

  group('GameFeed.reactionMs', () {
    test('counts from the buzzer opening, and not while it is shut', () async {
      final feed = GameFeed(gameId: 'g-1');
      addTearDown(feed.dispose);

      feed.push(Snapshot.fromJson(snapshot(state: 'CLUE_READING')));
      await Future<void>.delayed(Duration.zero);
      expect(feed.reactionMs, isNull);

      feed.push(Snapshot.fromJson(snapshot(seq: 2)));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final first = feed.reactionMs!;
      expect(first, greaterThanOrEqualTo(30));

      // A score change mid-open is another broadcast, not another opening.
      feed.push(Snapshot.fromJson(snapshot(seq: 3)));
      await Future<void>.delayed(Duration.zero);
      expect(feed.reactionMs, greaterThanOrEqualTo(first));

      // Someone buzzed, was wrong, and the buzzer reopened: a fresh count.
      feed.push(Snapshot.fromJson(snapshot(state: 'BUZZED', seq: 4)));
      await Future<void>.delayed(Duration.zero);
      expect(feed.reactionMs, isNull);
      feed.push(Snapshot.fromJson(snapshot(seq: 5)));
      await Future<void>.delayed(Duration.zero);
      expect(feed.reactionMs, lessThan(first));
    });

    test('a new clue restarts the count', () async {
      final feed = GameFeed(gameId: 'g-1');
      addTearDown(feed.dispose);

      feed.push(Snapshot.fromJson(snapshot()));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final onFirst = feed.reactionMs!;
      feed.push(Snapshot.fromJson(snapshot(clueId: 2, seq: 2)));
      await Future<void>.delayed(Duration.zero);
      expect(feed.reactionMs, lessThan(onFirst));
    });
  });

  testWidgets('the press is sent on the finger landing, once', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(420, 860) * 2;
    addTearDown(tester.view.reset);

    final buzzes = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/buzz')) {
        buzzes.add(jsonDecode(request.body) as Map<String, dynamic>);
      }
      return http.Response(
        jsonEncode(snapshot()),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          restClientProvider.overrideWithValue(RestClient(client: client)),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          builder: (context, child) => Stage(child: child!),
          home: BuzzerScreen(
            session: GameSession(
              gameId: 'g-1',
              joinCode: 'S6HG3F',
              isHost: false,
              savedAt: DateTime.now(),
              playerId: 'p-1',
              playerToken: 'tok-p-1',
              playerName: 'ანა',
              teamId: 't-1',
              teamName: 'მთიები',
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    final button = find.text(L.buzz);
    expect(button, findsOneWidget);

    // Finger down and held: the press has already gone.
    final gesture = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 50));
    expect(buzzes, hasLength(1));
    expect(buzzes.single['playerToken'], 'tok-p-1');
    expect(buzzes.single['reactionMs'], isA<int>());

    // Lifting it completes the tap, which must not press a second time.
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(buzzes, hasLength(1));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
