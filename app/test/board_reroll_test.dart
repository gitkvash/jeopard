import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeopard_app/core/models.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/widgets/board_grid.dart';

BoardColumn column(int id, {bool played = false}) => BoardColumn(
  topicId: id,
  idx: id,
  name: 'კატეგორია $id',
  tiles: [
    for (var i = 1; i <= 5; i++)
      TileView(
        clueId: id * 10 + i,
        value: i * 10,
        status: played && i == 1 ? TileStatus.done : TileStatus.available,
        wonByTeamId: null,
      ),
  ],
);

Widget app(List<BoardColumn> board, void Function(BoardColumn)? onReroll) =>
    MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          height: 700,
          child: BoardGrid(
            board: board,
            onTapTile: (_) {},
            onRerollTopic: onReroll,
          ),
        ),
      ),
    );

void main() {
  testWidgets('only a category nothing was taken from offers a swap', (
    tester,
  ) async {
    BoardColumn? asked;
    await tester.pumpWidget(
      app([column(1, played: true), column(2), column(3)], (c) => asked = c),
    );

    // Two untouched columns, one played-from: two swap buttons.
    expect(find.byIcon(Icons.refresh), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.refresh).first);
    expect(asked?.topicId, 2);
  });

  testWidgets('no swap buttons when the host cannot swap (curated package)', (
    tester,
  ) async {
    await tester.pumpWidget(app([column(1), column(2)], null));
    expect(find.byIcon(Icons.refresh), findsNothing);
  });
}
