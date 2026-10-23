@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeopard_app/core/models.dart';
import 'package:jeopard_app/core/providers.dart';
import 'package:jeopard_app/core/rest_client.dart';
import 'package:jeopard_app/core/session.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/host/host_game_screen.dart';
import 'package:jeopard_app/team/buzzer_screen.dart';
import 'package:jeopard_app/widgets/stage.dart';

void main() {
  setUpAll(() async {
    Future<void> load(String family, List<String> files) async {
      final loader = FontLoader(family);
      for (final f in files) {
        loader.addFont(rootBundle.load('assets/fonts/$f'));
      }
      await loader.load();
    }

    await load('NotoSansGeorgian', [
      'NotoSansGeorgian-Regular.ttf',
      'NotoSansGeorgian-SemiBold.ttf',
      'NotoSansGeorgian-Bold.ttf',
    ]);
    await load('RobotoLatin', [
      'RobotoLatin-Regular.ttf',
      'RobotoLatin-SemiBold.ttf',
      'RobotoLatin-Bold.ttf',
    ]);
    await load('Condensed', [
      'RobotoCondensed-Regular.ttf',
      'RobotoCondensed-Bold.ttf',
    ]);
  });

  Map<String, dynamic> team(
    String id,
    String name,
    int score, {
    int? wager,
    String? finalAnswer,
    bool hasFinalAnswer = false,
    bool lockedOut = false,
  }) => {
    'id': id,
    'name': name,
    'score': score,
    'host': false,
    'seat': 1,
    'wager': wager,
    'finalAnswer': finalAnswer,
    'hasFinalAnswer': hasFinalAnswer,
    'lockedOutOnCurrentClue': lockedOut,
    'solo': false,
    'players': [
      {'id': 'p-$id', 'name': 'Player $id', 'host': false},
    ],
  };

  Map<String, dynamic> col(int topicId, String name, int clueId, String status) => {
    'topicId': topicId,
    'idx': topicId,
    'name': name,
    'tiles': [
      {
        'clueId': clueId,
        'value': 0,
        'status': status,
        'wonByTeamId': null,
      },
    ],
  };

  Map<String, dynamic> snapshot({
    required String state,
    Map<String, dynamic>? currentClue,
    List<Map<String, dynamic>>? board,
    List<Map<String, dynamic>>? teams,
    String? pickingTeamId,
    bool finalAnswersLocked = false,
  }) => {
    'gameId': 'g-1',
    'joinCode': 'S6HG3F',
    'state': state,
    'roundId': 4,
    'roundIdx': 4,
    'isFinalRound': true,
    'progressRounds': true,
    'readingTimerSec': null,
    'buzzDurationSec': null,
    'autoOpenBuzz': false,
    'hostPlays': false,
    'playersPickClues': true,
    'questionsVisibleToParticipants': true,
    'board': board ?? [],
    'currentClue': currentClue,
    'buzzedTeamId': null,
    'buzzedPlayerId': null,
    'pickingTeamId': pickingTeamId,
    'answerRevealed': false,
    'answerPeeked': false,
    'tilesRemaining': 5,
    'finalAnswersLocked': finalAnswersLocked,
    'seq': 1,
    'teams': teams ?? [team('t-1', 'გუნდი 1', 100), team('t-2', 'გუნდი 2', 200)],
  };

  GameSession hostSession() => GameSession(
    gameId: 'g-1',
    joinCode: 'S6HG3F',
    isHost: true,
    savedAt: DateTime.now(),
    hostToken: 'host-tok',
  );

  GameSession playerSession({String teamId = 't-1'}) => GameSession(
    gameId: 'g-1',
    joinCode: 'S6HG3F',
    isHost: false,
    savedAt: DateTime.now(),
    playerId: 'p-$teamId',
    playerToken: 'player-tok',
    playerName: 'Player 1',
    teamId: teamId,
    teamName: 'გუნდი 1',
  );

  final calls = <(String, Map<String, dynamic>)>[];

  Widget testApp(Widget home, {required Map<String, dynamic> snap}) {
    calls.clear();
    final client = MockClient((request) async {
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map<String, dynamic>;
      calls.add(('${request.method} ${request.url.path}', body));
      return http.Response(
        jsonEncode(snap),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    return ProviderScope(
      overrides: [
        restClientProvider.overrideWithValue(RestClient(client: client)),
      ],
      child: MaterialApp(
        theme: buildTheme(),
        home: Stage(child: home),
      ),
    );
  }

  group('Final round topic elimination', () {
    testWidgets('host sees elimination phase and can eliminate topic', (tester) async {
      final board = [
        col(1, 'ქართული პოეზია', 101, 'AVAILABLE'),
        col(2, 'მსოფლიო გეოგრაფია', 102, 'AVAILABLE'),
        col(3, 'ძველი ისტორია', 103, 'DONE'),
      ];
      final snap = snapshot(
        state: 'FINAL_WAGER',
        board: board,
        pickingTeamId: 't-1',
      );

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(testApp(HostGameScreen(session: hostSession()), snap: snap));
      await tester.pumpAndSettle();

      expect(find.text(L.eliminationPhase), findsOneWidget);
      expect(find.text('ქართული პოეზია'), findsOneWidget);
      expect(find.text('მსოფლიო გეოგრაფია'), findsOneWidget);
      expect(find.text('ძველი ისტორია'), findsOneWidget);
      expect(find.text(L.topicEliminated), findsOneWidget);

      final eliminateButtons = find.text(L.eliminateTopic);
      expect(eliminateButtons, findsNWidgets(2));

      await tester.tap(eliminateButtons.first);
      await tester.pump();

      expect(calls, hasLength(2)); // initial snapshot fetch + eliminate
      final lastCall = calls.last;
      expect(lastCall.$1, 'POST /api/games/g-1/eliminate-topic');
      expect(lastCall.$2['clueId'], 101);
    });

    testWidgets('team sees turn banner and can eliminate topic on their turn', (tester) async {
      final board = [
        col(1, 'ქართული პოეზია', 101, 'AVAILABLE'),
        col(2, 'მსოფლიო გეოგრაფია', 102, 'AVAILABLE'),
      ];
      final snap = snapshot(
        state: 'FINAL_WAGER',
        board: board,
        pickingTeamId: 't-1',
      );

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(testApp(BuzzerScreen(session: playerSession(teamId: 't-1')), snap: snap));
      await tester.pumpAndSettle();

      expect(find.text(L.yourTurnToEliminate), findsOneWidget);
      final eliminateButtons = find.text(L.eliminateTopic);
      expect(eliminateButtons, findsNWidgets(2));

      await tester.tap(eliminateButtons.first);
      await tester.pump();

      expect(calls.last.$1, 'POST /api/games/g-1/eliminate-topic');
      expect(calls.last.$2['clueId'], 101);
    });

    testWidgets('team waiting when it is other team turn to eliminate', (tester) async {
      final board = [
        col(1, 'ქართული პოეზია', 101, 'AVAILABLE'),
      ];
      final snap = snapshot(
        state: 'FINAL_WAGER',
        board: board,
        pickingTeamId: 't-2',
      );

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(testApp(BuzzerScreen(session: playerSession(teamId: 't-1')), snap: snap));
      await tester.pumpAndSettle();

      expect(find.textContaining(L.waitingForElimination), findsOneWidget);
      expect(find.text(L.eliminateTopic), findsNothing);
    });
  });

  group('Final round secret answers and cutoff', () {
    testWidgets('team can type and submit secret final answer', (tester) async {
      final snap = snapshot(
        state: 'FINAL_CLUE',
        currentClue: {
          'clueId': 101,
          'topicName': 'ქართული პოეზია',
          'value': null,
          'question': 'ვინ არის „ვეფხისტყაოსნის“ ავტორი?',
          'answer': null,
          'correctionNote': null,
          'lockedOutTeamIds': const <String>[],
        },
        finalAnswersLocked: false,
      );

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(testApp(BuzzerScreen(session: playerSession(teamId: 't-1')), snap: snap));
      await tester.pumpAndSettle();

      expect(find.text(L.yourFinalAnswer), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'შოთა რუსთაველი');
      await tester.tap(find.text(L.submitAnswer));
      await tester.pump();

      expect(calls.last.$1, 'POST /api/games/g-1/final-answer');
      expect(calls.last.$2['answer'], 'შოთა რუსთაველი');
    });

    testWidgets('host sees cutoff button when answers unlocked', (tester) async {
      final snapUnlocked = snapshot(
        state: 'FINAL_CLUE',
        currentClue: {
          'clueId': 101,
          'topicName': 'ქართული პოეზია',
          'value': null,
          'question': 'ვინ არის „ვეფხისტყაოსნის“ ავტორი?',
          'answer': 'შოთა რუსთაველი',
          'correctionNote': null,
          'lockedOutTeamIds': const <String>[],
        },
        teams: [
          team('t-1', 'გუნდი 1', 100, wager: 50, hasFinalAnswer: true),
          team('t-2', 'გუნდი 2', 200, wager: 100, hasFinalAnswer: false),
        ],
        finalAnswersLocked: false,
      );

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(testApp(HostGameScreen(session: hostSession()), snap: snapUnlocked));
      await tester.pumpAndSettle();

      expect(find.text(L.timeCutoff), findsOneWidget);
      await tester.tap(find.text(L.timeCutoff));
      await tester.pump();

      expect(calls.last.$1, 'POST /api/games/g-1/lock-final-answers');
    });

    testWidgets('host judges locked answers', (tester) async {
      final snapLocked = snapshot(
        state: 'FINAL_CLUE',
        currentClue: {
          'clueId': 101,
          'topicName': 'ქართული პოეზია',
          'value': null,
          'question': 'ვინ არის „ვეფხისტყაოსნის“ ავტორი?',
          'answer': 'შოთა რუსთაველი',
          'correctionNote': null,
          'lockedOutTeamIds': const <String>[],
        },
        teams: [
          team('t-1', 'გუნდი 1', 100, wager: 50, finalAnswer: 'შოთა რუსთაველი', hasFinalAnswer: true),
          team('t-2', 'გუნდი 2', 200, wager: 100, finalAnswer: null, hasFinalAnswer: false),
        ],
        finalAnswersLocked: true,
      );

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(testApp(HostGameScreen(session: hostSession()), snap: snapLocked));
      await tester.pumpAndSettle();

      expect(find.text('„შოთა რუსთაველი“'), findsOneWidget);
      expect(find.text(L.noAnswerGiven), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNWidgets(2));
      expect(find.byIcon(Icons.close), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.check).first);
      await tester.pump();

      expect(calls.last.$1, 'POST /api/games/g-1/final-judge');
      expect(calls.last.$2['teamId'], 't-1');
      expect(calls.last.$2['correct'], true);
    });
  });
}
