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
import 'package:jeopard_app/core/notices.dart';
import 'package:jeopard_app/core/providers.dart';
import 'package:jeopard_app/core/rest_client.dart';
import 'package:jeopard_app/core/session.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/host/host_game_screen.dart';
import 'package:jeopard_app/team/buzzer_screen.dart';
import 'package:jeopard_app/team/join_screen.dart';
import 'package:jeopard_app/widgets/stage.dart';

/// Playing without a team, setting a buzz aside, the host's corrections, and the
/// answer reaching a team's own screen once the host has passed.
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

  // ---------------- fixtures ----------------

  Map<String, dynamic> team(
    String id,
    String name,
    int score,
    List<Map<String, dynamic>> players, {
    bool solo = false,
    bool host = false,
  }) => {
    'id': id,
    'name': name,
    'score': score,
    'host': host,
    'seat': 1,
    'wager': null,
    'lockedOutOnCurrentClue': false,
    'solo': solo,
    'players': players,
  };

  Map<String, dynamic> person(String id, String name) => {
    'id': id,
    'name': name,
    'host': false,
  };

  final longQuestion =
      'ამ ქართველმა მეფემ, რომელიც მეთორმეტე საუკუნეში მართავდა ქვეყანას და '
          'რომელსაც ისტორია "აღმაშენებელს" უწოდებს, დიდგორის ბრძოლაში მოიგო '
          'სელჩუკთა ურიცხვი ლაშქარი. ვის ვგულისხმობთ? ' *
      3;

  const answer = 'დავით აღმაშენებელი';

  Map<String, dynamic> snapshot(
    String state, {
    List<Map<String, dynamic>>? teams,
    bool answerRevealed = false,
    String? buzzedTeamId,
    bool withClue = false,
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
    'teams':
        teams ??
        [
          team('t-1', 'მთიები', 1200, [
            person('p-1', 'ნინო'),
            person('p-2', 'გიო'),
          ]),
          team('t-2', 'ლევანი', 300, [person('p-3', 'ლევანი')], solo: true),
        ],
    'board': const [],
    'currentClue': withClue
        ? {
            'clueId': 3,
            'topicName': 'ისტორია',
            'value': 600,
            'question': longQuestion,
            'answer': answerRevealed ? answer : null,
            'correctionNote': null,
            'lockedOutTeamIds': const <String>[],
          }
        : null,
    'buzzedTeamId': buzzedTeamId,
    'buzzedPlayerId': null,
    'pickingTeamId': null,
    'answerRevealed': answerRevealed,
    'answerPeeked': false,
    'tilesRemaining': 28,
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

  GameSession playerSession({String playerId = 'p-1'}) => GameSession(
    gameId: 'g-1',
    joinCode: 'S6HG3F',
    isHost: false,
    savedAt: DateTime.now(),
    playerId: playerId,
    playerToken: 'player-tok',
    playerName: 'ნინო',
    teamId: 't-1',
    teamName: 'მთიები',
  );

  /// Every request the app made, as `METHOD path` plus its decoded body.
  final calls = <(String, Map<String, dynamic>)>[];

  Widget app(Widget home, {required Map<String, dynamic> snap}) {
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

  const phone = Size(360, 640);

  // ---------------- wire shapes ----------------

  group('wire shapes', () {
    test('a team says whether it is one person playing alone', () {
      final solo = TeamView.fromJson(
        team('t', 'ანა', 0, [person('p', 'ანა')], solo: true),
      );
      final chosen = TeamView.fromJson(team('t', 'მთიები', 0, const []));
      expect(solo.solo, isTrue);
      expect(chosen.solo, isFalse);
      // A server that predates this field is not playing solo.
      expect(
        TeamView.fromJson({'id': 't', 'name': 'x', 'score': 0}).solo,
        isFalse,
      );
    });

    test('a notice parses, and a score notice reads as a before and after', () {
      final n = Notice.fromJson({
        'kind': 'SCORE_CHANGED',
        'teamName': 'მთიები',
        'scoreBefore': 40,
        'scoreAfter': 70,
      });
      expect(n.isScore, isTrue);
      expect(describeNotice(n), contains('მთიები'));
      expect(describeNotice(n), contains('40'));
      expect(describeNotice(n), contains('70'));
    });

    test('a move is addressed to the person it happened to', () {
      final n = Notice.fromJson({
        'kind': 'PLAYER_MOVED',
        'playerId': 'p-1',
        'playerName': 'ნინო',
        'fromTeamName': 'მთიები',
        'toTeamName': 'ვეფხვები',
      });
      expect(describeNotice(n, myPlayerId: 'p-1'), L.youWereMoved('ვეფხვები'));
      expect(
        describeNotice(n, myPlayerId: 'p-9'),
        L.playerMoved('ნინო', 'ვეფხვები'),
      );
      // Moved onto their own: no team to name.
      final alone = Notice.fromJson({
        'kind': 'PLAYER_MOVED',
        'playerId': 'p-1',
        'playerName': 'ნინო',
        'fromTeamName': 'მთიები',
      });
      expect(describeNotice(alone), L.playerMoved('ნინო', null));
      expect(describeNotice(alone), isNot(contains('„')));
    });

    test('a notice it does not understand is not worth a toast', () {
      expect(describeNotice(Notice(kind: 'SOMETHING_NEW')), isNull);
      expect(describeNotice(Notice(kind: 'SCORE_CHANGED')), isNull);
    });

    test('a game terminated notice describes as gameEndedNotice', () {
      final n = Notice.fromJson({'kind': 'GAME_TERMINATED'});
      expect(n.isGameTerminated, isTrue);
      expect(describeNotice(n), L.gameEndedNotice);
    });
  });

  // ---------------- joining without a team ----------------

  group('joining', () {
    testWidgets('a player can play without a team', (tester) async {
      useSize(tester, phone);
      final lobby = {
        'gameId': 'g-1',
        'joinCode': 'S6HG3F',
        'state': 'LOBBY',
        'teams': [
          {
            'id': 't-1',
            'name': 'მთიები',
            'seat': 1,
            'score': 0,
            'memberNames': ['ნინო'],
          },
        ],
      };
      final joined = {
        'gameId': 'g-1',
        'playerId': 'p-9',
        'playerToken': 'tok',
        'playerName': 'ანა',
        'teamId': 't-9',
        'teamName': 'ანა',
        'seat': 2,
        'solo': true,
      };
      final sent = <String>[];
      final client = MockClient((request) async {
        sent.add('${request.method} ${request.url.path} ${request.body}');
        final isJoin = request.method == 'POST';
        return http.Response(
          jsonEncode(isJoin ? joined : lobby),
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
            home: const JoinScreen(),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).first, 'S6HG3F');
      await tester.enterText(find.byType(TextField).last, 'ანა');
      await tester.pump();
      await tester.tap(find.text(L.next2));
      await settle(tester);

      expect(find.text(L.playSolo), findsOneWidget);
      await tester.tap(find.text(L.playSolo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final post = sent.firstWhere((s) => s.startsWith('POST'));
      final body = jsonDecode(post.split(' ').skip(2).join(' ')) as Map;
      // Neither a team nor a new team name: that is what "no team" is.
      expect(body['name'], 'ანა');
      expect(body.containsKey('teamId'), isFalse);
      expect(body.containsKey('newTeamName'), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------- the lobby, from a player's side ----------------

  group('lobby team picker', () {
    testWidgets('a player on a team can leave it and play alone', (tester) async {
      useSize(tester, phone);
      await tester.pumpWidget(
        app(
          BuzzerScreen(session: playerSession()),
          snap: snapshot('LOBBY'),
        ),
      );
      await settle(tester);

      expect(find.text('მთიები'), findsWidgets);
      expect(find.text(L.leaveTeam), findsOneWidget);

      await tester.tap(find.text(L.leaveTeam));
      await settle(tester);

      final call = calls.firstWhere((c) => c.$1.endsWith('/team'));
      expect(call.$1, 'POST /api/games/g-1/team');
      expect(call.$2['playerToken'], 'player-tok');
      expect(call.$2.containsKey('teamId'), isFalse);
      expect(call.$2.containsKey('newTeamName'), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a player alone is offered the teams, and none of the solo ones', (
      tester,
    ) async {
      useSize(tester, phone);
      // Levan plays alone; Nino and Gio sit together.
      await tester.pumpWidget(
        app(
          BuzzerScreen(session: playerSession(playerId: 'p-3')),
          snap: snapshot('LOBBY'),
        ),
      );
      await settle(tester);

      expect(find.text(L.noTeam), findsWidgets);
      // Nothing to leave, but a team to sit with -- and not his own solo team.
      expect(find.text(L.leaveTeam), findsNothing);
      expect(find.text('მთიები'), findsOneWidget);

      await tester.tap(find.text('მთიები'));
      await settle(tester);
      final call = calls.firstWhere((c) => c.$1.endsWith('/team'));
      expect(call.$2['teamId'], 't-1');
    });

    testWidgets('a player can start a team of their own', (tester) async {
      useSize(tester, phone);
      await tester.pumpWidget(
        app(
          BuzzerScreen(session: playerSession()),
          snap: snapshot('LOBBY'),
        ),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'ვეფხვები');
      await tester.pump();
      await tester.tap(find.text(L.createTeam));
      await settle(tester);

      final call = calls.firstWhere((c) => c.$1.endsWith('/team'));
      expect(call.$2['newTeamName'], 'ვეფხვები');
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------- the answer, on a team's own screen ----------------

  group('after the host passes', () {
    for (final size in const [Size(360, 640), Size(390, 844)]) {
      testWidgets(
        'a team sees the answer on screen under a long question ($size)',
        (tester) async {
          useSize(tester, size);
          await tester.pumpWidget(
            app(
              BuzzerScreen(session: playerSession()),
              snap: snapshot('RESOLVED', withClue: true, answerRevealed: true),
            ),
          );
          await settle(tester);

          final at = tester.getRect(find.text(answer));
          // Not merely in the tree: inside the screen, with nothing to scroll to.
          expect(at.bottom, lessThanOrEqualTo(size.height));
          expect(at.top, greaterThan(0));
          expect(find.text(L.answer.toUpperCase()), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('and before it is revealed, there is no answer to see', (
      tester,
    ) async {
      useSize(tester, phone);
      await tester.pumpWidget(
        app(
          BuzzerScreen(session: playerSession()),
          snap: snapshot('BUZZ_OPEN', withClue: true),
        ),
      );
      await settle(tester);
      expect(find.text(answer), findsNothing);
    });
  });

  // ---------------- the host ----------------

  group('host', () {
    testWidgets('can set a buzz aside as well as rule on it', (tester) async {
      useSize(tester, phone);
      await tester.pumpWidget(
        app(
          HostGameScreen(session: hostSession()),
          snap: snapshot('BUZZED', withClue: true, buzzedTeamId: 't-1'),
        ),
      );
      await settle(tester);

      expect(find.text(L.correct), findsOneWidget);
      expect(find.text(L.wrong), findsOneWidget);
      expect(find.text(L.skipBuzz), findsOneWidget);
      // None of the three wraps mid-word.
      expect(tester.getSize(find.text(L.correct)).height, lessThan(24));
      expect(tester.getSize(find.text(L.wrong)).height, lessThan(24));

      await tester.tap(find.text(L.skipBuzz));
      await settle(tester);
      expect(calls.map((c) => c.$1), contains('POST /api/games/g-1/skip-buzz'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('is not offered a skip when nobody has buzzed', (tester) async {
      useSize(tester, phone);
      await tester.pumpWidget(
        app(
          HostGameScreen(session: hostSession()),
          snap: snapshot('BUZZ_OPEN', withClue: true),
        ),
      );
      await settle(tester);
      // (The clue-level "pass" button shares the word; the undo icon is the skip.)
      expect(find.widgetWithIcon(TextButton, Icons.undo), findsNothing);
    });

    testWidgets('edits a team score from the manage sheet', (tester) async {
      useSize(tester, phone);
      await tester.pumpWidget(
        app(HostGameScreen(session: hostSession()), snap: snapshot('BOARD')),
      );
      await settle(tester);

      await tester.tap(find.byTooltip(L.manage));
      await settle(tester);
      expect(find.text('1200'), findsWidgets);

      await tester.tap(find.byTooltip(L.editScore).first);
      await settle(tester);
      await tester.enterText(find.byType(TextField), '-50');
      await tester.pump();
      await tester.tap(find.text(L.save));
      await settle(tester);

      final call = calls.firstWhere((c) => c.$1.contains('/score'));
      expect(call.$1, 'POST /api/games/g-1/teams/t-1/score');
      expect(call.$2['score'], -50);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaves the score alone when the number did not change', (
      tester,
    ) async {
      useSize(tester, phone);
      await tester.pumpWidget(
        app(HostGameScreen(session: hostSession()), snap: snapshot('BOARD')),
      );
      await settle(tester);
      await tester.tap(find.byTooltip(L.manage));
      await settle(tester);
      await tester.tap(find.byTooltip(L.editScore).first);
      await settle(tester);
      await tester.tap(find.text(L.save));
      await settle(tester);
      expect(calls.where((c) => c.$1.contains('/score')), isEmpty);
    });

    testWidgets('moves a person onto another team, or out on their own', (
      tester,
    ) async {
      useSize(tester, phone);
      final snap = snapshot(
        'BOARD',
        teams: [
          team('t-1', 'მთიები', 0, [person('p-1', 'ნინო'), person('p-2', 'გიო')]),
          team('t-2', 'ვეფხვები', 0, [person('p-3', 'ლევანი')]),
        ],
      );
      await tester.pumpWidget(
        app(HostGameScreen(session: hostSession()), snap: snap),
      );
      await settle(tester);
      await tester.tap(find.byTooltip(L.manage));
      await settle(tester);

      // Gio, to the other team.
      await tester.tap(find.byTooltip(L.moveTo).at(1));
      await settle(tester);
      await tester.tap(find.text('ვეფხვები').last);
      await settle(tester);
      var call = calls.firstWhere((c) => c.$1.contains('/move'));
      expect(call.$1, 'POST /api/games/g-1/players/p-2/move');
      expect(call.$2['teamId'], 't-2');

      // Nino, out on her own: neither field.
      calls.clear();
      await tester.tap(find.byTooltip(L.moveTo).first);
      await settle(tester);
      await tester.tap(find.text(L.moveAlone));
      await settle(tester);
      call = calls.firstWhere((c) => c.$1.contains('/move'));
      expect(call.$1, 'POST /api/games/g-1/players/p-1/move');
      expect(call.$2.containsKey('teamId'), isFalse);
      expect(call.$2.containsKey('newTeamName'), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cannot move people while a clue is up, and says why', (
      tester,
    ) async {
      useSize(tester, phone);
      await tester.pumpWidget(
        app(
          HostGameScreen(session: hostSession()),
          snap: snapshot('BUZZ_OPEN', withClue: true),
        ),
      );
      await settle(tester);
      await tester.tap(find.byTooltip(L.manage));
      await settle(tester);

      expect(find.text(L.movesBetweenClues), findsOneWidget);
      final menu = tester.widget(
        find.byWidgetPredicate((w) => w is PopupMenuButton).first,
      ) as PopupMenuButton;
      expect(menu.enabled, isFalse);
      // Scores are another matter: they can be corrected at any time.
      expect(find.byTooltip(L.editScore), findsWidgets);
    });

    for (final size in const [Size(360, 640), Size(740, 360)]) {
      testWidgets('the manage sheet fits a $size screen', (tester) async {
        useSize(tester, size);
        await tester.pumpWidget(
          app(HostGameScreen(session: hostSession()), snap: snapshot('BOARD')),
        );
        await settle(tester);
        await tester.tap(find.byTooltip(L.manage));
        await settle(tester);
        expect(find.text(L.manage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
