import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// A player's device: mostly one very large button. Teammates each get their
/// own, but score and lockout land on the team they share.
class BuzzerScreen extends ConsumerStatefulWidget {
  const BuzzerScreen({super.key, required this.session});

  final GameSession session;

  @override
  ConsumerState<BuzzerScreen> createState() => _BuzzerScreenState();
}

class _BuzzerScreenState extends ConsumerState<BuzzerScreen> {
  late final GameFeed _feed;

  /// Set the instant we send a buzz so the button reacts without waiting for
  /// the round trip. Cleared when the next snapshot tells us the real outcome.
  bool _buzzSent = false;
  int? _buzzSentForClue;

  final _wager = TextEditingController();

  String get _gameId => widget.session.gameId;
  String get _playerToken => widget.session.playerToken ?? '';
  String? get _teamId => widget.session.teamId;

  @override
  void initState() {
    super.initState();
    _feed = GameFeed(gameId: _gameId, onResync: _refresh)..addListener(_onFeed);
    _feed.connect();
    SessionStore.write(widget.session.renew());
    _refresh();
  }

  @override
  void dispose() {
    _feed.removeListener(_onFeed);
    _feed.dispose();
    _wager.dispose();
    super.dispose();
  }

  void _onFeed() {
    final snap = _feed.snapshot;
    if (_buzzSent &&
        (snap?.currentClue?.clueId != _buzzSentForClue ||
            snap?.state != GameState.buzzOpen)) {
      setState(() => _buzzSent = false);
    }
    if (snap?.state == GameState.finished) SessionStore.clear();
  }

  Future<void> _refresh() async {
    try {
      final s = await ref.read(restClientProvider).snapshot(_gameId);
      _feed.push(s);
    } catch (_) {
      // Next broadcast will resync.
    }
  }

  void _buzz() {
    final snap = _feed.snapshot;
    if (snap == null || snap.state != GameState.buzzOpen) return;

    HapticFeedback.heavyImpact();
    setState(() {
      _buzzSent = true;
      _buzzSentForClue = snap.currentClue?.clueId;
    });

    // Prefer the socket -- it is the lowest-latency path. If it is down, fall
    // back to REST so a flaky connection does not silently cost the round.
    if (_feed.isSocketConnected) {
      _feed.buzz(_playerToken);
    } else {
      ref
          .read(restClientProvider)
          .buzz(_gameId, _playerToken)
          .then(_feed.push)
          .catchError((_) {
            if (mounted) setState(() => _buzzSent = false);
            return Future<void>.value();
          });
    }
  }

