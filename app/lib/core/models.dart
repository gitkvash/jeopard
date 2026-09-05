/// Wire models mirroring the backend's GameDtos / ContentDtos.
///
/// Hand-written fromJson rather than codegen: the shapes are small and stable,
/// and it keeps the build to a plain `flutter run` with no build_runner step.
library;

enum GameState {
  lobby,
  board,
  clueReading,
  buzzOpen,
  buzzed,
  resolved,
  finalWager,
  finalClue,
  finalResult,
  finished,
  unknown;

  static GameState parse(String? raw) => switch (raw) {
    'LOBBY' => GameState.lobby,
    'BOARD' => GameState.board,
    'CLUE_READING' => GameState.clueReading,
    'BUZZ_OPEN' => GameState.buzzOpen,
    'BUZZED' => GameState.buzzed,
    'RESOLVED' => GameState.resolved,
    'FINAL_WAGER' => GameState.finalWager,
    'FINAL_CLUE' => GameState.finalClue,
    'FINAL_RESULT' => GameState.finalResult,
    'FINISHED' => GameState.finished,
    _ => GameState.unknown,
  };
}

/// How the buzzer goes live once a clue is on screen.
///
/// The server enforces whichever of these a game was created with; the client
/// only needs to know which one so it can say so and, on a timer, count down.
enum BuzzMode {
  /// The host presses the button when they have finished reading.
  host,

  /// Live the moment the clue appears.
  instant,

  /// Live by itself after a set number of seconds.
  timer;

  static BuzzMode parse(String? raw) => switch (raw) {
    'INSTANT' => BuzzMode.instant,
    'TIMER' => BuzzMode.timer,
    _ => BuzzMode.host,
  };

  String get wire => switch (this) {
    BuzzMode.host => 'HOST',
    BuzzMode.instant => 'INSTANT',
    BuzzMode.timer => 'TIMER',
  };
}

enum TileStatus {
  available,
  inPlay,
  done;

  static TileStatus parse(String? raw) => switch (raw) {
    'IN_PLAY' => TileStatus.inPlay,
    'DONE' => TileStatus.done,
    _ => TileStatus.available,
  };
}

class RoundSummary {
  RoundSummary({
    required this.id,
    required this.idx,
    required this.finalRound,
    required this.playable,
    required this.topicCount,
  });

  final int id;
  final int idx;
  final bool finalRound;
  final bool playable;
  final int topicCount;

  factory RoundSummary.fromJson(Map<String, dynamic> j) => RoundSummary(
    id: j['id'] as int,
    idx: j['idx'] as int,
    finalRound: j['finalRound'] as bool? ?? false,
    playable: j['playable'] as bool? ?? false,
    topicCount: j['topicCount'] as int? ?? 0,
  );
}

class PackageSummary {
  PackageSummary({
    required this.id,
    required this.number,
    required this.title,
    required this.subtitle,
    required this.sourceUrl,
    required this.rounds,
  });

  final int id;
  final int number;
  final String title;
  final String? subtitle;

  /// Where the questions came from. Generated packages carry a
  /// `generated:<model>` marker, set when the set is merged, so the picker can
  /// separate them from the 2008 archive without matching on subtitle text.
  final String? sourceUrl;
  final List<RoundSummary> rounds;

  bool get generated => sourceUrl?.startsWith('generated') ?? false;

  factory PackageSummary.fromJson(Map<String, dynamic> j) => PackageSummary(
    id: j['id'] as int,
    number: j['number'] as int,
    title: j['title'] as String,
    subtitle: j['subtitle'] as String?,
    sourceUrl: j['sourceUrl'] as String?,
    rounds: (j['rounds'] as List<dynamic>? ?? const [])
        .map((r) => RoundSummary.fromJson(r as Map<String, dynamic>))
        .toList(),
  );
}

/// One person on one device. Several players may share a [TeamView].
class PlayerView {
  PlayerView({required this.id, required this.name, required this.host});

  final String id;
  final String name;
  final bool host;

