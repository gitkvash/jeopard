import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/game_feed.dart';
import '../core/game_sounds.dart';
import '../core/models.dart';
import '../core/providers.dart';
import '../core/responsive.dart';
import '../core/rest_client.dart';
import '../core/session.dart';
import '../core/session_store.dart';
import '../core/theme.dart';
import '../host/host_game_screen.dart' show GameTitle;
import '../role_screen.dart';
import '../widgets/board_grid.dart';
import '../widgets/clue_panel.dart';
import '../widgets/game_chrome.dart';
import '../widgets/scoreboard.dart';
import '../widgets/stage.dart';
import '../widgets/toast.dart';

/// One person on their own, working through a package.
///
/// The same game the server runs for a room, with the player as host and only
/// team at once: they choose a tile, think of the answer, look at it, and say
/// whether they had it. Right wins the value and wrong loses it, as a buzz
/// would; "did not know" costs nothing -- so the total is the score they would
/// have made by only buzzing on what they knew.
class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({super.key, required this.session});

  final GameSession session;

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  late final GameFeed _feed;
  late final GameSounds _sounds;
  StreamSubscription<Notice>? _noticeSub;
  bool _busy = false;

  /// The answer the player asked to see, held only while its clue is in play.
  String? _answer;
  String? _correctionNote;
  int? _answerClueId;

  /// Stops [_onFeed] asking for the answer again on every broadcast while the
  /// fetch it already started is on its way.
  int? _fetchingAnswerFor;

  final _wager = TextEditingController();

  String get _gameId => widget.session.gameId;
  String get _token => widget.session.hostToken ?? '';
  String? get _teamId => widget.session.hostTeamId;

  @override
  void initState() {
    super.initState();
    _feed = GameFeed(gameId: _gameId, onResync: _refresh)..addListener(_onFeed);
    _sounds = GameSounds(_feed, role: SoundRole.host);
    _noticeSub = _feed.notices.listen(_onNotice);
    _feed.connect();
    SessionStore.write(widget.session.renew());
    _refresh();
  }

  @override
  void dispose() {
    _noticeSub?.cancel();
    _sounds.dispose();
    _feed.removeListener(_onFeed);
    _feed.dispose();
    _wager.dispose();
    super.dispose();
  }

  void _onFeed() {
    final snap = _feed.snapshot;
    final clue = snap?.currentClue;
    if (_answer != null && clue?.clueId != _answerClueId) {
      setState(() {
        _answer = null;
        _correctionNote = null;
        _answerClueId = null;
      });
    }

    // Looked at before a reload: the server remembers that, this screen does
    // not, and making them press the button again for an answer they have
    // already seen would only be in the way.
    final judging =
        snap?.state == GameState.clueReading ||
        snap?.state == GameState.finalClue;
    if (clue != null &&
        judging &&
        (snap?.answerPeeked ?? false) &&
        _answer == null &&
        _fetchingAnswerFor != clue.clueId) {
      _showAnswer();
    }

    if (snap?.state == GameState.finished) SessionStore.clear();
  }

  void _onNotice(Notice n) {
    if (n.isGameTerminated) {
      SessionStore.clear();
      if (mounted) RoleScreen.replaceAll(context);
    }
  }

  Future<void> _refresh() async {
    try {
      _feed.push(
        await ref.read(restClientProvider).snapshot(_gameId, hostToken: _token),
      );
    } on ApiException catch (e) {
      if (e.isNotFound) {
        SessionStore.clear();
        if (mounted) RoleScreen.replaceAll(context);
      }
    } catch (_) {
      // The socket will deliver the next broadcast anyway.
    }
  }

  Future<void> _act(Future<Snapshot> Function(RestClient c) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _feed.push(await action(ref.read(restClientProvider)));
    } catch (e) {
      _toast(describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showAnswer() async {
    final clueId = _feed.snapshot?.currentClue?.clueId;
    if (clueId == null || _fetchingAnswerFor == clueId) return;
    _fetchingAnswerFor = clueId;
    setState(() => _busy = true);
    try {
      final revealed = await ref.read(restClientProvider).peek(_gameId, _token);
      if (!mounted) return;
      setState(() {
        _answer = revealed.answer;
        _correctionNote = revealed.correctionNote;
        _answerClueId = revealed.clueId;
      });
    } catch (e) {
      _fetchingAnswerFor = null;
      _toast(describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Wagering and opening the final are one step when there is nobody else
  /// to wait for.
  Future<void> _wagerAndOpen(int amount) => _act((c) async {
    await c.wager(_gameId, widget.session.playerToken ?? '', amount);
    return c.openFinal(_gameId, _token);
  });

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    showToast(context, message, error: error);
  }

  Future<void> _endPractice() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(L.endPractice),
        content: const Text(L.endPracticeMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(L.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: JColors.wrong,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(L.endGameAction),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(restClientProvider).deleteGame(_gameId, _token);
      SessionStore.clear();
      if (!mounted) return;
      RoleScreen.replaceAll(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast(describeError(e), error: true);
      }
    }
  }

  /// The answer the player looked at, laid into the clue so the panel shows it
  /// where it always shows answers.
  CurrentClue _withAnswer(CurrentClue clue) =>
      (clue.answer == null && clue.clueId == _answerClueId && _answer != null)
      ? clue.copyWith(answer: _answer, correctionNote: _correctionNote)
      : clue;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        RoleScreen.replaceAll(context);
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: context.appBarHeight,
          titleSpacing: 16,
          title: GameTitle(feed: _feed),
          actions: [
            const SoundToggle(),
            IconButton(
              tooltip: L.endPractice,
              onPressed: _endPractice,
              icon: const Icon(
                Icons.stop_circle_outlined,
                size: 20,
                color: JColors.wrongBright,
              ),
            ),
            // Home without ending it: the start screen offers it back.
            IconButton(
              tooltip: L.mainMenu,
              onPressed: () => RoleScreen.replaceAll(context),
              icon: const Icon(Icons.home_outlined, size: 20),
            ),
            IconButton(
              onPressed: () =>
                  showAboutJeopard(context, _feed.snapshot?.attribution),
              icon: const Icon(Icons.info_outline, size: 20),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SnapshotBuilder<(GameState, List<TeamView>)>(
                feed: _feed,
                select: (s) => (
                  s?.state ?? GameState.unknown,
                  s?.teams ?? const <TeamView>[],
                ),
                equals: (a, b) => a.$1 == b.$1 && teamsEqual(a.$2, b.$2),
                builder: (context, value) {
                  if (value.$1 == GameState.finished || value.$2.isEmpty) {
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
                    child: Scoreboard(teams: value.$2, myTeamId: _teamId),
                  );
                },
              ),
              Expanded(
                child: SnapshotBuilder<GameState?>(
                  feed: _feed,
                  select: (s) => s?.state,
                  builder: (context, state) => switch (state) {
                    GameState.board => _board(),
                    GameState.clueReading ||
                    GameState.buzzOpen ||
                    GameState.buzzed ||
                    GameState.resolved => _cluePhase(),
                    GameState.finalWager => _finalWager(),
                    GameState.finalClue ||
                    GameState.finalResult => _finalClue(),
                    GameState.finished => _finished(),
                    // A practice game opens on the board; there is no lobby.
                    null || GameState.unknown || GameState.lobby =>
                      const Center(child: CircularProgressIndicator()),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- board ----------------

  Widget _board() {
    return Column(
      children: [
        const PhaseHint(L.chooseTile),
        Expanded(child: _grid()),
      ],
    );
  }

  Widget _grid() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        9,
        0,
        9,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: SnapshotBuilder<(List<BoardColumn>, int?)>(
        feed: _feed,
        select: (s) => (s?.board ?? const <BoardColumn>[], s?.packageNumber),
        equals: (a, b) => a.$2 == b.$2 && boardsEqual(a.$1, b.$1),
        builder: (context, value) => BoardGrid(
          board: value.$1,
          onTapTile: (t) =>
              _act((c) => c.selectClue(_gameId, _token, t.clueId)),
          // A random package's categories are this game's own to swap.
          onRerollTopic: (value.$2 ?? 0) < 0
              ? (column) => _act(
                  (c) => c.rerollGameTopic(_gameId, _token, column.topicId),
                )
              : null,
        ),
      ),
    );
  }

  // ---------------- clue in play ----------------

  Widget _cluePhase() {
    return SnapshotBuilder<(int?, GameState?, bool)>(
      feed: _feed,
      select: (s) =>
          (s?.currentClue?.clueId, s?.state, s?.answerRevealed ?? false),
      builder: (context, _) {
        final snap = _feed.snapshot;
        final clue = snap?.currentClue;
        if (snap == null || clue == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final resolved = snap.state == GameState.resolved;
        final seen = _answer != null && _answerClueId == clue.clueId;

        return ClueLayout(
          panel: CluePanel(
            clue: _withAnswer(clue),
            showAnswer: resolved || seen,
            banner: resolved
                ? null
                : CluePanelBanner(
                    text: seen ? L.practiceDidYouKnow : L.practiceThink,
                    color: JColors.goldBright,
                    icon: seen ? Icons.rule : Icons.lightbulb_outline,
                  ),
          ),
          controls: (side) => _clueControls(snap, seen: seen, side: side),
        );
      },
    );
  }

  Widget _clueControls(
    Snapshot snap, {
    required bool seen,
    required bool side,
  }) {
    final notKnown = OutlinedButton.icon(
      onPressed: _busy ? null : () => _act((c) => c.pass(_gameId, _token)),
      icon: const Icon(Icons.skip_next, size: 20),
      label: const Text(L.practiceNotKnown),
    );

    if (snap.state == GameState.resolved) {
      return ControlShelf(
        side: side,
        children: [
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _act((c) => c.next(_gameId, _token)),
            icon: const Icon(Icons.arrow_forward, size: 20),
            label: const Text(L.next),
          ),
        ],
      );
    }

    if (!seen) {
      return ControlShelf(
        side: side,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _showAnswer,
            icon: const Icon(Icons.visibility_outlined, size: 20),
            label: const Text(L.showAnswer),
          ),
          notKnown,
        ],
      );
    }

    return ControlShelf(
      side: side,
      trailing: notKnown,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: JColors.correct,
            foregroundColor: Colors.white,
          ),
          onPressed: _busy
              ? null
              : () => _act((c) => c.selfJudge(_gameId, _token, true)),
          icon: const Icon(Icons.check, size: 20),
          label: const Text(L.correct),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: JColors.wrong,
            foregroundColor: Colors.white,
          ),
          onPressed: _busy
              ? null
              : () => _act((c) => c.selfJudge(_gameId, _token, false)),
          icon: const Icon(Icons.close, size: 20),
          label: const Text(L.wrong),
        ),
      ],
    );
  }

  // ---------------- final round ----------------

  Widget _finalWager() {
    return SnapshotBuilder<(String?, int?, int?)>(
      feed: _feed,
      select: (s) => (
        s?.currentClue?.topicName,
        s?.teamById(_teamId)?.score,
        s?.teamById(_teamId)?.wager,
      ),
      builder: (context, value) {
        final (topic, score, wager) = value;
        if (topic == null) {
          return Column(
            children: [
              const PhaseHint(L.chooseTile),
              Expanded(child: _grid()),
            ],
          );
        }

        // Only after a reload between the two halves of [_wagerAndOpen].
        if (wager != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${L.yourWager}: $wager',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: JColors.goldBright,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _act((c) => c.openFinal(_gameId, _token)),
                  icon: const Icon(Icons.lock_open, size: 20),
                  label: const Text(L.openFinalClue),
                ),
              ],
            ),
          );
        }

        // Funded by points already won; the server clamps it as well.
        final have = score ?? 0;
        final max = have > 0 ? have : 0;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      topic,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${L.score}: $have  ·  ${L.maxWager} $max',
                      style: const TextStyle(
                        color: JColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: _wager,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: L.yourWager),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (label, amount) in [
                          ('0', 0),
                          ('½', max ~/ 2),
                          (L.maxWager, max),
                        ])
                          OutlinedButton(
                            onPressed: () {
                              _wager.text = '$amount';
                              setState(() {});
                            },
                            child: Text(label),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed:
                          _busy || int.tryParse(_wager.text.trim()) == null
                          ? null
                          : () => _wagerAndOpen(int.parse(_wager.text.trim())),
                      icon: const Icon(Icons.lock_open, size: 20),
                      label: const Text(L.openFinalClue),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _finalClue() {
    return SnapshotBuilder<(int?, GameState?, bool)>(
      feed: _feed,
      select: (s) =>
          (s?.currentClue?.clueId, s?.state, s?.answerRevealed ?? false),
      builder: (context, _) {
        final snap = _feed.snapshot;
        final clue = snap?.currentClue;
        if (snap == null || clue == null) return const SizedBox.shrink();
        final teamId = _teamId;
        final wager = snap.teamById(teamId)?.wager ?? 0;
        final judging = snap.state == GameState.finalClue;
        final seen = _answer != null && _answerClueId == clue.clueId;

        final List<Widget> buttons;
        if (!judging) {
          buttons = [
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _act((c) => c.next(_gameId, _token)),
              icon: const Icon(Icons.flag, size: 20),
              label: const Text(L.finalResults),
            ),
          ];
        } else if (!seen) {
          buttons = [
            FilledButton.icon(
              onPressed: _busy ? null : _showAnswer,
              icon: const Icon(Icons.visibility_outlined, size: 20),
              label: const Text(L.showAnswer),
            ),
          ];
        } else {
          buttons = [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: JColors.correct,
                foregroundColor: Colors.white,
              ),
              onPressed: _busy || teamId == null
                  ? null
                  : () => _act(
                      (c) => c.finalJudge(_gameId, _token, teamId, true),
                    ),
              icon: const Icon(Icons.check, size: 20),
              label: const Text(L.correct),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: JColors.wrong,
                foregroundColor: Colors.white,
              ),
              onPressed: _busy || teamId == null
                  ? null
                  : () => _act(
                      (c) => c.finalJudge(_gameId, _token, teamId, false),
                    ),
              icon: const Icon(Icons.close, size: 20),
              label: const Text(L.wrong),
            ),
          ];
        }

        return ClueLayout(
          panel: CluePanel(
            clue: _withAnswer(clue),
            showAnswer: !judging || seen,
            banner: judging
                ? CluePanelBanner(
                    text: '${L.yourWager}: $wager',
                    color: JColors.goldBright,
                    icon: Icons.casino_outlined,
                  )
                : null,
          ),
          controls: (side) => ControlShelf(side: side, children: buttons),
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
        highlightTeamId: _teamId,
        onRestart: () {
          SessionStore.clear();
          RoleScreen.replaceAll(context);
        },
      ),
    );
  }
}
