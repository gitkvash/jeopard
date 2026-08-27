import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeopard_app/core/models.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/widgets/board_grid.dart';
import 'package:jeopard_app/widgets/clue_panel.dart';
import 'package:jeopard_app/widgets/scoreboard.dart';

/// Wraps a widget in enough app scaffolding to lay out, with a fixed size so
/// the Expanded-based board has bounded height.
Widget host(Widget child, {Size size = const Size(900, 700)}) {
  return MaterialApp(
    theme: buildTheme(),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );
}

BoardColumn column(int idx, String name, List<int> values,
    {Set<int> doneValues = const {}}) {
  return BoardColumn(
    topicId: idx,
    idx: idx,
    name: name,
    tiles: values
        .map((v) => TileView(
              clueId: idx * 100 + v,
              value: v,
              status: doneValues.contains(v)
                  ? TileStatus.done
                  : TileStatus.available,
              wonByTeamId: null,
            ))
        .toList(),
  );
}

List<BoardColumn> fullBoard({Set<int> doneValues = const {}}) => [
      for (var i = 1; i <= 6; i++)
        column(i, 'თემა $i', const [10, 20, 30, 40, 50],
            doneValues: i == 1 ? doneValues : const {}),
    ];

void main() {
  group('BoardGrid', () {
    testWidgets('renders every topic name and tile value', (tester) async {
      await tester.pumpWidget(host(BoardGrid(
        board: fullBoard(),
        onTapTile: (_) {},
      )));

      for (var i = 1; i <= 6; i++) {
        expect(find.text('თემა $i'.toUpperCase()), findsOneWidget);
      }
      // Six columns each carrying the same five values.
      expect(find.text('10'), findsNWidgets(6));
      expect(find.text('50'), findsNWidgets(6));
    });

    testWidgets('a spent tile shows a check instead of its value',
        (tester) async {
      await tester.pumpWidget(host(BoardGrid(
        board: fullBoard(doneValues: {30}),
        onTapTile: (_) {},
      )));

      // Column 1's 30 is spent, so only the other five columns show it.
      expect(find.text('30'), findsNWidgets(5));
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('tapping an available tile reports that tile', (tester) async {
      TileView? tapped;
      await tester.pumpWidget(host(BoardGrid(
        board: fullBoard(),
        onTapTile: (t) => tapped = t,
      )));

      await tester.tap(find.text('20').first);
      await tester.pump();

      expect(tapped, isNotNull);
      expect(tapped!.value, 20);
    });

    testWidgets('a spent tile is not tappable', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(BoardGrid(
        board: [column(1, 'თემა', const [10], doneValues: {10})],
        onTapTile: (_) => taps++,
      )));

      await tester.tap(find.byIcon(Icons.check));
      await tester.pump();

      expect(taps, 0);
    });

    testWidgets('team devices cannot drive the board', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(BoardGrid(
        board: fullBoard(),
        interactive: false,
        onTapTile: (_) => taps++,
      )));

      await tester.tap(find.text('40').first);
      await tester.pump();

      expect(taps, 0);
    });
  });

  group('CluePanel', () {
    CurrentClue clue({String? answer, String? note}) => CurrentClue(
          clueId: 1,
          topicName: 'სრუტეები',
          value: 30,
          question: 'რომელი სრუტე?',
          answer: answer,
          correctionNote: note,
          lockedOutTeamIds: const [],
        );

    testWidgets('shows the question and the value', (tester) async {
      await tester.pumpWidget(host(CluePanel(clue: clue())));
      expect(find.text('რომელი სრუტე?'), findsOneWidget);
      // Category and value are shown prominently so team devices can see what
      // the host picked.
      expect(find.text('30 ${L.points}'), findsOneWidget);
      expect(find.text('სრუტეები'.toUpperCase()), findsOneWidget);
    });

    testWidgets('withholds the answer while showAnswer is false',
        (tester) async {
      // Even if an answer somehow reached the widget, it must not be painted
      // until the reveal flag is set.
      await tester.pumpWidget(host(CluePanel(
        clue: clue(answer: 'ბოსფორი'),
        showAnswer: false,
      )));

      expect(find.text('ბოსფორი'), findsNothing);
      expect(find.text(L.answer.toUpperCase()), findsNothing);
    });

    testWidgets('reveals the answer and any correction note', (tester) async {
      await tester.pumpWidget(host(CluePanel(
        clue: clue(answer: 'ბოსფორი', note: 'შესწორება: 42-ე პრეზიდენტი'),
        showAnswer: true,
      )));

      expect(find.text('ბოსფორი'), findsOneWidget);
      expect(find.text(L.answer.toUpperCase()), findsOneWidget);
      expect(find.text('შესწორება: 42-ე პრეზიდენტი'), findsOneWidget);
    });

    testWidgets('a null answer stays hidden even when revealed',
        (tester) async {
      await tester.pumpWidget(host(CluePanel(clue: clue(), showAnswer: true)));
      expect(find.text(L.answer.toUpperCase()), findsNothing);
    });

    testWidgets('long questions scroll rather than overflow', (tester) async {
      final long = 'ქართული ' * 120;
      await tester.pumpWidget(host(
        CluePanel(
          clue: CurrentClue(
            clueId: 1,
            topicName: 'თემა',
            value: 50,
            question: long,
            answer: null,
            correctionNote: null,
            lockedOutTeamIds: const [],
          ),
        ),
        size: const Size(360, 420),
      ));

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  group('Scoreboard', () {
    TeamView team(String id, String name, int score,
            {bool lockedOut = false, bool isHost = false, int? wager}) =>
        TeamView(
          id: id,
          name: name,
          score: score,
          host: isHost,
          seat: 1,
          wager: wager,
          lockedOut: lockedOut,
        );

    testWidgets('shows each team with its score, negatives included',
        (tester) async {
      await tester.pumpWidget(host(Scoreboard(teams: [
        team('a', 'გუნდი ა', -30),
        team('b', 'გუნდი ბ', 120),
      ])));

      expect(find.text('გუნდი ა'), findsOneWidget);
      expect(find.text('-30'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
    });

    testWidgets('strikes through a team locked out of the current clue',
        (tester) async {
      await tester.pumpWidget(host(Scoreboard(teams: [
        team('a', 'გუნდი ა', 0, lockedOut: true),
      ])));

      final label = tester.widget<Text>(find.text('გუნდი ა'));
      expect(label.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('marks the host team with an icon', (tester) async {
      await tester.pumpWidget(host(Scoreboard(teams: [
        team('h', 'მასპინძელი', 0, isHost: true),
      ])));

      expect(find.byIcon(Icons.co_present_outlined), findsOneWidget);
    });

    testWidgets('shows a final-round wager when one is set', (tester) async {
      await tester.pumpWidget(host(Scoreboard(teams: [
        team('a', 'გუნდი ა', 300, wager: 250),
      ])));

      expect(find.text('${L.wager}: 250'), findsOneWidget);
    });

    testWidgets('says so when nobody has joined', (tester) async {
      await tester.pumpWidget(host(const Scoreboard(teams: [])));
      expect(find.text(L.noTeamsYet), findsOneWidget);
    });
  });
}