  Future<void> _submitWager(int amount) async {
    try {
      final s = await ref
          .read(restClientProvider)
          .wager(_gameId, _playerToken, amount);
      _feed.push(s);
    } catch (e) {
      if (mounted) {
        showToast(context, describeError(e), error: true);
      }
    }
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

  /// My team -- the thing that holds my score.
  TeamView? get _me => _feed.snapshot?.teamById(_teamId);

  /// The server already omits [CurrentClue.question] on this game -- this just
  /// turns that gap into something a player understands instead of a blank
  /// panel, or a lonely "...".
  CurrentClue _hideQuestionIfNeeded(CurrentClue clue, Snapshot snap) =>
      (clue.question == null && !snap.questionsVisibleToParticipants)
      ? clue.copyWith(question: L.questionHiddenFromParticipants)
      : clue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.session.playerName ?? L.team,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            Text(
              widget.session.teamName ?? '',
              style: const TextStyle(fontSize: 11, color: JColors.textFaint),
            ),
          ],
        ),
        actions: [
          // My score, large enough to glance at mid-game.
          SnapshotBuilder<int?>(
            feed: _feed,
            select: (s) => s?.teamById(_teamId)?.score,
            builder: (context, score) => score == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      child: Text(
                        '$score',
                        style: engraved(
                          22,
                          color: score < 0 ? JColors.wrongBright : JColors.gold,
                          glow: false,
                        ),
                      ),
                    ),
                  ),
          ),
          ConnectionDot(feed: _feed, onTap: _refresh),
          IconButton(
            tooltip: L.leaveGame,
            onPressed: _leave,
            icon: const Icon(Icons.logout, size: 20),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        // Stretch, or the score strip shrink-wraps its content and floats in
        // the middle of the screen instead of spanning it.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  myTeamId: _teamId,
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
                GameState.lobby => _waitingForHost(),
                GameState.board => _watchBoard(),
                GameState.clueReading ||
                GameState.buzzOpen ||
                GameState.buzzed ||
                GameState.resolved => _cluePhase(),
                GameState.finalWager => _wagerPhase(),
                GameState.finalClue || GameState.finalResult => _finalPhase(),
                GameState.finished => _finished(),
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- lobby ----------------

  Widget _waitingForHost() {
    return SnapshotBuilder<(String, int)>(
      feed: _feed,
      select: (s) => (s?.joinCode ?? '', s?.teams.length ?? 0),
      builder: (context, value) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: JColors.surface,
                  borderRadius: BorderRadius.circular(JRadius.card),
                  border: Border.all(color: JColors.line),
                ),
                child: Text(
                  value.$1,
                  style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 6,
                    fontWeight: FontWeight.w700,
                    color: JColors.goldBright,
                  ),
                ),
              ),
              const SizedBox(height: 26),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 18),
              const Text(
                L.waitingForHost,
                style: TextStyle(color: JColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                '${value.$2} ${L.teamsJoined.toLowerCase()}',
                style: const TextStyle(color: JColors.textFaint, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Read-only board. Players need to see the categories and what is still
  /// unplayed, both to follow along and to know what the host just picked.
  Widget _watchBoard() {
    return Column(
      children: [
        SnapshotBuilder<String?>(
          feed: _feed,
          select: (s) => s?.teamById(s.pickingTeamId)?.name,
          builder: (context, picking) => PhaseHint(
            picking == null ? L.hostIsChoosing : '${L.chooseTile} — $picking',
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
                interactive: false,
                onTapTile: (_) {},
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- clue in play ----------------

  Widget _cluePhase() {
    return SnapshotBuilder<(int?, GameState?, bool, String?, String?, bool)>(
      feed: _feed,
      select: (s) => (
        s?.currentClue?.clueId,
        s?.state,
        s?.answerRevealed ?? false,
        s?.buzzedTeamId,
        s?.buzzedPlayerId,
        s?.teamById(_teamId)?.lockedOut ?? false,
      ),
      builder: (context, _) {
        final snap = _feed.snapshot;
        final clue = snap?.currentClue;
        if (snap == null || clue == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final iBuzzed = snap.buzzedTeamId == _teamId;
        final someoneElse = snap.buzzedTeamId != null && !iBuzzed;
        final buzzedTeam = snap.teamById(snap.buzzedTeamId);

        return Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: CluePanel(
                  clue: _hideQuestionIfNeeded(clue, snap),
                  showAnswer: snap.answerRevealed,
                  banner: switch (snap.state) {
                    // A closed buzzer that is about to open on its own is
                    // worth counting: it is the difference between waiting and
                    // getting ready.
                    GameState.clueReading when snap.buzzOpensInMs != null =>
                      BuzzCountdown(
                        remainingMs: snap.buzzOpensInMs!,
                        builder: (context, left) => CluePanelBanner(
                          text: '${L.buzzOpensIn}  ·  $left',
                          color: JColors.gold,
                          icon: Icons.hourglass_bottom,
                        ),
                      ),
                    GameState.clueReading => const CluePanelBanner(
                      text: L.buzzerClosed,
                      color: JColors.textMuted,
                      icon: Icons.lock_outline,
                    ),
                    GameState.buzzed => CluePanelBanner(
                      text: iBuzzed
                          ? L.youBuzzed
                          : '${buzzerLabel(snap, buzzedTeam)} ${L.buzzedIn}',
                      color: iBuzzed ? JColors.correct : JColors.buzz,
                      icon: Icons.touch_app,
                    ),
                    _ => null,
                  },
                ),
              ),
            ),
            // The buzzer is a target: on a wide browser a metre-wide button is
            // harder to hit accurately than a big one in the middle.
            ControlShelf(children: [_buzzArea(snap, someoneElse)]),
          ],
        );
      },
    );
  }

  Widget _buzzArea(Snapshot snap, bool someoneElse) {
    final lockedOut = _me?.lockedOut ?? false;
    final open = snap.state == GameState.buzzOpen;

    if (lockedOut) {
      return _statusBar(L.lockedOut, Icons.block);
    }
    if (someoneElse) {
      return _statusBar(
        '${buzzerLabel(snap, snap.teamById(snap.buzzedTeamId))} ${L.buzzedIn}',
        Icons.hourglass_bottom,
      );
    }
    if (!open) {
      return _statusBar(L.buzzerClosed, Icons.lock_outline);
    }

    return _BuzzButton(sent: _buzzSent, onTap: _buzz);
  }

  Widget _statusBar(String text, IconData icon) {
    return Container(
      height: 68,
      width: double.infinity,
      decoration: BoxDecoration(
        color: JColors.surface,
        borderRadius: BorderRadius.circular(JRadius.card),
        border: Border.all(color: JColors.line),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: JColors.textFaint, size: 18),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: JColors.textMuted, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- final round ----------------

  Widget _wagerPhase() {
    return SnapshotBuilder<(String?, int?, int?)>(
      feed: _feed,
      select: (s) => (
        s?.currentClue?.topicName,
        s?.teamById(_teamId)?.score,
        s?.teamById(_teamId)?.wager,
      ),
      builder: (context, value) {
        final topic = value.$1;
        if (topic == null) {
          return Center(
            child: Text(
              L.waitingForHost,
              style: const TextStyle(color: JColors.textMuted),
            ),
          );
        }
        if (value.$3 != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${L.yourWager}: ${value.$3}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: JColors.goldBright,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  L.waitingForHost,
                  style: TextStyle(color: JColors.textFaint, fontSize: 13),
                ),
              ],
            ),
          );
        }

        // A wager has to be funded by points already won, so the ceiling is
        // the score -- and the server clamps it anyway.
        final score = value.$2 ?? 0;
        final max = score > 0 ? score : 0;
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
                      '${L.score}: $score  ·  ${L.maxWager} $max',
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
                    // Typing a number on a phone mid-game is the slow path; these are
                    // the three wagers people actually want.
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
                    FilledButton(
                      onPressed: () {
                        final amount = int.tryParse(_wager.text.trim());
                        if (amount != null) _submitWager(amount);
                      },
                      child: const Text(L.submitWager),
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

  Widget _finalPhase() {
    return SnapshotBuilder<(int?, bool)>(
      feed: _feed,
      select: (s) => (s?.currentClue?.clueId, s?.answerRevealed ?? false),
      builder: (context, _) {
        final snap = _feed.snapshot;
        final clue = snap?.currentClue;
        if (snap == null || clue == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.all(12),
          child: CluePanel(
            clue: _hideQuestionIfNeeded(clue, snap),
            showAnswer: snap.answerRevealed,
          ),
        );
      },
    );
  }

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

/// The one control that has to be unmissable and fast.
///
/// Full width, tall enough to hit without looking, and lit from within: while
/// the buzzer is open the glow breathes, which is what tells a player across the
/// room that it is their moment without them reading anything. The instant it is
/// pressed it latches, before any round trip.
class _BuzzButton extends StatefulWidget {
  const _BuzzButton({required this.sent, required this.onTap});

  final bool sent;
  final VoidCallback onTap;

  @override
  State<_BuzzButton> createState() => _BuzzButtonState();
}

class _BuzzButtonState extends State<_BuzzButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.sent) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_BuzzButton old) {
    super.didUpdateWidget(old);
    // A latched button stops breathing: the moment has passed to the host.
    if (widget.sent && _pulse.isAnimating) {
      _pulse.stop();
    } else if (!widget.sent && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_pulse.value);
          final glow = widget.sent ? 0.0 : 34 + 26 * t;
          return Container(
            height: 168,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.9),
                radius: 1.4,
                colors: widget.sent
                    ? const [
                        Color(0xFF3FD98A),
                        JColors.correct,
                        Color(0xFF14663B),
                      ]
                    : const [
                        JColors.buzzBright,
                        JColors.buzz,
                        Color(0xFF7D0B1B),
                      ],
                stops: const [0, 0.45, 1],
              ),
              borderRadius: BorderRadius.circular(JRadius.panel),
              boxShadow: [
                if (glow > 0)
                  BoxShadow(
                    color: JColors.buzz.withValues(alpha: 0.55),
                    blurRadius: glow,
                    spreadRadius: -8,
                  ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                  spreadRadius: -6,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.sent ? null : widget.onTap,
                splashColor: const Color(0x40FFFFFF),
                child: Center(
                  child: widget.sent
                      ? const Icon(Icons.check, size: 58, color: Colors.white)
                      : const Text(
                          L.buzz,
                          style: TextStyle(
                            fontSize: 46,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 1.5,
                            shadows: [
                              Shadow(
                                color: Color(0x66000000),
                                offset: Offset(0, 3),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
