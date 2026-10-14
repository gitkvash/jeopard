import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'models.dart';
import 'theme.dart';

/// Thrown when the backend rejects an action. [message] is the server's own
/// explanation, which is usually the right thing to show the host.
class ApiException implements Exception {
  ApiException(this.status, this.message);

  final int status;
  final String message;

  bool get isConflict => status == 409;
  bool get isNotFound => status == 404;

  @override
  String toString() => 'ApiException($status): $message';
}

/// Turns a caught error into text worth putting on screen. [ApiException]
/// already carries the server's own explanation; anything else -- a dropped
/// connection, the backend unreachable, a device on the wrong Wi-Fi -- is a
/// [http.ClientException] or similar whose message is meant for a console,
/// not a player, so it collapses to one plain-language line instead.
String describeError(Object error) {
  if (error is ApiException) return error.message;
  if (error is http.ClientException) return L.connectionError;
  return L.unexpectedError;
}

class RestClient {
  RestClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // ---------- content ----------

  Future<List<PackageSummary>> packages() async {
    final body = await _get('/api/packages');
    return (body as List<dynamic>)
        .map((p) => PackageSummary.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  /// Assembles a fresh packet server-side by sampling topics from the existing
  /// ones. Returns a normal [PackageSummary]; the game it starts is created the
  /// same way as any other package.
  Future<PackageSummary> randomPackage() async {
    final body = await _post('/api/packages/random');
    return PackageSummary.fromJson(body as Map<String, dynamic>);
  }

  /// Swaps one category of a random package with another random category.
  Future<TopicSummary> rerollTopic(int packageId, int topicId) async {
    final body = await _post('/api/packages/$packageId/topics/$topicId/reroll');
    return TopicSummary.fromJson(body as Map<String, dynamic>);
  }

  Future<PackageSummary> getPackage(int packageId) async {
    final body = await _get('/api/packages/$packageId');
    return PackageSummary.fromJson(body as Map<String, dynamic>);
  }

  // ---------- setup ----------

  /// Pass [packageId] to play a whole package (boards 1-3 then the final with
  /// scores carried across), or [roundId] for a single round. Exactly one.
  Future<CreatedGame> createGame({
    int? packageId,
    int? roundId,
    required bool hostPlays,
    String? hostTeamName,
    BuzzMode buzzMode = BuzzMode.host,
    int? buzzDelaySeconds,
    bool questionsVisibleToParticipants = true,
  }) async {
    assert(
      (packageId == null) != (roundId == null),
      'supply exactly one of packageId or roundId',
    );
    assert(
      buzzMode != BuzzMode.timer || buzzDelaySeconds != null,
      'an automatic buzzer needs a delay',
    );
    final body = await _post(
      '/api/games',
      body: {
        'packageId': ?packageId,
        'roundId': ?roundId,
        'hostPlays': hostPlays,
        if (hostTeamName != null && hostTeamName.isNotEmpty)
          'hostTeamName': hostTeamName,
        'buzzMode': buzzMode.wire,
        if (buzzMode == BuzzMode.timer) 'buzzDelaySeconds': buzzDelaySeconds,
        'questionsVisibleToParticipants': questionsVisibleToParticipants,
      },
    );
    return CreatedGame.fromJson(body as Map<String, dynamic>);
  }

  /// The teams already in the game, so a joining player can pick one.
  Future<LobbyView> lobby(String joinCode) async {
    final body = await _get('/api/games/$joinCode/lobby');
    return LobbyView.fromJson(body as Map<String, dynamic>);
  }

  /// Join as a person. Supply [teamId] to sit with an existing team or
  /// [newTeamName] to start one; supply neither to play without a team.
  Future<JoinedPlayer> joinPlayer({
    required String joinCode,
    required String name,
    String? teamId,
    String? newTeamName,
  }) async {
    assert(
      teamId == null || newTeamName == null,
      'supply at most one of teamId or newTeamName',
    );
    final body = await _post(
      '/api/games/$joinCode/players',
      body: {'name': name, 'teamId': ?teamId, 'newTeamName': ?newTeamName},
    );
    return JoinedPlayer.fromJson(body as Map<String, dynamic>);
  }

  /// A player moving themselves, before the game starts. Supply [teamId] for an
  /// existing team or [newTeamName] for a new one; supply neither to leave the
  /// team and play alone.
  Future<Snapshot> changeTeam({
    required String gameId,
    required String playerToken,
    String? teamId,
    String? newTeamName,
  }) async {
    assert(
      teamId == null || newTeamName == null,
      'supply at most one of teamId or newTeamName',
    );
    final body = await _post(
      '/api/games/$gameId/team',
      body: {
        'playerToken': playerToken,
        'teamId': ?teamId,
        'newTeamName': ?newTeamName,
      },
    );
    return Snapshot.fromJson(body as Map<String, dynamic>);
  }

  /// A player voluntarily leaving the game.
  Future<void> leavePlayer(String gameId, String playerToken) async {
    try {
      await _post(
        '/api/games/$gameId/leave',
        body: {'playerToken': playerToken},
      );
    } catch (_) {
      // Best-effort
    }
  }

  /// Supply [hostToken] to get the clue question even when this game keeps it
  /// off a participant's own device -- omit it for the view a team itself
  /// would get.
  Future<Snapshot> snapshot(String gameId, {String? hostToken}) async =>
      Snapshot.fromJson(
        await _get('/api/games/$gameId', hostToken: hostToken)
            as Map<String, dynamic>,
      );

  Future<Snapshot> snapshotByCode(String joinCode, {String? hostToken}) async =>
      Snapshot.fromJson(
        await _get('/api/games/by-code/$joinCode', hostToken: hostToken)
            as Map<String, dynamic>,
      );

  // ---------- host actions ----------

  Future<Snapshot> start(String gameId, String hostToken) =>
      _hostAction(gameId, 'start', hostToken);

  Future<Snapshot> selectClue(String gameId, String hostToken, int clueId) =>
      _hostAction(gameId, 'select-clue', hostToken, body: {'clueId': clueId});

  /// Swaps a category nobody has played from for another random one.
  Future<Snapshot> rerollGameTopic(
    String gameId,
    String hostToken,
    int topicId,
  ) => _hostAction(gameId, 'topics/$topicId/reroll', hostToken);

  Future<Snapshot> openBuzzer(String gameId, String hostToken) =>
      _hostAction(gameId, 'open-buzzer', hostToken);

  Future<Snapshot> judge(String gameId, String hostToken, bool correct) =>
      _hostAction(gameId, 'judge', hostToken, body: {'correct': correct});

  Future<Snapshot> pass(String gameId, String hostToken) =>
      _hostAction(gameId, 'pass', hostToken);

  /// Set the current buzz aside: no points, no lockout, and the buzzer reopens
  /// for everyone -- for a press that was an accident.
  Future<Snapshot> skipBuzz(String gameId, String hostToken) =>
      _hostAction(gameId, 'skip-buzz', hostToken);

  /// Sets a team's score outright. Everyone in the game is told.
  Future<Snapshot> setScore(
    String gameId,
    String hostToken,
    String teamId,
    int score,
  ) => _hostAction(
    gameId,
    'teams/$teamId/score',
    hostToken,
    body: {'score': score},
  );

  /// Moves a person to [teamId], to a new team named [newTeamName], or -- with
  /// neither -- on their own. Only between clues.
  Future<Snapshot> movePlayer(
    String gameId,
    String hostToken,
    String playerId, {
    String? teamId,
    String? newTeamName,
  }) => _hostAction(
    gameId,
    'players/$playerId/move',
    hostToken,
    body: {'teamId': ?teamId, 'newTeamName': ?newTeamName},
  );

  Future<Snapshot> reveal(String gameId, String hostToken) =>
      _hostAction(gameId, 'reveal', hostToken);

  Future<Snapshot> next(String gameId, String hostToken) =>
      _hostAction(gameId, 'next', hostToken);

  /// Host-only answer lookup. When the host is also playing this costs them the
  /// buzzer on the current clue.
  Future<RevealedAnswer> peek(String gameId, String hostToken) async {
    final body = await _post('/api/games/$gameId/peek', hostToken: hostToken);
    return RevealedAnswer.fromJson(body as Map<String, dynamic>);
  }

  // ---------- buzzing ----------

  /// REST fallback for the STOMP buzz; same server-side locking path.
  Future<Snapshot> buzz(String gameId, String playerToken) async {
    final body = await _post(
      '/api/games/$gameId/buzz',
      body: {'playerToken': playerToken},
    );
    return Snapshot.fromJson(body as Map<String, dynamic>);
  }

  // ---------- final round ----------

  /// Any member may set it -- the wager belongs to the team.
  Future<Snapshot> wager(String gameId, String playerToken, int amount) async {
    final body = await _post(
      '/api/games/$gameId/wager',
      body: {'playerToken': playerToken, 'wager': amount},
    );
    return Snapshot.fromJson(body as Map<String, dynamic>);
  }

  Future<Snapshot> openFinal(String gameId, String hostToken) =>
      _hostAction(gameId, 'open-final', hostToken);

  Future<Snapshot> finalJudge(
    String gameId,
    String hostToken,
    String teamId,
    bool correct,
  ) => _hostAction(
    gameId,
    'final-judge',
    hostToken,
    body: {'teamId': teamId, 'correct': correct},
  );

  /// Ends and deletes the game.
  Future<void> deleteGame(String gameId, String hostToken) async {
    await _delete('/api/games/$gameId', hostToken: hostToken);
  }

  // ---------- plumbing ----------

  Future<Snapshot> _hostAction(
    String gameId,
    String action,
    String hostToken, {
    Map<String, dynamic>? body,
  }) async {
    final json = await _post(
      '/api/games/$gameId/$action',
      body: body,
      hostToken: hostToken,
    );
    return Snapshot.fromJson(json as Map<String, dynamic>);
  }

  Future<dynamic> _get(String path, {String? hostToken}) async {
    final res = await _client.get(
      Uri.parse('${ApiConfig.baseUrl}$path'),
      headers: {'X-Host-Token': ?hostToken},
    );
    return _decode(res);
  }

  Future<dynamic> _post(
    String path, {
    Map<String, dynamic>? body,
    String? hostToken,
  }) async {
    final res = await _client.post(
      Uri.parse('${ApiConfig.baseUrl}$path'),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'X-Host-Token': ?hostToken,
      },
      body: jsonEncode(body ?? const {}),
    );
    return _decode(res);
  }

  Future<dynamic> _delete(String path, {String? hostToken}) async {
    final res = await _client.delete(
      Uri.parse('${ApiConfig.baseUrl}$path'),
      headers: {'X-Host-Token': ?hostToken},
    );
    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    // Decode as UTF-8 explicitly: Georgian text is multi-byte and http's
    // default latin-1 fallback would mangle it when charset is absent.
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return text.isEmpty ? const {} : jsonDecode(text);
    }
    throw ApiException(res.statusCode, _errorMessage(text, res.statusCode));
  }

  String _errorMessage(String text, int status) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['detail'] is String) {
        return decoded['detail'] as String;
      }
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } catch (_) {
      // Not JSON; fall through to the raw text.
    }
    return text.isEmpty ? 'HTTP $status' : text;
  }

  void close() => _client.close();
}
