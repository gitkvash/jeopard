import 'models.dart';
import 'theme.dart';

/// What to say for a [Notice], or null when it is not worth interrupting for.
///
/// A person who was moved hears it addressed to them ("you were moved"); everyone
/// else hears who went where. [myPlayerId] is the listening device's own player,
/// null on a host who is not playing.
String? describeNotice(Notice n, {String? myPlayerId}) {
  if (n.isScore) {
    final team = n.teamName;
    final before = n.scoreBefore;
    final after = n.scoreAfter;
    if (team == null || before == null || after == null) return null;
    return L.scoreChanged(team, before, after);
  }
  if (n.isMove) {
    final player = n.playerName;
    if (player == null) return null;
    return n.playerId != null && n.playerId == myPlayerId
        ? L.youWereMoved(n.toTeamName)
        : L.playerMoved(player, n.toTeamName);
  }
  return null;
}
