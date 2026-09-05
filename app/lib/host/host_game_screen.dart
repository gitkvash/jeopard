import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/game_feed.dart';
import '../core/models.dart';
import '../core/providers.dart';
import '../core/rest_client.dart';
import '../core/session.dart';
import '../core/session_store.dart';
import '../core/theme.dart';
import '../role_screen.dart';
import '../widgets/board_grid.dart';
import '../widgets/clue_panel.dart';
import '../widgets/game_chrome.dart';
import '../widgets/scoreboard.dart';
import '../widgets/stage.dart';
import '../widgets/toast.dart';

/// The host's console: shows the board, puts clues in play, opens the buzzer,
/// and rules on spoken answers.
class HostGameScreen extends ConsumerStatefulWidget {
  const HostGameScreen({super.key, required this.session});

  final GameSession session;

  @override
  ConsumerState<HostGameScreen> createState() => _HostGameScreenState();
}

class _HostGameScreenState extends ConsumerState<HostGameScreen> {
  late final GameFeed _feed;
  bool _busy = false;

  /// Answer fetched with the host token, held only while this clue is in play.
  String? _hostAnswer;
  int? _hostAnswerClueId;

  /// Set the instant the host's own team buzzes, mirroring [BuzzerScreen] --
  /// same instant latch, before any round trip.
  bool _buzzSent = false;
  int? _buzzSentForClue;

  String get _gameId => widget.session.gameId;
  String get _token => widget.session.hostToken ?? '';

  /// Set only when the host also plays. Buzzing needs this, the host's own
  /// player token -- distinct from [_token], which authorises host actions.
  String? get _hostPlayerToken => widget.session.playerToken;

  @override
  void initState() {
    super.initState();
    _feed = GameFeed(gameId: _gameId, onResync: _refresh)..addListener(_onFeed);
    _feed.connect();
    // Renew the stored session: it is what a reload comes back through, and
    // the timestamp is what stops a days-old token being offered.
    SessionStore.write(widget.session.renew());
    _refresh();
  }

  @override
  void dispose() {
    _feed.removeListener(_onFeed);
    _feed.dispose();
    super.dispose();
  }

  void _onFeed() {
    final snap = _feed.snapshot;
    // A new clue invalidates any answer we were holding.
    final staleAnswer =
        snap?.currentClue?.clueId != _hostAnswerClueId && _hostAnswer != null;
    // Same idea as BuzzerScreen: the latch only lasts until the snapshot
    // confirms it, or moves on without it.
    final staleBuzz =
        _buzzSent &&
        (snap?.currentClue?.clueId != _buzzSentForClue ||
            snap?.state != GameState.buzzOpen);
    if (staleAnswer || staleBuzz) {
      setState(() {
        if (staleAnswer) {
          _hostAnswer = null;
          _hostAnswerClueId = null;
        }
        if (staleBuzz) _buzzSent = false;
      });
    }
    // Nothing left to resume once the game is over.
    if (snap?.state == GameState.finished) SessionStore.clear();
  }

  /// Buzzes in the host's own team. A separate path from [_act]: the socket
  /// is lower-latency than REST, and the host racing for the buzzer needs
  /// that as much as any other team does.
  void _buzz() {
    final snap = _feed.snapshot;
    final token = _hostPlayerToken;
    if (snap == null || snap.state != GameState.buzzOpen || token == null) {
      return;
    }

    HapticFeedback.heavyImpact();
    setState(() {
      _buzzSent = true;
      _buzzSentForClue = snap.currentClue?.clueId;
    });

    if (_feed.isSocketConnected) {
      _feed.buzz(token);
    } else {
      ref
          .read(restClientProvider)
          .buzz(_gameId, token)
          .then(_feed.push)
          .catchError((_) {
            if (mounted) setState(() => _buzzSent = false);
            return Future<void>.value();
          });
    }
  }

  Future<void> _refresh() async {
    try {
      final s = await ref.read(restClientProvider).snapshot(_gameId);
      _feed.push(s);
    } catch (_) {
      // The socket will deliver the next broadcast anyway.
    }
  }