  factory PlayerView.fromJson(Map<String, dynamic> j) => PlayerView(
    id: j['id'] as String,
    name: j['name'] as String,
    host: j['host'] as bool? ?? false,
  );
}

/// The scoring unit. Score, wager and per-clue lockout all belong to the team,
/// not to the individual who happened to buzz.
class TeamView {
  TeamView({
    required this.id,
    required this.name,
    required this.score,
    required this.host,
    required this.seat,
    required this.wager,
    required this.lockedOut,
    this.players = const [],
  });

  final String id;
  final String name;
  final int score;
  final bool host;
  final int seat;
  final int? wager;
  final bool lockedOut;
  final List<PlayerView> players;

  factory TeamView.fromJson(Map<String, dynamic> j) => TeamView(
    id: j['id'] as String,
    name: j['name'] as String,
    score: j['score'] as int? ?? 0,
    host: j['host'] as bool? ?? false,
    seat: j['seat'] as int? ?? 0,
    wager: j['wager'] as int?,
    lockedOut: j['lockedOutOnCurrentClue'] as bool? ?? false,
    players: (j['players'] as List<dynamic>? ?? const [])
        .map((p) => PlayerView.fromJson(p as Map<String, dynamic>))
        .toList(),
  );
}

class TileView {
  TileView({
    required this.clueId,
    required this.value,
    required this.status,
    required this.wonByTeamId,
  });

  final int clueId;
  final int? value;
  final TileStatus status;
  final String? wonByTeamId;

  bool get available => status == TileStatus.available;

  factory TileView.fromJson(Map<String, dynamic> j) => TileView(
    clueId: j['clueId'] as int,
    value: j['value'] as int?,
    status: TileStatus.parse(j['status'] as String?),
    wonByTeamId: j['wonByTeamId'] as String?,
  );
}

class BoardColumn {
  BoardColumn({
    required this.topicId,
    required this.idx,
    required this.name,
    required this.tiles,
  });

  final int topicId;
  final int idx;
  final String name;
  final List<TileView> tiles;

  factory BoardColumn.fromJson(Map<String, dynamic> j) => BoardColumn(
    topicId: j['topicId'] as int,
    idx: j['idx'] as int? ?? 0,
    name: j['name'] as String,
    tiles: (j['tiles'] as List<dynamic>? ?? const [])
        .map((t) => TileView.fromJson(t as Map<String, dynamic>))
        .toList(),
  );
}

/// The clue in play. [answer] is null until the host reveals it -- the server
/// simply does not send it before then.
class CurrentClue {
  CurrentClue({
    required this.clueId,
    required this.topicName,
    required this.value,
    required this.question,
    required this.answer,
    required this.correctionNote,
    required this.lockedOutTeamIds,
  });

  final int clueId;
  final String topicName;
  final int? value;
  final String? question;
  final String? answer;
  final String? correctionNote;
  final List<String> lockedOutTeamIds;

  /// Only ever used to overlay a question the host fetched on the side (a
  /// host-token'd snapshot fetch, when the game hides it from participants) or
  /// an explanation of why a team's device is not getting one -- every other
  /// field stays what the server sent.
  CurrentClue copyWith({String? question}) => CurrentClue(
    clueId: clueId,
    topicName: topicName,
    value: value,
    question: question ?? this.question,
    answer: answer,
    correctionNote: correctionNote,
    lockedOutTeamIds: lockedOutTeamIds,
  );

  factory CurrentClue.fromJson(Map<String, dynamic> j) => CurrentClue(
    clueId: j['clueId'] as int,
    topicName: j['topicName'] as String? ?? '',
    value: j['value'] as int?,
    question: j['question'] as String?,
    answer: j['answer'] as String?,
    correctionNote: j['correctionNote'] as String?,
    lockedOutTeamIds: (j['lockedOutTeamIds'] as List<dynamic>? ?? const [])
        .map((e) => e as String)
        .toList(),
  );
}

