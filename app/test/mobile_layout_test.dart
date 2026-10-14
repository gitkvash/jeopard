@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:jeopard_app/role_screen.dart';
import 'package:jeopard_app/team/buzzer_screen.dart';
import 'package:jeopard_app/team/join_screen.dart';
import 'package:jeopard_app/widgets/clue_panel.dart';
import 'package:jeopard_app/widgets/stage.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Phones are the device this app is mostly played on -- every player joins from
/// one -- so each screen has to lay out without overflowing at the sizes real
/// phones come in. A RenderFlex overflow is a test failure here, not a yellow
/// stripe somebody notices later.
///
/// Set `SHOTS=<dir>` to also write a PNG of every case, which is how the layouts
/// get looked at when there is no browser to look at them in.
void main() {
  const sizes = <String, Size>{
    'small': Size(360, 640),
    'phone': Size(390, 844),
    'landscape': Size(740, 360),
  };

  final shotsDir = Platform.environment['SHOTS'];

  // Without the real faces every glyph is a 1em box, which makes every width in
  // here wrong. These are the same files the app bundles.
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

  const topics = [
    'გეოგრაფიული ტერმინები',
    'დროის საზომები',
    'ქართული სამზარეულო',
    'არქიტექტურა',
    'ფილმები',
    'მუსიკა',
  ];

  Map<String, dynamic> team(
    int seat,
    String name,
    int score, {
    bool lockedOut = false,
    int? wager,
    int players = 1,
    bool host = false,
  }) => {
    'id': 't-$seat',
    'name': name,
    'score': score,
    'host': host,
    'seat': seat,
    'wager': wager,
    'lockedOutOnCurrentClue': lockedOut,
    'players': [
      for (var i = 0; i < players; i++)
        {'id': 'p-$seat-$i', 'name': 'მოთამაშე $i', 'host': false},
    ],
  };

  final teams = [
    team(1, 'მთიები', 1200, players: 2),
    team(2, 'ძალიან გრძელი გუნდის სახელი ორი', -400, lockedOut: true),
    team(3, 'ბორჯღალი', 15400, host: true),
    team(4, 'ნიანგები', 0),
    team(5, 'მეხუთე გუნდი', 300),
    team(6, 'მეექვსე', 800),
  ];

  List<Map<String, dynamic>> board() => [
    for (var c = 0; c < topics.length; c++)
      {
        'topicId': c + 1,
        'idx': c,
        'name': topics[c],
        'tiles': [
          for (var r = 0; r < 5; r++)
            {
              'clueId': c * 10 + r,
              'value': (r + 1) * 200,
              'status': (c == 1 && r < 2) ? 'DONE' : 'AVAILABLE',
              'wonByTeamId': null,
            },
        ],
      },
  ];

  final longQuestion =
      'ამ ქართველმა მეფემ, რომელიც მეთორმეტე საუკუნეში მართავდა ქვეყანას და '
          'რომელსაც ისტორია "აღმაშენებელს" უწოდებს, დიდგორის ბრძოლაში მოიგო '
          'სელჩუკთა ურიცხვი ლაშქარი. ვის ვგულისხმობთ? ' *
      3;

  Map<String, dynamic> snapshot(
    String state, {
    Map<String, dynamic>? clue,
    String? buzzedTeamId,
    bool answerRevealed = false,
    List<Map<String, dynamic>>? withTeams,
    Map<String, dynamic>? extra,
  }) => {
    'gameId': 'g-1',
    'joinCode': 'S6HG3F',
    'state': state,
    'hostPlays': true,
    'roundId': 25,
    'roundIdx': 1,
    'finalRound': state.startsWith('FINAL'),
    'progressRounds': true,
    'packageNumber': 7,
    'packageTitle': 'პაკეტი #7 — ძალიან გრძელი სათაური',
    'teams': withTeams ?? teams,
    'board': state == 'LOBBY' ? const [] : board(),
    'currentClue': clue,
    'buzzedTeamId': buzzedTeamId,
    'buzzedPlayerId': null,
    'pickingTeamId': 't-1',
    'answerRevealed': answerRevealed,
    'answerPeeked': false,
    'tilesRemaining': 28,
    'seq': 1,
    'attribution': 'moazrovne.net',
    ...?extra,
  };

  Map<String, dynamic> clue({String? answer}) => {
    'clueId': 3,
    'topicName': topics[0],
    'value': 600,
    'question': longQuestion,
    'answer': answer,
    'correctionNote': null,
    'lockedOutTeamIds': const <String>[],
  };

  final cases = <String, ({bool host, Map<String, dynamic> snap})>{
    'host-lobby': (host: true, snap: snapshot('LOBBY')),
    'host-board': (host: true, snap: snapshot('BOARD')),
    'host-reading': (host: true, snap: snapshot('CLUE_READING', clue: clue())),
    'host-buzz-open': (host: true, snap: snapshot('BUZZ_OPEN', clue: clue())),
    'host-buzzed': (
      host: true,
      snap: snapshot('BUZZED', clue: clue(), buzzedTeamId: 't-1'),
    ),
    'host-resolved': (
      host: true,
      snap: snapshot(
        'RESOLVED',
        clue: clue(answer: 'დავით აღმაშენებელი'),
        answerRevealed: true,
      ),
    ),
    'host-final-wager': (
      host: true,
      snap: snapshot('FINAL_WAGER', extra: {'currentClue': clue()}),
    ),
    'host-final-clue': (host: true, snap: snapshot('FINAL_CLUE', clue: clue())),
    'host-finished': (host: true, snap: snapshot('FINISHED')),
    'team-lobby': (host: false, snap: snapshot('LOBBY')),
    'team-board': (host: false, snap: snapshot('BOARD')),
    // The players choose the tile and it is this team's turn (pickingTeamId t-1).
    'team-your-turn': (
      host: false,
      snap: snapshot('BOARD', extra: {'playersPickClues': true}),
    ),
    'host-board-players-pick': (
      host: true,
      snap: snapshot('BOARD', extra: {'playersPickClues': true}),
    ),
    'team-reading': (host: false, snap: snapshot('CLUE_READING', clue: clue())),
    'team-buzz-open': (host: false, snap: snapshot('BUZZ_OPEN', clue: clue())),
    'team-buzzed': (
      host: false,
      snap: snapshot('BUZZED', clue: clue(), buzzedTeamId: 't-2'),
    ),
    // The answer has to be on screen, not merely somewhere down the scroll.
    'team-resolved': (
      host: false,
      snap: snapshot(
        'RESOLVED',
        clue: clue(answer: 'დავით აღმაშენებელი'),
        answerRevealed: true,
      ),
    ),
    'team-wager': (
      host: false,
      snap: snapshot('FINAL_WAGER', extra: {'currentClue': clue()}),
    ),
    'team-finished': (host: false, snap: snapshot('FINISHED')),
  };

  GameSession hostSession() => GameSession(
    gameId: 'g-1',
    joinCode: 'S6HG3F',
    isHost: true,
    savedAt: DateTime.now(),
    hostToken: 'host-tok',
    hostTeamId: 't-3',
  );

  GameSession playerSession() => GameSession(
    gameId: 'g-1',
    joinCode: 'S6HG3F',
    isHost: false,
    savedAt: DateTime.now(),
    playerId: 'p-1-0',
    playerToken: 'player-tok',
    playerName: 'ნინო ძალიან გრძელი სახელი',
    teamId: 't-1',
    teamName: 'მთიები',
  );

  Widget app(Widget home, {Map<String, dynamic>? snap}) {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode(snap ?? snapshot('LOBBY')),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    return ProviderScope(
      overrides: [
        restClientProvider.overrideWithValue(RestClient(client: client)),
      ],
      child: MaterialApp(
        theme: buildTheme(),
        debugShowCheckedModeBanner: false,
        builder: (context, child) => RepaintBoundary(
          key: _shotKey,
          child: Stage(child: child ?? const SizedBox.shrink()),
        ),
        home: home,
      ),
    );
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    if (shotsDir == null) return;
    await tester.runAsync(() async {
      final boundary =
          _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$shotsDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  /// Fixed pumps: the buzzer pulses and the spinners spin, so nothing settles.
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

  for (final MapEntry(key: sizeName, value: size) in sizes.entries) {
    for (final MapEntry(key: caseName, value: c) in cases.entries) {
      testWidgets('$caseName fits a $sizeName screen', (tester) async {
        useSize(tester, size);
        await tester.pumpWidget(
          app(
            c.host
                ? HostGameScreen(session: hostSession())
                : BuzzerScreen(session: playerSession()),
            snap: c.snap,
          ),
        );
        await settle(tester);
        await shoot(tester, '$sizeName/$caseName');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the QR dialog fits a $sizeName screen', (tester) async {
      useSize(tester, size);
      await tester.pumpWidget(
        app(HostGameScreen(session: hostSession()), snap: snapshot('LOBBY')),
      );
      await settle(tester);
      await tester.tap(find.text(L.qrCode));
      await settle(tester);
      await shoot(tester, '$sizeName/qr-dialog');
      expect(tester.takeException(), isNull);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('role picker fits a $sizeName screen', (tester) async {
      useSize(tester, size);
      await tester.pumpWidget(app(const RoleScreen()));
      await settle(tester);
      await shoot(tester, '$sizeName/role');
      expect(tester.takeException(), isNull);
    });

    testWidgets('join form fits a $sizeName screen', (tester) async {
      useSize(tester, size);
      await tester.pumpWidget(app(const JoinScreen()));
      await settle(tester);
      await shoot(tester, '$sizeName/join');
      expect(tester.takeException(), isNull);
    });
  }

  group('on a phone', () {
    testWidgets('the whole board is on screen, not scrolled sideways', (
      tester,
    ) async {
      useSize(tester, sizes['small']!);
      await tester.pumpWidget(
        app(HostGameScreen(session: hostSession()), snap: snapshot('BOARD')),
      );
      await settle(tester);

      // Every column is laid out inside the screen: the last one's right edge
      // is not past it, and nothing is waiting to be scrolled to.
      final lastTile = tester.getRect(find.text('1000').last);
      expect(lastTile.right, lessThanOrEqualTo(360));
      expect(
        find.descendant(
          of: find.byType(HostGameScreen),
          matching: find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal &&
                w.child is Container,
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('upright, the controls sit under the clue', (tester) async {
      useSize(tester, sizes['phone']!);
      await tester.pumpWidget(
        app(
          HostGameScreen(session: hostSession()),
          snap: snapshot('BUZZ_OPEN', clue: clue()),
        ),
      );
      await settle(tester);

      final panel = tester.getRect(find.byType(CluePanel));
      final buzz = tester.getRect(find.text(L.buzz));
      expect(buzz.top, greaterThan(panel.bottom));
    });

    testWidgets('sideways, the controls stand beside the clue', (tester) async {
      useSize(tester, sizes['landscape']!);
      await tester.pumpWidget(
        app(
          HostGameScreen(session: hostSession()),
          snap: snapshot('BUZZ_OPEN', clue: clue()),
        ),
      );
      await settle(tester);

      final panel = tester.getRect(find.byType(CluePanel));
      final buzz = tester.getRect(find.text(L.buzz));
      expect(buzz.left, greaterThan(panel.right));
      // And the clue keeps most of the height: a shelf under it took half.
      expect(panel.height, greaterThan(200));
    });

    testWidgets('two buttons share the bar without breaking a word', (
      tester,
    ) async {
      useSize(tester, sizes['small']!);
      await tester.pumpWidget(
        app(
          HostGameScreen(session: hostSession()),
          snap: snapshot('BUZZ_OPEN', clue: clue()),
        ),
      );
      await settle(tester);

      // One line each: a label that wraps mid-word is two lines tall.
      expect(tester.getSize(find.text(L.pass)).height, lessThan(24));
    });
  });
}

final _shotKey = GlobalKey();
