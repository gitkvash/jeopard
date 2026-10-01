import 'package:flutter_test/flutter_test.dart';
import 'package:jeopard_app/core/game_feed.dart';
import 'package:jeopard_app/core/game_sounds.dart';
import 'package:jeopard_app/core/models.dart';
import 'package:jeopard_app/core/sfx.dart';
import 'package:jeopard_app/core/sfx_backend.dart';

/// A snapshot with two teams, `a` and `b`, built the way the app builds them:
/// from the wire format.
Snapshot snap({
  required int seq,
  required String state,
  int a = 0,
  int b = 0,
  bool aLocked = false,
  String? buzzed,
  int roundId = 1,
}) {
  Map<String, dynamic> team(String id, int score, bool locked) => {
    'id': id,
    'name': id,
    'score': score,
    'host': false,
    'seat': 0,
    'lockedOutOnCurrentClue': locked,
  };
  return Snapshot.fromJson({
    'gameId': 'g',
    'joinCode': 'ABC123',
    'state': state,
    'roundId': roundId,
    'seq': seq,
    'buzzedTeamId': buzzed,
    'teams': [team('a', a, aLocked), team('b', b, false)],
  });
}

List<Cue> cues(
  Snapshot prev,
  Snapshot next, {
  SoundRole role = SoundRole.host,
  String? me,
}) => [for (final c in cuesFor(prev, next, role: role, myTeamId: me)) c.cue];