  /// Runs a host action, surfacing the server's own rejection message.
  Future<void> _act(Future<Snapshot> Function(RestClient c) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final s = await action(ref.read(restClientProvider));
      _feed.push(s);
    } catch (e) {
      _toast(describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _peek() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final revealed = await ref.read(restClientProvider).peek(_gameId, _token);
      if (!mounted) return;
      setState(() {
        _hostAnswer = revealed.answer;
        _hostAnswerClueId = revealed.clueId;
      });
      if (revealed.peekPenaltyApplied) {
        _toast(L.peekWarning);
      }
    } catch (e) {
      _toast(describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    showToast(context, message, error: error);
  }

  Future<void> _leave() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(L.leaveGame),
        content: const Text(L.leaveGameHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(L.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(L.leaveGame),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    SessionStore.clear();
    if (!mounted) return;
    RoleScreen.replaceAll(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: GameTitle(feed: _feed),
        actions: [
          ConnectionDot(feed: _feed, onTap: _refresh),
          IconButton(
            tooltip: L.leaveGame,
            onPressed: _leave,
            icon: const Icon(Icons.logout, size: 20),
          ),
          IconButton(
            onPressed: () =>
                showAboutJeopard(context, _feed.snapshot?.attribution),
            icon: const Icon(Icons.info_outline, size: 20),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        // Stretch, or the score strip shrink-wraps its content and floats in
        // the middle of the screen instead of spanning it.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Scores redraw on their own, without dragging the board along.
          SnapshotBuilder<(GameState, List<TeamView>, String?)>(
            feed: _feed,
            select: (s) => (
              s?.state ?? GameState.unknown,
              s?.teams ?? const <TeamView>[],
              s?.buzzedTeamId,
            ),
            equals: (a, b) =>
                a.$1 == b.$1 && a.$3 == b.$3 && teamsEqual(a.$2, b.$2),
            builder: (context, value) {
              if (value.$1 == GameState.lobby || value.$2.isEmpty) {
                return const SizedBox.shrink();
              }
              return Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC0A0E1C), Color(0x8805070F)],
                  ),
                  border: Border(bottom: BorderSide(color: JColors.brass)),
                ),
                child: Scoreboard(
                  teams: value.$2,
                  buzzedTeamId: value.$3,
                  myTeamId: widget.session.hostTeamId,
                ),
              );
            },
          ),
          Expanded(
            child: SnapshotBuilder<GameState?>(
              feed: _feed,
              select: (s) => s?.state,
              builder: (context, state) => switch (state) {
                null || GameState.unknown => const Center(
                  child: CircularProgressIndicator(),
                ),
                GameState.lobby => _lobby(),
                GameState.board => _board(),
                GameState.clueReading ||
                GameState.buzzOpen ||
                GameState.buzzed ||
                GameState.resolved => _cluePhase(),
                GameState.finalWager => _finalWager(),
                GameState.finalClue || GameState.finalResult => _finalClue(),
                GameState.finished => _finished(),
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- lobby ----------------

  Widget _lobby() {
    return SnapshotBuilder<(String, List<TeamView>)>(
      feed: _feed,
      select: (s) => (s?.joinCode ?? '', s?.teams ?? const <TeamView>[]),
      equals: (a, b) => a.$1 == b.$1 && teamsEqual(a.$2, b.$2),
      builder: (context, value) {
        final code = value.$1;
        final teams = value.$2;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            Center(child: _JoinCodeCard(code: code)),
            const SizedBox(height: 30),
            Row(
              children: [
                Text(
                  L.teamsJoined,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 8),
                Text(
                  '${teams.length}',
                  style: const TextStyle(
                    color: JColors.goldBright,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (teams.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  L.noTeamsYet,
                  style: TextStyle(color: JColors.textFaint, fontSize: 13),
                ),
              )
            else
              for (final t in teams)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Plate(
                    padding: const EdgeInsets.fromLTRB(12, 10, 14, 11),
                    child: Row(
                      children: [
                        _SeatBadge(seat: t.seat),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (t.players.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  t.players.map((p) => p.name).join(', '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: JColors.textFaint,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (t.host)
                          const Icon(
                            Icons.co_present_outlined,
                            size: 15,
                            color: JColors.brass,
                          ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 24),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: FilledButton.icon(
                  onPressed: teams.isEmpty || _busy
                      ? null
                      : () => _act((c) => c.start(_gameId, _token)),
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text(L.startGame),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------- board ----------------

  Widget _board() {
    return Column(
      children: [
        SnapshotBuilder<String?>(
          feed: _feed,
          select: (s) => s?.teamById(s.pickingTeamId)?.name,
          builder: (context, picking) => PhaseHint(
            picking == null ? L.chooseTile : '${L.chooseTile} — $picking',
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 0, 9, 12),
            child: SnapshotBuilder<List<BoardColumn>>(
              feed: _feed,
              select: (s) => s?.board ?? const <BoardColumn>[],
              equals: boardsEqual,
              builder: (context, board) => BoardGrid(
                board: board,
                onTapTile: (t) =>
                    _act((c) => c.selectClue(_gameId, _token, t.clueId)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- clue in play ----------------

  Widget _cluePhase() {
    return SnapshotBuilder<(int?, GameState?, bool, String?, String?)>(
      feed: _feed,
      select: (s) => (
        s?.currentClue?.clueId,
        s?.state,
        s?.answerRevealed ?? false,
        s?.buzzedTeamId,
        s?.buzzedPlayerId,
      ),
      builder: (context, _) {
        final snap = _feed.snapshot;
        final clue = snap?.currentClue;
        if (snap == null || clue == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final buzzed = snap.teamById(snap.buzzedTeamId);

        final opensIn = snap.buzzOpensInMs;
        final banner = switch (snap.state) {
          // On a timer the host is reading against a clock, so the clock is in
          // the banner they are already looking at.
          GameState.clueReading when opensIn != null => BuzzCountdown(
            remainingMs: opensIn,
            builder: (context, left) => CluePanelBanner(
              text: '${L.readAloud}  ·  $left',
              color: JColors.goldBright,
              icon: Icons.campaign,
            ),
          ),
          GameState.clueReading => const CluePanelBanner(
            text: L.readAloud,
            color: JColors.goldBright,
            icon: Icons.campaign,
          ),
          GameState.buzzOpen => const CluePanelBanner(
            text: L.waitingForBuzz,
            color: JColors.correct,
            icon: Icons.bolt,
          ),
          GameState.buzzed => CluePanelBanner(
            text: '${buzzerLabel(snap, buzzed)} ${L.buzzedIn}',
            color: JColors.buzz,
            icon: Icons.touch_app,
          ),
          _ => null,
        };

        return Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Column(
                  children: [
                    Expanded(
                      child: CluePanel(
                        clue: clue,
                        showAnswer: snap.answerRevealed,
                        banner: banner,
                      ),
                    ),
                    if (_hostAnswer != null && !snap.answerRevealed) ...[
                      const SizedBox(height: 10),
                      _HostOnlyAnswer(answer: _hostAnswer!),
                    ],
                  ],
                ),
              ),
            ),
            _cluePhaseControls(snap),
          ],
        );
      },
    );
  }

  Widget _cluePhaseControls(Snapshot snap) {
    final buttons = <Widget>[];

    switch (snap.state) {
      case GameState.clueReading:
        buttons.add(
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _act((c) => c.openBuzzer(_gameId, _token)),
            icon: const Icon(Icons.bolt, size: 20),
            // With a timer running the button is no longer "open the buzzer"
            // but "do not wait for it".
            label: Text(
              snap.buzzMode == BuzzMode.timer ? L.openNow : L.openBuzzer,
            ),
          ),
        );
        buttons.add(
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _act((c) => c.pass(_gameId, _token)),
            child: const Text(L.pass),
          ),
        );
      case GameState.buzzOpen:
        final hostTeamId = widget.session.hostTeamId;
        final hostLockedOut = snap.teamById(hostTeamId)?.lockedOut ?? false;
        // Hidden once the host has peeked at the answer this clue -- the
        // server refuses that buzz anyway, and peeking already warned them.
        if (hostTeamId != null && !hostLockedOut && !snap.answerPeeked) {
          buttons.add(
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: JColors.buzz,
                foregroundColor: Colors.white,
              ),
              onPressed: _buzzSent ? null : _buzz,
              icon: Icon(_buzzSent ? Icons.check : Icons.bolt, size: 20),
              label: const Text(L.buzz),
            ),
          );
        }
        buttons.add(
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _act((c) => c.pass(_gameId, _token)),
            icon: const Icon(Icons.skip_next, size: 20),
            label: const Text(L.pass),
          ),
        );
      case GameState.buzzed:
        buttons.add(
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: JColors.correct,
              foregroundColor: Colors.white,
            ),
            onPressed: _busy
                ? null
                : () => _act((c) => c.judge(_gameId, _token, true)),
            icon: const Icon(Icons.check, size: 20),
            label: const Text(L.correct),
          ),
        );
        buttons.add(
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: JColors.wrong,
              foregroundColor: Colors.white,
            ),
            onPressed: _busy
                ? null
                : () => _act((c) => c.judge(_gameId, _token, false)),
            icon: const Icon(Icons.close, size: 20),
            label: const Text(L.wrong),
          ),
        );
      case GameState.resolved:
        buttons.add(
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _act((c) => c.next(_gameId, _token)),
            icon: const Icon(Icons.arrow_forward, size: 20),
            label: const Text(L.next),
          ),
        );
      default:
        break;
    }

    return ControlShelf(
      // The host needs the answer in hand to judge. In host-plays mode fetching
      // it costs them the buzzer, which the server enforces -- so it stays a
      // quiet action, off the main row.
      trailing: (!snap.answerRevealed && _hostAnswer == null)
          ? TextButton.icon(
              onPressed: _busy ? null : _peek,
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text(L.showAnswer),
            )
          : null,
      children: buttons,
    );
  }

  // ---------------- final round ----------------

  Widget _finalWager() {
    final snap = _feed.snapshot;
    if (snap == null) return const SizedBox.shrink();

    if (snap.currentClue == null) {
      return Column(
        children: [
          const PhaseHint(L.chooseTile),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 0, 9, 12),
              child: SnapshotBuilder<List<BoardColumn>>(
                feed: _feed,
                select: (s) => s?.board ?? const <BoardColumn>[],
                equals: boardsEqual,
                builder: (context, board) => BoardGrid(
                  board: board,
                  onTapTile: (t) =>
                      _act((c) => c.selectClue(_gameId, _token, t.clueId)),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return SnapshotBuilder<(String, List<TeamView>)>(
      feed: _feed,
      select: (s) =>
          (s?.currentClue?.topicName ?? '', s?.teams ?? const <TeamView>[]),
      equals: (a, b) => a.$1 == b.$1 && teamsEqual(a.$2, b.$2),
      builder: (context, value) {
        final teams = value.$2;
        final waiting = teams.where((t) => t.wager == null).length;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            Text(value.$1, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              L.waitingForWagers,
              style: const TextStyle(color: JColors.textFaint, fontSize: 13),
            ),
            const SizedBox(height: 18),
            for (final t in teams)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    title: Text(t.name),
                    subtitle: Text('${L.score}: ${t.score}'),
                    trailing: Text(
                      t.wager == null ? '—' : '${t.wager}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: t.wager == null
                            ? JColors.textFaint
                            : JColors.goldBright,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: FilledButton.icon(
                  onPressed: waiting > 0 || _busy
                      ? null
                      : () => _act((c) => c.openFinal(_gameId, _token)),
                  icon: const Icon(Icons.lock_open, size: 20),
                  label: const Text(L.openFinalClue),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _finalClue() {
    return SnapshotBuilder<(int?, GameState?, bool, int)>(
      feed: _feed,
      select: (s) => (
        s?.currentClue?.clueId,
        s?.state,
        s?.answerRevealed ?? false,
        s?.teams.where((t) => t.lockedOut).length ?? 0,
      ),
      builder: (context, _) {
        final snap = _feed.snapshot;
        final clue = snap?.currentClue;
        if (snap == null || clue == null) return const SizedBox.shrink();

        return Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: CluePanel(clue: clue, showAnswer: snap.answerRevealed),
              ),
            ),
            _FinalShelf(
              child: snap.state == GameState.finalClue
                  ? Column(
                      children: [
                        for (final t in snap.teams.where((t) => !t.lockedOut))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${t.name}  ·  ${L.wager}: ${t.wager ?? 0}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton.filled(
                                  style: IconButton.styleFrom(
                                    backgroundColor: JColors.correct,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => _act(
                                          (c) => c.finalJudge(
                                            _gameId,
                                            _token,
                                            t.id,
                                            true,
                                          ),
                                        ),
                                  icon: const Icon(Icons.check, size: 18),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filled(
                                  style: IconButton.styleFrom(
                                    backgroundColor: JColors.wrong,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => _act(
                                          (c) => c.finalJudge(
                                            _gameId,
                                            _token,
                                            t.id,
                                            false,
                                          ),
                                        ),
                                  icon: const Icon(Icons.close, size: 18),
                                ),
                              ],
                            ),
                          ),
                      ],
                    )
                  : FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _act((c) => c.next(_gameId, _token)),
                      icon: const Icon(Icons.flag, size: 20),
                      label: const Text(L.finalResults),
                    ),
            ),
          ],
        );
      },
    );
  }

  // ---------------- finished ----------------

  Widget _finished() {
    return SnapshotBuilder<(List<TeamView>, String?)>(
      feed: _feed,
      select: (s) => (s?.teams ?? const <TeamView>[], s?.attribution),
      equals: (a, b) => a.$2 == b.$2 && teamsEqual(a.$1, b.$1),
      builder: (context, value) => ResultsView(
        teams: value.$1,
        attribution: value.$2,
        highlightTeamId: widget.session.hostTeamId,
        onRestart: () {
          SessionStore.clear();
          RoleScreen.replaceAll(context);
        },
      ),
    );
  }
}

/// The round the game is on, plus how much of the board is left.
class GameTitle extends StatelessWidget {
  const GameTitle({super.key, required this.feed});

  final GameFeed feed;

  @override
  Widget build(BuildContext context) {
    return SnapshotBuilder<GameHeader>(
      feed: feed,
      select: (s) => GameHeader(
        title: s?.packageTitle,
        roundIdx: s?.roundIdx ?? 0,
        finalRound: s?.finalRound ?? false,
        tilesRemaining: s?.tilesRemaining ?? 0,
        connected: feed.connected,
      ),
      builder: (context, header) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            header.title ?? L.appTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          Text(
            '${header.finalRound ? L.finalRound : '${L.roundLabel} ${header.roundIdx}'}'
            '  ·  ${L.remaining} ${header.tilesRemaining}',
            style: const TextStyle(fontSize: 11, color: JColors.textFaint),
          ),
        ],
      ),
    );
  }
}

class _SeatBadge extends StatelessWidget {
  const _SeatBadge({required this.seat});

  final int seat;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: JColors.surfaceHigh,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: JColors.line),
      ),
      child: Text(
        '$seat',
        style: engraved(15, color: JColors.brass, glow: false),
      ),
    );
  }
}

/// The join code, in board numerals, one character per tile.
///
/// This is the screen everyone looks at while they wait, so it is built like a
/// row off the board itself: bevelled blue plates, gold condensed characters,
/// black gutters between them. Tapping copies the code.
class _JoinCodeCard extends StatelessWidget {
  const _JoinCodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    // Generate link based on the current window URL (frontend), not the API backend.
    final joinLink = Uri.base.replace(queryParameters: {'code': code}).toString();

    return Column(
      children: [
        Text(L.shareCode.toUpperCase(), style: kTicker),
        const SizedBox(height: 14),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(JRadius.card),
            onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              showToast(context, L.copied);
            },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final ch in code.characters) ...[
                    Container(
                      width: 46,
                      height: 62,
                      alignment: Alignment.center,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFF3A56F5),
                            JColors.boardLit,
                            JColors.board,
                            JColors.boardDeep,
                          ],
                          stops: [0, 0.08, 0.45, 1],
                        ),
                        borderRadius: BorderRadius.circular(JRadius.tile),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                            spreadRadius: -4,
                          ),
                        ],
                      ),
                      child: Text(ch, style: engraved(34)),
                    ),
                  ],
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.copy_rounded,
                    size: 17,
                    color: JColors.brass,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: joinLink));
                showToast(context, L.linkCopied);
              },
              icon: const Icon(Icons.link, color: JColors.brass),
              label: const Text(L.shareLink, style: TextStyle(color: JColors.brass)),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () => _showQrDialog(context, joinLink),
              icon: const Icon(Icons.qr_code, color: JColors.brass),
              label: const Text(L.qrCode, style: TextStyle(color: JColors.brass)),
            ),
          ],
        ),
      ],
    );
  }

  void _showQrDialog(BuildContext context, String link) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 250,
                height: 250,
                child: QrImageView(
                  data: link,
                  version: 4,
                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(L.ok),
            ),
          ],
        ),
      ),
    );
  }
}

/// Answer shown to the host only, never part of a broadcast.
class _HostOnlyAnswer extends StatelessWidget {
  const _HostOnlyAnswer({required this.answer});

  final String answer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JColors.surfaceHigh,
        borderRadius: BorderRadius.circular(JRadius.card),
        border: Border.all(color: JColors.gold),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.visibility_off_outlined,
            size: 17,
            color: JColors.gold,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${L.answer} (${L.host})',
                  style: const TextStyle(
                    fontSize: 10,
                    color: JColors.textFaint,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  answer,
                  style: const TextStyle(
                    color: JColors.goldBright,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The final round judges several teams at once, so its controls are a column
/// rather than a row -- but they belong on the same shelf as everything else.
class _FinalShelf extends StatelessWidget {
  const _FinalShelf({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x9905070F), Color(0xFF05070F)],
          stops: [0, 0.35, 1],
        ),
        border: Border(top: BorderSide(color: Color(0x338A6A2A))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