class Snapshot {
  Snapshot({
    required this.gameId,
    required this.joinCode,
    required this.state,
    required this.hostPlays,
    required this.roundId,
    required this.roundIdx,
    required this.finalRound,
    required this.progressRounds,
    required this.packageNumber,
    required this.packageTitle,
    required this.teams,
    required this.board,
    required this.currentClue,
    required this.buzzedTeamId,
    required this.buzzedPlayerId,
    required this.pickingTeamId,
    required this.answerRevealed,
    required this.answerPeeked,
    required this.tilesRemaining,
    required this.buzzMode,
    required this.buzzDelaySeconds,
    required this.buzzOpensInMs,
    required this.questionsVisibleToParticipants,
    required this.seq,
    required this.attribution,
  });

  final String gameId;
  final String joinCode;
  final GameState state;
  final bool hostPlays;
  final int roundId;
  final int roundIdx;
  final bool finalRound;

  /// True when this game walks the whole package (boards 1-3 then the final)
  /// rather than a single round.
  final bool progressRounds;
  final int? packageNumber;
  final String? packageTitle;
  final List<TeamView> teams;
  final List<BoardColumn> board;
  final CurrentClue? currentClue;
  final String? buzzedTeamId;

  /// The member of [buzzedTeamId] who actually hit the button.
  final String? buzzedPlayerId;
  final String? pickingTeamId;
  final bool answerRevealed;
  final bool answerPeeked;
  final int tilesRemaining;

  /// How this game opens its buzzer, chosen when the game was created.
  final BuzzMode buzzMode;

  /// Reading time on a [BuzzMode.timer] game, in seconds.
  final int buzzDelaySeconds;

  /// What is left of that reading time when this snapshot was built, or null
  /// when nothing is counting. A remaining duration rather than a deadline, so
  /// a device with a wrong clock still counts down correctly.
  final int? buzzOpensInMs;

  /// False when this game keeps the clue text off a participant's own device.
  /// The host always gets it regardless, fetched with the host token, so this
  /// never affects the host's own screen.
  final bool questionsVisibleToParticipants;

  final int seq;
  final String? attribution;

  TeamView? teamById(String? id) {
    if (id == null) return null;
    for (final t in teams) {
      if (t.id == id) return t;
    }
    return null;
  }

  factory Snapshot.fromJson(Map<String, dynamic> j) => Snapshot(
    gameId: j['gameId'] as String,
    joinCode: j['joinCode'] as String,
    state: GameState.parse(j['state'] as String?),
    hostPlays: j['hostPlays'] as bool? ?? false,
    roundId: j['roundId'] as int,
    roundIdx: j['roundIdx'] as int? ?? 0,
    finalRound: j['finalRound'] as bool? ?? false,
    progressRounds: j['progressRounds'] as bool? ?? false,
    packageNumber: j['packageNumber'] as int?,
    packageTitle: j['packageTitle'] as String?,
    teams: (j['teams'] as List<dynamic>? ?? const [])
        .map((t) => TeamView.fromJson(t as Map<String, dynamic>))
        .toList(),
    board: (j['board'] as List<dynamic>? ?? const [])
        .map((c) => BoardColumn.fromJson(c as Map<String, dynamic>))
        .toList(),
    currentClue: j['currentClue'] == null
        ? null
        : CurrentClue.fromJson(j['currentClue'] as Map<String, dynamic>),
    buzzedTeamId: j['buzzedTeamId'] as String?,
    buzzedPlayerId: j['buzzedPlayerId'] as String?,
    pickingTeamId: j['pickingTeamId'] as String?,
    answerRevealed: j['answerRevealed'] as bool? ?? false,
    answerPeeked: j['answerPeeked'] as bool? ?? false,
    tilesRemaining: j['tilesRemaining'] as int? ?? 0,
    buzzMode: BuzzMode.parse(j['buzzMode'] as String?),
    buzzDelaySeconds: j['buzzDelaySeconds'] as int? ?? 0,
    buzzOpensInMs: (j['buzzOpensInMs'] as num?)?.toInt(),
    questionsVisibleToParticipants:
        j['questionsVisibleToParticipants'] as bool? ?? true,
    seq: (j['seq'] as num?)?.toInt() ?? 0,
    attribution: j['attribution'] as String?,
  );
}