void main() {
  group('host: the whole show', () {
    test('picking a tile and the buzzer opening on a timer', () {
      final board = snap(seq: 1, state: 'BOARD');
      final reading = snap(seq: 2, state: 'CLUE_READING');
      final open = snap(seq: 3, state: 'BUZZ_OPEN');

      expect(cues(board, reading), [Cue.cluePick]);
      expect(cues(reading, open), [Cue.buzzOpen]);
    });

    test('instant mode: the tile and the live buzzer in one snapshot', () {
      final out = cuesFor(
        snap(seq: 1, state: 'BOARD'),
        snap(seq: 2, state: 'BUZZ_OPEN'),
        role: SoundRole.host,
      );
      expect(out, const [
        TimedCue(Cue.cluePick),
        TimedCue(Cue.buzzOpen, 350),
      ]);
    });

    test('a buzz, then a correct ruling', () {
      final open = snap(seq: 1, state: 'BUZZ_OPEN');
      final buzzed = snap(seq: 2, state: 'BUZZED', buzzed: 'a');
      final done = snap(seq: 3, state: 'RESOLVED', a: 30);

      expect(cues(open, buzzed), [Cue.buzzIn]);
      expect(cues(buzzed, done), [Cue.correct]);
    });

    test('a wrong ruling reopens the buzzer, but after the buzzer sound', () {
      final out = cuesFor(
        snap(seq: 1, state: 'BUZZED', buzzed: 'a', a: 30),
        snap(seq: 2, state: 'BUZZ_OPEN', a: 0),
        role: SoundRole.host,
      );
      expect(out, const [
        TimedCue(Cue.wrong),
        TimedCue(Cue.buzzOpen, 900),
      ]);
    });

    test('a wrong ruling with nobody left is a wrong, not also "no answer"', () {
      expect(
        cues(
          snap(seq: 1, state: 'BUZZED', buzzed: 'a', a: 30),
          snap(seq: 2, state: 'RESOLVED', a: 0),
        ),
        [Cue.wrong],
      );
    });

    test('a clue nobody scored on', () {
      expect(
        cues(
          snap(seq: 1, state: 'BUZZ_OPEN'),
          snap(seq: 2, state: 'RESOLVED'),
        ),
        [Cue.noAnswer],
      );
    });

    test('revealing the answer while a team holds the buzzer is no answer', () {
      expect(
        cues(
          snap(seq: 1, state: 'BUZZED', buzzed: 'a'),
          snap(seq: 2, state: 'RESOLVED'),
        ),
        [Cue.noAnswer],
      );
    });

    test('starting the game and the next round announce a board', () {
      expect(
        cues(snap(seq: 1, state: 'LOBBY'), snap(seq: 2, state: 'BOARD')),
        [Cue.roundStart],
      );
      expect(
        cues(
          snap(seq: 1, state: 'RESOLVED'),
          snap(seq: 2, state: 'BOARD', roundId: 2),
        ),
        [Cue.roundStart],
      );
      // Back to the same round's board after a clue: no fanfare.
      expect(
        cues(snap(seq: 1, state: 'RESOLVED'), snap(seq: 2, state: 'BOARD')),
        isEmpty,
      );
    });

    test('the final: intro, question, rulings, finale', () {
      expect(
        cues(snap(seq: 1, state: 'BOARD'), snap(seq: 2, state: 'FINAL_WAGER')),
        [Cue.finalIntro],
      );
      expect(
        cues(
          snap(seq: 1, state: 'FINAL_WAGER'),
          snap(seq: 2, state: 'FINAL_CLUE'),
        ),
        [Cue.buzzOpen],
      );
      // One team judged, the clue still up: the score moves inside FINAL_CLUE.
      expect(
        cues(
          snap(seq: 1, state: 'FINAL_CLUE', a: 100),
          snap(seq: 2, state: 'FINAL_CLUE', a: 40),
        ),
        [Cue.wrong],
      );
      expect(
        cues(
          snap(seq: 1, state: 'FINAL_RESULT'),
          snap(seq: 2, state: 'FINISHED'),
        ),
        [Cue.finale],
      );
    });

    test('a score that moves outside a ruling is not a verdict', () {
      expect(
        cues(
          snap(seq: 1, state: 'BOARD', a: 10),
          snap(seq: 2, state: 'BOARD', a: 0),
        ),
        isEmpty,
      );
    });
  });

  group('team: only what concerns this team', () {
    test('its own buzz, not a rival\'s', () {
      final open = snap(seq: 1, state: 'BUZZ_OPEN');
      expect(
        cues(
          open,
          snap(seq: 2, state: 'BUZZED', buzzed: 'a'),
          role: SoundRole.team,
          me: 'a',
        ),
        [Cue.buzzIn],
      );
      expect(
        cues(
          open,
          snap(seq: 2, state: 'BUZZED', buzzed: 'b'),
          role: SoundRole.team,
          me: 'a',
        ),
        isEmpty,
      );
    });

    test('its own ruling, not another team\'s', () {
      final before = snap(seq: 1, state: 'BUZZED', buzzed: 'b');
      final after = snap(seq: 2, state: 'RESOLVED', b: 30);
      expect(cues(before, after, role: SoundRole.team, me: 'b'), [Cue.correct]);
      expect(cues(before, after, role: SoundRole.team, me: 'a'), isEmpty);
    });

    test('the ping, unless locked out of this clue', () {
      final reading = snap(seq: 1, state: 'CLUE_READING');
      expect(
        cues(
          reading,
          snap(seq: 2, state: 'BUZZ_OPEN'),
          role: SoundRole.team,
          me: 'a',
        ),
        [Cue.buzzOpen],
      );
      expect(
        cues(
          reading,
          snap(seq: 2, state: 'BUZZ_OPEN', aLocked: true),
          role: SoundRole.team,
          me: 'a',
        ),
        isEmpty,
      );
    });

    test('no tile, round or "no answer" sounds from a phone', () {
      expect(
        cues(
          snap(seq: 1, state: 'BOARD'),
          snap(seq: 2, state: 'CLUE_READING'),
          role: SoundRole.team,
          me: 'a',
        ),
        isEmpty,
      );
      expect(
        cues(
          snap(seq: 1, state: 'BUZZ_OPEN'),
          snap(seq: 2, state: 'RESOLVED'),
          role: SoundRole.team,
          me: 'a',
        ),
        isEmpty,
      );
    });
  });

  group('frames that are not events', () {
    test('a repeated or older frame', () {
      final a = snap(seq: 5, state: 'BOARD');
      expect(cues(a, snap(seq: 5, state: 'CLUE_READING')), isEmpty);
      expect(cues(a, snap(seq: 4, state: 'CLUE_READING')), isEmpty);
    });

    test('a device that missed several frames stays quiet', () {
      expect(
        cues(snap(seq: 1, state: 'BOARD'), snap(seq: 9, state: 'RESOLVED')),
        isEmpty,
      );
    });

    test('a connection change with the same snapshot', () {
      final s = snap(seq: 1, state: 'BOARD');
      expect(cues(s, s), isEmpty);
    });
  });

  group('GameSounds', () {
    test('mute silences it, and the first snapshot is only a baseline', () async {
      final backend = _RecordingBackend();
      final sfx = Sfx.test(backend);
      final feed = GameFeed(gameId: 'g');
      addTearDown(feed.dispose);
      final sounds = GameSounds(feed, role: SoundRole.host, sfx: sfx);
      addTearDown(sounds.dispose);

      feed.push(snap(seq: 1, state: 'BOARD'));
      await pumpEventQueue();
      expect(backend.played, isEmpty, reason: 'a reload must not replay');

      feed.push(snap(seq: 2, state: 'CLUE_READING'));
      await pumpEventQueue();
      expect(backend.played, ['clue_pick']);

      sfx.toggleMuted();
      feed.push(snap(seq: 3, state: 'BUZZ_OPEN'));
      await pumpEventQueue();
      expect(backend.played, ['clue_pick'], reason: 'muted');
    });
  });
}

class _RecordingBackend implements SfxBackend {
  final played = <String>[];

  @override
  bool get audible => true;

  @override
  Future<void> load(String name, String assetPath) async {}

  @override
  void play(String name, double volume) => played.add(name);
}
