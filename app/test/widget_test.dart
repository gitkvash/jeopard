import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeopard_app/core/models.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/main.dart';

void main() {
  testWidgets('role picker offers both roles', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JeopardApp()));
    expect(find.text(L.iAmHost), findsOneWidget);
    expect(find.text(L.iAmPlayer), findsOneWidget);
  });

  group('snapshot parsing', () {
    test('maps server state names onto the enum', () {
      expect(GameState.parse('BUZZ_OPEN'), GameState.buzzOpen);
      expect(GameState.parse('CLUE_READING'), GameState.clueReading);
      expect(GameState.parse('FINAL_WAGER'), GameState.finalWager);
      expect(GameState.parse('something-new'), GameState.unknown);
    });

    test('a hidden answer stays null rather than becoming empty text', () {
      final clue = CurrentClue.fromJson({
        'clueId': 7,
        'topicName': 'სრუტეები',
        'value': 30,
        'question': 'კითხვა?',
        'answer': null,
        'correctionNote': null,
        'lockedOutTeamIds': <String>[],
      });
      expect(clue.answer, isNull);
      expect(clue.question, 'კითხვა?');
    });

    test('tile status defaults to available when unknown', () {
      expect(TileStatus.parse('DONE'), TileStatus.done);
      expect(TileStatus.parse('IN_PLAY'), TileStatus.inPlay);
      expect(TileStatus.parse(null), TileStatus.available);
    });

    test('snapshot round-trips the fields the UI depends on', () {
      final snap = Snapshot.fromJson({
        'gameId': 'g1',
        'joinCode': 'ABC234',
        'state': 'BUZZED',
        'hostPlays': true,
        'roundId': 1,
        'roundIdx': 1,
        'finalRound': false,
        'progressRounds': true,
        'packageNumber': 1,
        'packageTitle': 'პაკეტი #1',
        'teams': [
          {
            'id': 't1',
            'name': 'გუნდი ა',
            'score': -30,
            'host': false,
            'seat': 1,
            'wager': null,
            'lockedOutOnCurrentClue': true,
          },
        ],
        'board': [
          {
            'topicId': 1,
            'idx': 1,
            'name': 'სრუტეები',
            'tiles': [
              {'clueId': 1, 'value': 10, 'status': 'DONE', 'wonByTeamId': 't1'},
            ],
          },
        ],
        'currentClue': null,
        'buzzedTeamId': 't1',
        'pickingTeamId': null,
        'answerRevealed': false,
        'answerPeeked': false,
        'tilesRemaining': 29,
        'seq': 12,
        'attribution': 'moazrovne.net',
      });

      expect(snap.state, GameState.buzzed);
      expect(snap.teams.single.score, -30);
      expect(snap.teams.single.lockedOut, isTrue);
      expect(snap.teamById('t1')?.name, 'გუნდი ა');
      expect(snap.board.single.tiles.single.available, isFalse);
      expect(snap.tilesRemaining, 29);
    });
  });
}
