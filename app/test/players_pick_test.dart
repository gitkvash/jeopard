@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeopard_app/core/providers.dart';
import 'package:jeopard_app/core/rest_client.dart';
import 'package:jeopard_app/core/session.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/host/host_game_screen.dart';
import 'package:jeopard_app/team/buzzer_screen.dart';
import 'package:jeopard_app/widgets/game_chrome.dart';
import 'package:jeopard_app/widgets/stage.dart';

/// A game where the players choose the tile in turn: the team whose turn it is
/// is told so and can tap the board, everyone else watches, and the host can
/// always choose.
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

  Map<String, dynamic> team(String id, String name, String playerId) => {
    'id': id,
    'name': name,
    'score': 0,
    'host': false,
    'seat': 1,
    'wager': null,
    'lockedOutOnCurrentClue': false,
    'solo': false,
    'players': [
      {'id': playerId, 'name': 'მოთამაშე $playerId', 'host': false},
    ],
  };

  Map<String, dynamic> snapshot({
    required bool playersPick,
    String? picking,
    String state = 'BOARD',
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
    'teams': [team('t-1', 'მთიები', 'p-1'), team('t-2', 'ვეფხვები', 'p-2')],
    'board': [
      for (var c = 0; c < 6; c++)
        {
          'topicId': c + 1,
          'idx': c,
          'name': 'თემა ${c + 1}',
          'tiles': [
            for (var r = 0; r < 5; r++)
              {
                'clueId': c * 10 + r + 1,
                'value': (r + 1) * 10,
                'status': 'AVAILABLE',
                'wonByTeamId': null,
              },
          ],
        },
    ],
    'currentClue': null,
    'buzzedTeamId': null,
    'buzzedPlayerId': null,
    'pickingTeamId': picking,
    'answerRevealed': false,
    'answerPeeked': false,
    'tilesRemaining': 30,
    'playersPickClues': playersPick,
    'seq': 1,
    'attribution': 'moazrovne.net',
  };

  GameSession hostSession() => GameSession(
    gameId: 'g-1',
    joinCode: 'S6HG3F',
    isHost: true,
    savedAt: DateTime.now(),
    hostToken: 'host-tok',
  );

  GameSession playerSession(String playerId, String teamId) => GameSession(
    gameId: 'g-1',
    joinCode: 'S6HG3F',
    isHost: false,
    savedAt: DateTime.now(),
    playerId: playerId,
    playerToken: 'tok-$playerId',
    playerName: 'მოთამაშე $playerId',
    teamId: teamId,
    teamName: 'x',
  );

  final calls = <(String, Map<String, dynamic>)>[];

  Widget app(
    Widget home, {
    required Map<String, dynamic> snap,
    int pickStatus = 200,
  }) {
    calls.clear();
    final client = MockClient((request) async {
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map<String, dynamic>;
      calls.add(('${request.method} ${request.url.path}', body));
      final refused =
          request.url.path.endsWith('/pick-clue') && pickStatus != 200;
      return http.Response(
        refused ? jsonEncode({'detail': 'not your turn'}) : jsonEncode(snap),
        refused ? pickStatus : 200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    return ProviderScope(
      overrides: [
        restClientProvider.overrideWithValue(RestClient(client: client)),
      ],
      child: MaterialApp(
        theme: buildTheme(),
        debugShowCheckedModeBanner: false,
        builder: (context, child) => Stage(child: child!),
        home: home,
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  void useSize(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    addTearDown(tester.view.reset);
  }

  const wide = Size(900, 640);

  testWidgets('the team whose turn it is is told, and taps a tile to pick it', (
    tester,
  ) async {
    useSize(tester, wide);
    await tester.pumpWidget(
      app(
        BuzzerScreen(session: playerSession('p-1', 't-1')),
        snap: snapshot(playersPick: true, picking: 't-1'),
      ),
    );
    await settle(tester);

    expect(find.byType(YourTurnBanner), findsOneWidget);
    expect(find.text(L.yourTurnToPick), findsOneWidget);

    // Tile "10" of the first category.
    await tester.tap(find.text('10').first);
    await settle(tester);

    final pick = calls.where((c) => c.$1 == 'POST /api/games/g-1/pick-clue');
    expect(pick, hasLength(1));
    expect(pick.single.$2, {'playerToken': 'tok-p-1', 'clueId': 1});
  });

  testWidgets('a team out of turn sees whose it is, and the board does nothing', (
    tester,
  ) async {
    useSize(tester, wide);
    await tester.pumpWidget(
      app(
        BuzzerScreen(session: playerSession('p-2', 't-2')),
        snap: snapshot(playersPick: true, picking: 't-1'),
      ),
    );
    await settle(tester);

    expect(find.byType(YourTurnBanner), findsNothing);
    expect(find.text(L.isChoosing('მთიები')), findsOneWidget);

    await tester.tap(find.text('10').first, warnIfMissed: false);
    await settle(tester);
    expect(calls.where((c) => c.$1.endsWith('/pick-clue')), isEmpty);
  });

  testWidgets('where the host chooses, a team never gets the board', (
    tester,
  ) async {
    useSize(tester, wide);
    await tester.pumpWidget(
      app(
        BuzzerScreen(session: playerSession('p-1', 't-1')),
        snap: snapshot(playersPick: false, picking: 't-1'),
      ),
    );
    await settle(tester);

    expect(find.byType(YourTurnBanner), findsNothing);
    await tester.tap(find.text('10').first, warnIfMissed: false);
    await settle(tester);
    expect(calls.where((c) => c.$1.endsWith('/pick-clue')), isEmpty);
  });

  testWidgets('a pick refused as out of turn is explained, in Georgian', (
    tester,
  ) async {
    useSize(tester, wide);
    await tester.pumpWidget(
      app(
        BuzzerScreen(session: playerSession('p-1', 't-1')),
        snap: snapshot(playersPick: true, picking: 't-1'),
        pickStatus: 409,
      ),
    );
    await settle(tester);

    await tester.tap(find.text('10').first);
    await settle(tester);

    expect(find.text(L.pickNotYourTurn), findsOneWidget);
    // Let the toast's dismiss timer run out.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('the host sees whose turn it is and can still pick a tile', (
    tester,
  ) async {
    useSize(tester, wide);
    await tester.pumpWidget(
      app(
        HostGameScreen(session: hostSession()),
        snap: snapshot(playersPick: true, picking: 't-2'),
      ),
    );
    await settle(tester);

    expect(find.text(L.turnToChoose('ვეფხვები')), findsOneWidget);

    await tester.tap(find.text('10').first);
    await settle(tester);
    final select = calls.where(
      (c) => c.$1 == 'POST /api/games/g-1/select-clue',
    );
    expect(select, hasLength(1));
    expect(select.single.$2, {'clueId': 1});
  });
}
