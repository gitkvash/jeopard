import 'game_feed.dart';
import 'models.dart';
import 'sfx.dart';

/// Whose ears a device is for.
///
/// The host's screen is the room's loudspeaker -- the one that is on a laptop or
/// a TV where everybody can hear it -- so it plays the whole show. A team's
/// phone is in one person's hand, often next to four others, so it plays only
/// what that team needs to know: the buzzer going live, its own buzz, its own
/// ruling. Otherwise a table of six phones is six overlapping buzzers.
enum SoundRole { host, team }

/// A cue and how long after the snapshot it should sound.
class TimedCue {
  const TimedCue(this.cue, [this.delayMs = 0]);

  final Cue cue;
  final int delayMs;

  @override
  bool operator ==(Object other) =>
      other is TimedCue && other.cue == cue && other.delayMs == delayMs;

  @override
  int get hashCode => Object.hash(cue, delayMs);

  @override
  String toString() => delayMs == 0 ? '$cue' : '$cue+${delayMs}ms';
}

/// Which sounds a change from [prev] to [next] deserves.
///
/// Pure, so the whole soundtrack can be tested without an audio device. The
/// server keeps no event log -- only state -- so this works out what happened
/// from the difference between two snapshots, using what the backend does:
/// a ruling is the only thing that moves a score while a team holds the buzzer
/// (`GameService.judge`) or while the final clue is up (`finalJudge`).
List<TimedCue> cuesFor(
  Snapshot prev,
  Snapshot next, {
  required SoundRole role,
  String? myTeamId,
}) {
  // A stale or repeated frame is not an event. A big jump means this device was
  // asleep or offline and has just caught up: announcing a clue that ended a
  // minute ago would be noise, not information.
  if (next.seq <= prev.seq || next.seq - prev.seq > _maxSeqJump) {
    return const [];
  }

  final host = role == SoundRole.host;
  final from = prev.state;
  final to = next.state;
  final out = <TimedCue>[];

  // ---- rulings ----
  Cue? verdict;
  if (from == GameState.buzzed || from == GameState.finalClue) {
    var gained = false;
    var lost = false;
    for (final team in next.teams) {
      if (!host && team.id != myTeamId) continue;
      final before = prev.teamById(team.id);
      if (before == null) continue;
      if (team.score > before.score) gained = true;
      if (team.score < before.score) lost = true;
    }
    verdict = gained
        ? Cue.correct
        : lost
        ? Cue.wrong
        : null;
  }
  if (verdict != null) out.add(TimedCue(verdict));

  // The answer went up and nobody earned or lost anything for it.
  if (host &&
      to == GameState.resolved &&
      from != GameState.resolved &&
      verdict == null) {
    out.add(const TimedCue(Cue.noAnswer));
  }

  // ---- phase changes ----
  if (from == to) return out;

  final iAmLockedOut = next.teamById(myTeamId)?.lockedOut ?? false;
  final pingForMe = host || !iAmLockedOut;

  switch (to) {
    case GameState.board:
      if (host && (from == GameState.lobby || next.roundId != prev.roundId)) {
        out.add(const TimedCue(Cue.roundStart));
      }
    case GameState.clueReading:
      if (host) out.add(const TimedCue(Cue.cluePick));
    case GameState.buzzOpen:
      if (from == GameState.board) {
        // Instant mode: the tile and the live buzzer arrive in one snapshot.
        if (host) out.add(const TimedCue(Cue.cluePick));
        if (pingForMe) out.add(const TimedCue(Cue.buzzOpen, 350));
      } else if (pingForMe) {
        // Reopened after a wrong answer: let the buzzer finish first, or the
        // two land on top of each other and the ping is lost.
        out.add(TimedCue(Cue.buzzOpen, verdict == Cue.wrong ? 900 : 0));
      }
    case GameState.buzzed:
      if (host || next.buzzedTeamId == myTeamId) {
        out.add(const TimedCue(Cue.buzzIn));
      }
    case GameState.finalWager:
      out.add(const TimedCue(Cue.finalIntro));
    case GameState.finalClue:
      out.add(const TimedCue(Cue.buzzOpen));
    case GameState.finished:
      out.add(const TimedCue(Cue.finale));
    case GameState.lobby ||
        GameState.resolved ||
        GameState.finalResult ||
        GameState.unknown:
      break;
  }
  return out;
}

const _maxSeqJump = 3;

/// Plays [cuesFor] as a [GameFeed] changes. Owned by a screen, created next to
/// its feed and disposed with it.
class GameSounds {
  GameSounds(this._feed, {required this.role, this.myTeamId, Sfx? sfx})
    : _sfx = sfx ?? Sfx.instance {
    _last = _feed.snapshot;
    _feed.addListener(_onFeed);
  }

  final GameFeed _feed;
  final SoundRole role;
  final String? myTeamId;
  final Sfx _sfx;

  Snapshot? _last;

  void _onFeed() {
    final next = _feed.snapshot;
    // The feed also notifies when only the connection changed.
    if (next == null || identical(next, _last)) return;
    final prev = _last;
    _last = next;
    // The first snapshot is a baseline, not news: opening or reloading the app
    // in the middle of a game must not replay its last event.
    if (prev == null) return;

    for (final c in cuesFor(prev, next, role: role, myTeamId: myTeamId)) {
      _sfx.play(c.cue, delay: Duration(milliseconds: c.delayMs));
    }
  }

  void dispose() => _feed.removeListener(_onFeed);
}
