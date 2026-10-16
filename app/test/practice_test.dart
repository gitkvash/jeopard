@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeopard_app/core/models.dart';
import 'package:jeopard_app/core/providers.dart';
import 'package:jeopard_app/core/rest_client.dart';
import 'package:jeopard_app/core/session.dart';
import 'package:jeopard_app/core/session_store.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/practice/practice_screen.dart';
import 'package:jeopard_app/role_screen.dart';

/// One person practising alone: the start screen offers it, a stored practice
/// session comes back to it, and the clue is judged by the player themselves.
void main() {
  setUp(() {
    SessionStore.debugKeepInMemory = true;
    SessionStore.clear();
  });

  tearDown(() {
    SessionStore.clear();
    SessionStore.debugKeepInMemory = false;
  });

  const answer = 'დავით აღმაშენებელი';

  GameSession practiceSession() => GameSession(
    gameId: 'g-1',
    joinCode: 'S6HG3F',
    isHost: true,
    savedAt: DateTime.now(),
    hostToken: 'host-tok',
    hostTeamId: 't-1',
    playerId: 'p-1',
    playerToken: 'player-tok',
    teamId: 't-1',
    practice: true,
  );

  Map<String, dynamic> snapshot(
    String state, {
    int score = 0,
    bool answerPeeked = false,
    bool answerRevealed = false,
  }) => {
    'gameId': 'g-1',
    'joinCode': 'S6HG3F',
    'state': state,
    'hostPlays': true,
    'practice': true,
    'roundId': 25,
    'roundIdx': 1,
    'finalRound': false,
    'progressRounds': true,
    'packageNumber': 7,
    'packageTitle': 'პაკეტი #7',
    'teams': [
      {
        'id': 't-1',
        'name': 'მოთამაშე',
        'score': score,
        'host': true,
        'seat': 1,
        'wager': null,
        'lockedOutOnCurrentClue': false,
        'solo': false,
        'players': [
          {'id': 'p-1', 'name': 'მოთამაშე', 'host': true},
        ],
      },
    ],
    'board': const [],
    'currentClue': state == 'BOARD'
        ? null
        : {
            'clueId': 3,
            'topicName': 'ისტორია',
            'value': 40,
            'question': 'ვინ მოიგო დიდგორის ბრძოლა?',
            'answer': answerRevealed ? answer : null,
            'correctionNote': null,
            'lockedOutTeamIds': const <String>[],
          },
    'buzzedTeamId': null,
    'buzzedPlayerId': null,
    'pickingTeamId': null,
    'answerRevealed': answerRevealed,
    'answerPeeked': answerPeeked,
    'tilesRemaining': 29,
    'buzzMode': 'HOST',
    'seq': 1,
    'attribution': 'moazrovne.net',
  };

  /// Every request the app made, as `METHOD path` plus its decoded body.
  final calls = <(String, Map<String, dynamic>)>[];

  /// A server that answers the snapshot with [snap], a peek with the answer,
  /// and a ruling with the clue resolved.
  Widget app(Widget home, {required Map<String, dynamic> snap}) {
    calls.clear();
    final client = MockClient((request) async {
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map<String, dynamic>;
      calls.add(('${request.method} ${request.url.path}', body));
      final path = request.url.path;
      final Object reply;
      if (path.endsWith('/peek')) {
        reply = {
          'clueId': 3,
          'answer': answer,
          'correctionNote': null,
          'peekPenaltyApplied': true,
        };
      } else if (path.endsWith('/self-judge')) {
        reply = snapshot(
          'RESOLVED',
          score: body['correct'] == true ? 40 : -40,
          answerRevealed: true,
        );
      } else {
        reply = snap;
      }
      return http.Response(
        jsonEncode(reply),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    return ProviderScope(
      overrides: [
        restClientProvider.overrideWithValue(RestClient(client: client)),
      ],
      child: MaterialApp(theme: buildTheme(), home: home),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  void useSize(WidgetTester tester) {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(400, 800) * 2;
    addTearDown(tester.view.reset);
  }

  test('a practice session survives being stored', () {
    final restored = GameSession.decode(practiceSession().encode());
    expect(restored?.practice, isTrue);
    // A session written before practice existed is an ordinary one.
    final old = GameSession.decode(
      jsonEncode({
        'gameId': 'g-1',
        'joinCode': 'S6HG3F',
        'isHost': true,
        'savedAt': DateTime.now().toIso8601String(),
        'hostToken': 'host-tok',
      }),
    );
    expect(old?.practice, isFalse);
    expect(gameScreenFor(practiceSession()), isA<PracticeScreen>());
  });

  test('the snapshot says whether the game is practice', () {
    expect(Snapshot.fromJson(snapshot('BOARD')).practice, isTrue);
    expect(
      Snapshot.fromJson({...snapshot('BOARD')}..remove('practice')).practice,
      isFalse,
    );
  });

  testWidgets('the start screen offers practice, and returns to one', (
    tester,
  ) async {
    useSize(tester);
    SessionStore.write(practiceSession());
    await tester.pumpWidget(app(const RoleScreen(), snap: snapshot('BOARD')));
    await settle(tester);

    expect(find.text(L.practiceHint), findsOneWidget);
    // Nobody can join a practice game, so its code is not offered.
    expect(find.text(L.practice), findsWidgets);
    expect(find.textContaining('${L.joinCode}:'), findsNothing);
    expect(find.textContaining('S6HG3F'), findsNothing);
  });

  testWidgets('looking at the answer, then judging it oneself', (tester) async {
    useSize(tester);
    await tester.pumpWidget(
      app(
        PracticeScreen(session: practiceSession()),
        snap: snapshot('CLUE_READING'),
      ),
    );
    await settle(tester);

    expect(find.text(L.practiceThink), findsOneWidget);
    expect(find.text(answer), findsNothing);
    expect(find.text(L.correct), findsNothing);

    await tester.tap(find.text(L.showAnswer));
    await settle(tester);
    expect(calls.map((c) => c.$1), contains('POST /api/games/g-1/peek'));
    expect(find.text(answer), findsOneWidget);
    expect(find.text(L.practiceDidYouKnow), findsOneWidget);

    await tester.tap(find.text(L.correct));
    await settle(tester);
    final judged = calls.lastWhere((c) => c.$1.endsWith('/self-judge'));
    expect(judged.$2, {'correct': true});
    expect(find.text(L.next), findsOneWidget);
  });

  testWidgets('an answer already looked at comes back after a reload', (
    tester,
  ) async {
    useSize(tester);
    await tester.pumpWidget(
      app(
        PracticeScreen(session: practiceSession()),
        snap: snapshot('CLUE_READING', answerPeeked: true),
      ),
    );
    await settle(tester);

    expect(find.text(answer), findsOneWidget);
    expect(find.text(L.wrong), findsOneWidget);
  });

  testWidgets('not knowing passes the clue, at no cost', (tester) async {
    useSize(tester);
    await tester.pumpWidget(
      app(
        PracticeScreen(session: practiceSession()),
        snap: snapshot('CLUE_READING'),
      ),
    );
    await settle(tester);

    await tester.tap(find.text(L.practiceNotKnown));
    await settle(tester);
    expect(calls.map((c) => c.$1), contains('POST /api/games/g-1/pass'));
    expect(calls.where((c) => c.$1.endsWith('/self-judge')), isEmpty);
  });
}