/// Returned when the host creates a game.
class CreatedGame {
  CreatedGame({
    required this.gameId,
    required this.joinCode,
    required this.hostToken,
    required this.hostTeamId,
    required this.hostPlayerId,
    required this.hostPlayerToken,
  });

  final String gameId;
  final String joinCode;
  final String hostToken;

  /// All three are present only when the host is also playing.
  final String? hostTeamId;
  final String? hostPlayerId;
  final String? hostPlayerToken;

  factory CreatedGame.fromJson(Map<String, dynamic> j) => CreatedGame(
    gameId: j['gameId'] as String,
    joinCode: j['joinCode'] as String,
    hostToken: j['hostToken'] as String,
    hostTeamId: j['hostTeamId'] as String?,
    hostPlayerId: j['hostPlayerId'] as String?,
    hostPlayerToken: j['hostPlayerToken'] as String?,
  );
}

/// A team offered on the join screen, so a player can pick one to sit with.
class TeamOption {
  TeamOption({
    required this.id,
    required this.name,
    required this.seat,
    required this.score,
    required this.memberNames,
  });

  final String id;
  final String name;
  final int seat;
  final int score;
  final List<String> memberNames;

  factory TeamOption.fromJson(Map<String, dynamic> j) => TeamOption(
    id: j['id'] as String,
    name: j['name'] as String,
    seat: j['seat'] as int? ?? 0,
    score: j['score'] as int? ?? 0,
    memberNames: (j['memberNames'] as List<dynamic>? ?? const [])
        .map((e) => e as String)
        .toList(),
  );
}

class LobbyView {
  LobbyView({
    required this.gameId,
    required this.joinCode,
    required this.state,
    required this.teams,
  });

  final String gameId;
  final String joinCode;
  final GameState state;
  final List<TeamOption> teams;

  factory LobbyView.fromJson(Map<String, dynamic> j) => LobbyView(
    gameId: j['gameId'] as String,
    joinCode: j['joinCode'] as String,
    state: GameState.parse(j['state'] as String?),
    teams: (j['teams'] as List<dynamic>? ?? const [])
        .map((t) => TeamOption.fromJson(t as Map<String, dynamic>))
        .toList(),
  );
}

/// Returned when a person joins. The token is the player's, not the team's --
/// that is what lets two people on one team each hold a buzzer.
class JoinedPlayer {
  JoinedPlayer({
    required this.gameId,
    required this.playerId,
    required this.playerToken,
    required this.playerName,
    required this.teamId,
    required this.teamName,
    required this.seat,
  });

  final String gameId;
  final String playerId;
  final String playerToken;
  final String playerName;
  final String teamId;
  final String teamName;
  final int seat;

  factory JoinedPlayer.fromJson(Map<String, dynamic> j) => JoinedPlayer(
    gameId: j['gameId'] as String,
    playerId: j['playerId'] as String,
    playerToken: j['playerToken'] as String,
    playerName: j['playerName'] as String,
    teamId: j['teamId'] as String,
    teamName: j['teamName'] as String,
    seat: j['seat'] as int? ?? 0,
  );
}

/// Host-only answer lookup result.
class RevealedAnswer {
  RevealedAnswer({
    required this.clueId,
    required this.answer,
    required this.correctionNote,
    required this.peekPenaltyApplied,
  });

  final int clueId;
  final String answer;
  final String? correctionNote;
  final bool peekPenaltyApplied;

  factory RevealedAnswer.fromJson(Map<String, dynamic> j) => RevealedAnswer(
    clueId: j['clueId'] as int,
    answer: j['answer'] as String? ?? '',
    correctionNote: j['correctionNote'] as String?,
    peekPenaltyApplied: j['peekPenaltyApplied'] as bool? ?? false,
  );
}
