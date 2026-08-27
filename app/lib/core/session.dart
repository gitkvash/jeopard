import 'dart:convert';

import 'models.dart';

/// Everything this device needs to rejoin a game it is already in.
///
/// The server holds all the game state, so a client only has to remember who it
/// is: the game, and the bearer token that proves what it is allowed to do.
/// That makes a browser reload -- which throws away every bit of Dart state --
/// recoverable, as long as this survives it. See [SessionStore].
class GameSession {
  const GameSession({
    required this.gameId,
    required this.joinCode,
    required this.isHost,
    required this.savedAt,
    this.hostToken,
    this.hostTeamId,
    this.playerId,
    this.playerToken,
    this.playerName,
    this.teamId,
    this.teamName,
    this.seat = 0,
  });

  final String gameId;
  final String joinCode;

  /// Which console to rebuild: the host's board or a player's buzzer.
  final bool isHost;
  final DateTime savedAt;

  /// Host only, and the whole point of persisting: without it a reloaded host
  /// can watch the game but not run it.
  final String? hostToken;

  /// Set when the host also plays.
  final String? hostTeamId;

  final String? playerId;
  final String? playerToken;
  final String? playerName;
  final String? teamId;
  final String? teamName;
  final int seat;

  GameSession.fromCreated(CreatedGame created, {DateTime? at})
    : gameId = created.gameId,
      joinCode = created.joinCode,
      isHost = true,
      savedAt = at ?? DateTime.now(),
      hostToken = created.hostToken,
      hostTeamId = created.hostTeamId,
      playerId = created.hostPlayerId,
      playerToken = created.hostPlayerToken,
      playerName = null,
      teamId = created.hostTeamId,
      teamName = null,
      seat = 0;

  GameSession.fromJoined(
    JoinedPlayer joined, {
    required this.joinCode,
    DateTime? at,
  }) : gameId = joined.gameId,
       isHost = false,
       savedAt = at ?? DateTime.now(),
       hostToken = null,
       hostTeamId = null,
       playerId = joined.playerId,
       playerToken = joined.playerToken,
       playerName = joined.playerName,
       teamId = joined.teamId,
       teamName = joined.teamName,
       seat = joined.seat;

  /// Same session, stamped now -- written on entering a game screen so an
  /// evening-long game does not age out mid-play.
  GameSession renew() => GameSession(
    gameId: gameId,
    joinCode: joinCode,
    isHost: isHost,
    savedAt: DateTime.now(),
    hostToken: hostToken,
    hostTeamId: hostTeamId,
    playerId: playerId,
    playerToken: playerToken,
    playerName: playerName,
    teamId: teamId,
    teamName: teamName,
    seat: seat,
  );

  /// A host session is only usable if we still hold the host token; a player
  /// session needs its player token. Anything else is a half-written record.
  bool get isUsable =>
      gameId.isNotEmpty &&
      (isHost ? (hostToken ?? '').isNotEmpty : (playerToken ?? '').isNotEmpty);

  Map<String, dynamic> toJson() => {
    'gameId': gameId,
    'joinCode': joinCode,
    'isHost': isHost,
    'savedAt': savedAt.toIso8601String(),
    if (hostToken != null) 'hostToken': hostToken,
    if (hostTeamId != null) 'hostTeamId': hostTeamId,
    if (playerId != null) 'playerId': playerId,
    if (playerToken != null) 'playerToken': playerToken,
    if (playerName != null) 'playerName': playerName,
    if (teamId != null) 'teamId': teamId,
    if (teamName != null) 'teamName': teamName,
    'seat': seat,
  };

  static GameSession? fromJson(Map<String, dynamic> j) {
    final gameId = j['gameId'];
    if (gameId is! String || gameId.isEmpty) return null;
    return GameSession(
      gameId: gameId,
      joinCode: j['joinCode'] as String? ?? '',
      isHost: j['isHost'] as bool? ?? false,
      savedAt:
          DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime.now(),
      hostToken: j['hostToken'] as String?,
      hostTeamId: j['hostTeamId'] as String?,
      playerId: j['playerId'] as String?,
      playerToken: j['playerToken'] as String?,
      playerName: j['playerName'] as String?,
      teamId: j['teamId'] as String?,
      teamName: j['teamName'] as String?,
      seat: (j['seat'] as num?)?.toInt() ?? 0,
    );
  }

  String encode() => jsonEncode(toJson());

  static GameSession? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final session = fromJson(decoded);
      return (session != null && session.isUsable) ? session : null;
    } catch (_) {
      // Corrupt or from an older shape: treat as no session at all.
      return null;
    }
  }
}
