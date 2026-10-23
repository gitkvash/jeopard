import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/game_feed.dart';
import '../core/models.dart';
import '../core/notices.dart';
import '../core/providers.dart';
import '../core/responsive.dart';
import '../core/rest_client.dart';
import '../core/game_sounds.dart';
import '../core/session.dart';
import '../core/sfx.dart';
import '../core/session_store.dart';
import '../core/theme.dart';
import '../role_screen.dart';
import '../widgets/board_grid.dart';
import '../widgets/clue_panel.dart';
import '../widgets/game_chrome.dart';
import '../widgets/scoreboard.dart';
import '../widgets/stage.dart';
import '../widgets/toast.dart';
import 'lobby_team_picker.dart';

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
  late final GameSounds _sounds;
  StreamSubscription<Notice>? _noticeSub;

  /// Set the instant we send a buzz so the button reacts without waiting for
  /// the round trip. Cleared when the next snapshot tells us the real outcome.
  bool _buzzSent = false;
  int? _buzzSentForClue;
  int? _lastClueId;
  GameState? _lastState;

  /// Whether the last snapshot made it this team's turn to choose, so the phone
  /// buzzes once when the turn arrives rather than on every broadcast.
  bool _wasMyTurn = false;

  final _wager = TextEditingController();
  final _finalAnswer = TextEditingController();

  /// Set while a tile this player tapped is on its way to the server, so a
  /// second tap cannot send a second pick.
  bool _picking = false;

  String get _gameId => widget.session.gameId;
  String get _playerToken => widget.session.playerToken ?? '';

  /// The team this player is on *now*. Read off the game rather than off what was
  /// stored at join time, because a player can be moved -- by choice in the lobby
  /// or by the host mid-game -- and everything here (score, lockout, the buzz)
  /// belongs to whichever team that is.
  String? get _teamId => _myTeam?.id ?? widget.session.teamId;

  TeamView? get _myTeam {
    final id = widget.session.playerId;
    final snap = _feed.snapshot;
    if (id == null || snap == null) return null;
    for (final t in snap.teams) {
      if (t.players.any((p) => p.id == id)) return t;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _feed = GameFeed(gameId: _gameId, onResync: _refresh)..addListener(_onFeed);
    _sounds = GameSounds(
      _feed,
      role: SoundRole.team,
      myTeamId: widget.session.teamId,
      teamIdOf: () => _teamId,
    );
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
    _finalAnswer.dispose();
    super.dispose();
  }

  void _onFeed() {
    final snap = _feed.snapshot;
    final myTurn = _isMyTurnToPick(snap);
    if (myTurn && !_wasMyTurn) HapticFeedback.mediumImpact();
    _wasMyTurn = myTurn;

    final clueId = snap?.currentClue?.clueId;
    if (_buzzSent &&
        (clueId != _buzzSentForClue || snap?.state != GameState.buzzOpen)) {
      setState(() => _buzzSent = false);
    }
    if (_lastClueId != clueId ||
        (snap?.state == GameState.buzzOpen && _lastState != GameState.buzzOpen)) {
      _buzzSentForClue = null;
    }
    _lastClueId = clueId;
    _lastState = snap?.state;

    final myAns = _me?.finalAnswer;
    if (myAns != null && myAns.isNotEmpty && _finalAnswer.text.isEmpty) {
      _finalAnswer.text = myAns;
    }

    if (snap?.state == GameState.finished) SessionStore.clear();
  }

  /// The host edited a score or moved someone: say so, to the person it
  /// happened to in the second person. If the host ended the game, return to home.
  void _onNotice(Notice n) {
    if (n.isGameTerminated) {
      SessionStore.clear();
      if (!mounted) return;
      showToast(context, L.gameEndedNotice);
      RoleScreen.replaceAll(context);
      return;
    }
    final text = describeNotice(n, myPlayerId: widget.session.playerId);
    if (text != null && mounted) showToast(context, text);
  }

  /// Before the game starts: sit with another team, start one, or go solo.
  Future<void> _changeTeam({String? teamId, String? newTeamName}) async {
    try {
      final s = await ref
          .read(restClientProvider)
          .changeTeam(
            gameId: _gameId,
            playerToken: _playerToken,
            teamId: teamId,
            newTeamName: newTeamName,
          );
      _feed.push(s);
      // What was stored at join time is now stale; a reload should come back
      // onto the team this player actually chose.
      final mine = _myTeam;
      if (mine != null) {
        SessionStore.write(
          widget.session.withTeam(teamId: mine.id, teamName: mine.name),
        );
      }
    } on ApiException catch (e) {
      if (e.isNotFound) {
        SessionStore.clear();
        if (mounted) {
          showToast(context, L.gameEndedNotice);
          RoleScreen.replaceAll(context);
        }
        return;
      }
      if (mounted) showToast(context, describeError(e), error: true);
    } catch (e) {
      if (mounted) showToast(context, describeError(e), error: true);
    }
  }

  Future<void> _refresh() async {
    try {
      final s = await ref.read(restClientProvider).snapshot(_gameId);
      _feed.push(s);
    } on ApiException catch (e) {
      if (e.isNotFound) {
        SessionStore.clear();
        if (mounted) {
          showToast(context, L.gameEndedNotice);
          RoleScreen.replaceAll(context);
        }
      }
    } catch (_) {
      // Next broadcast will resync.
    }
  }

  void _buzz() {
    final snap = _feed.snapshot;
    if (snap == null || snap.state != GameState.buzzOpen) return;
    final clueId = snap.currentClue?.clueId;
    // The button fires on the finger landing and again, for keyboards and
    // screen readers, on the tap; only the first of those is a press.
    if (_buzzSent && _buzzSentForClue == clueId) return;

    // Out of the door before anything else: the haptic, the sound and the
    // rebuild below are all time the press would otherwise spend on the phone.
    // Prefer the socket -- it is the lowest-latency path. If it is down, fall
    // back to REST so a flaky connection does not silently cost the round.
    if (_feed.isSocketConnected) {
      _feed.buzz(_playerToken);
    } else {
      ref
          .read(restClientProvider)
          .buzz(_gameId, _playerToken, reactionMs: _feed.reactionMs)
          .then(_feed.push)
          .catchError((Object e) {
            if (e is ApiException && e.isNotFound) {
              SessionStore.clear();
              if (mounted) {
                showToast(context, L.gameEndedNotice);
                RoleScreen.replaceAll(context);
              }
              return Future<void>.value();
            }
            if (mounted) setState(() => _buzzSent = false);
            return Future<void>.value();
          });
    }

    HapticFeedback.heavyImpact();
    Sfx.instance.play(Cue.tap);
    setState(() {
      _buzzSent = true;
      _buzzSentForClue = clueId;
    });
  }

  Future<void> _eliminateTopic(int clueId) async {
    try {
      final s = await ref
          .read(restClientProvider)
          .eliminateTopic(_gameId, playerToken: _playerToken, clueId: clueId);
      _feed.push(s);
    } on ApiException catch (e) {
      if (e.isNotFound) {
        SessionStore.clear();
        if (mounted) {
          showToast(context, L.gameEndedNotice);
          RoleScreen.replaceAll(context);
        }
        return;
      }
      if (mounted) {
        showToast(
          context,
          e.isConflict ? L.pickNotYourTurn : describeError(e),
          error: true,
        );
      }
      unawaited(_refresh());
    } catch (e) {
      if (mounted) showToast(context, describeError(e), error: true);
    }
  }

  Future<void> _submitFinalAnswer(String answer) async {
    try {
      final s = await ref
          .read(restClientProvider)
          .submitFinalAnswer(_gameId, _playerToken, answer);
      _feed.push(s);
      if (mounted) {
        showToast(context, L.answerSubmitted);
      }
    } on ApiException catch (e) {
      if (e.isNotFound) {
        SessionStore.clear();
        if (mounted) {
          showToast(context, L.gameEndedNotice);
          RoleScreen.replaceAll(context);
        }
        return;
      }
      if (mounted) {
        showToast(context, describeError(e), error: true);
      }
    } catch (e) {
      if (mounted) {
        showToast(context, describeError(e), error: true);
      }
    }
  }

  Future<void> _submitWager(int amount) async {
    try {
      final s = await ref
          .read(restClientProvider)
          .wager(_gameId, _playerToken, amount);
      _feed.push(s);
    } on ApiException catch (e) {
      if (e.isNotFound) {
        SessionStore.clear();
        if (mounted) {
          showToast(context, L.gameEndedNotice);
          RoleScreen.replaceAll(context);
        }
        return;
      }
      if (mounted) {
        showToast(context, describeError(e), error: true);
      }
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
    unawaited(
      ref
          .read(restClientProvider)
          .leavePlayer(_gameId, _playerToken)
          .catchError((_) {}),
    );
    if (!mounted) return;
    RoleScreen.replaceAll(context);
  }

  /// My team -- the thing that holds my score.
  TeamView? get _me => _feed.snapshot?.teamById(_teamId);

  /// True when this game lets the players pick and the turn is my team's.
  bool _isMyTurnToPick(Snapshot? snap) =>
      snap != null &&
      snap.playersPickClues &&
      snap.state == GameState.board &&
      snap.pickingTeamId != null &&
      snap.pickingTeamId == _teamId;

  /// Put a tile in play on my team's turn. The server decides whether the turn
  /// really is ours -- a tap that lost the race to a teammate, or to the host
  /// choosing for us, is refused there and explained here.
  Future<void> _pickTile(TileView tile) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final s = await ref
          .read(restClientProvider)
          .pickClue(_gameId, _playerToken, tile.clueId);
      _feed.push(s);
    } on ApiException catch (e) {
      if (e.isNotFound) {
        SessionStore.clear();
        if (mounted) {
          showToast(context, L.gameEndedNotice);
          RoleScreen.replaceAll(context);
        }
        return;
      }
      if (mounted) {
        showToast(
          context,
          e.isConflict ? L.pickNotYourTurn : describeError(e),
          error: true,
        );
      }
      // Whatever beat us to it is already on the wire; make sure we have it.
      unawaited(_refresh());
    } catch (e) {
      if (mounted) showToast(context, describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// The server already omits [CurrentClue.question] on this game -- this just
  /// turns that gap into something a player understands instead of a blank
  /// panel, or a lonely "...".
  CurrentClue _hideQuestionIfNeeded(CurrentClue clue, Snapshot snap) =>
      (clue.question == null && !snap.questionsVisibleToParticipants)
      ? clue.copyWith(question: L.questionHiddenFromParticipants)
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
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.session.playerName ?? L.team,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SnapshotBuilder<String>(
                feed: _feed,
                select: (s) {
                  final mine = _myTeam;
                  if (mine == null) return widget.session.teamName ?? '';
                  return mine.solo ? L.noTeam : mine.name;
                },
                builder: (context, name) => Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: JColors.textFaint,
                  ),
                ),
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
                            color: score < 0
                                ? JColors.wrongBright
                                : JColors.gold,
                            glow: false,
                          ),
                        ),
                      ),
                    ),
            ),
            const SoundToggle(),
            ConnectionDot(feed: _feed, onTap: _refresh),
            IconButton(
              tooltip: L.leaveGame,
              onPressed: _leave,
              icon: const Icon(Icons.logout, size: 20),
            ),
            const SizedBox(width: 4),
          ],
        ),
        // Sides only: in landscape a notch sits where the board starts. The top is
        // the app bar's, and the bottom is the control shelf's own.
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
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
                    GameState.finalClue ||
                    GameState.finalResult => _finalPhase(),
                    GameState.finished => _finished(),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- lobby ----------------

  Widget _waitingForHost() {
    return SnapshotBuilder<String>(
      feed: _feed,
      select: (s) => s?.joinCode ?? '',
      builder: (context, code) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
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
                        code,
                        style: const TextStyle(
                          fontSize: 24,
                          letterSpacing: 6,
                          fontWeight: FontWeight.w700,
                          color: JColors.goldBright,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text(
                        L.waitingForHost,
                        style: TextStyle(
                          color: JColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  LobbyTeamPicker(
                    feed: _feed,
                    myTeamId: () => _teamId,
                    onChange: _changeTeam,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Read-only board. Players need to see the categories and what is still
  /// unplayed, both to follow along and to know what the host just picked.
  Widget _watchBoard() {
    return Column(
      children: [
        SnapshotBuilder<(String?, String?, bool)>(
          feed: _feed,
          select: (s) => (
            s?.pickingTeamId,
            s?.teamById(s.pickingTeamId)?.name,
            s?.playersPickClues ?? false,
          ),
          builder: (context, value) {
            final (pickingId, picking, playersPick) = value;
            if (playersPick) {
              if (pickingId != null && pickingId == _teamId) {
                return const YourTurnBanner();
              }
              return PhaseHint(
                picking == null ? L.hostIsChoosing : L.isChoosing(picking),
              );
            }
            return PhaseHint(
              picking == null ? L.hostIsChoosing : '${L.chooseTile} — $picking',
            );
          },
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              9,
              0,
              9,
              12 + MediaQuery.paddingOf(context).bottom,
            ),
            // Rebuilt when the turn changes too: the same board is read-only
            // for everyone but whoever holds the pick.
            child: SnapshotBuilder<(List<BoardColumn>, bool)>(
              feed: _feed,
              select: (s) =>
                  (s?.board ?? const <BoardColumn>[], _isMyTurnToPick(s)),
              equals: (a, b) => a.$2 == b.$2 && boardsEqual(a.$1, b.$1),
              builder: (context, value) => BoardGrid(
                board: value.$1,
                interactive: value.$2,
                onTapTile: _pickTile,
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

        return ClueLayout(
          panel: CluePanel(
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
          // The buzzer is a target: on a wide browser a metre-wide button is
          // harder to hit accurately than a big one in the middle.
          controls: (side) => ControlShelf(
            side: side,
            children: [_buzzArea(snap, someoneElse)],
          ),
        );
      },
    );
  }

  Widget _buzzArea(Snapshot snap, bool someoneElse) {
    final lockedOut = _me?.lockedOut ?? false;
    final open = snap.state == GameState.buzzOpen;
    final iBuzzed = snap.buzzedTeamId == _teamId;
    final clueId = snap.currentClue?.clueId;

    if (lockedOut) {
      return _statusBar(L.lockedOut, Icons.block);
    }
    if (iBuzzed) {
      return _BuzzButton(
        status: BuzzButtonStatus.won,
        onTap: () {},
      );
    }
    if (someoneElse) {
      final lostLabel =
          '${buzzerLabel(snap, snap.teamById(snap.buzzedTeamId))} ${L.buzzedIn}';
      if (_buzzSentForClue == clueId) {
        return _BuzzButton(
          status: BuzzButtonStatus.lost,
          lostLabel: lostLabel,
          onTap: () {},
        );
      }
      return _statusBar(lostLabel, Icons.hourglass_bottom);
    }
    if (snap.state == GameState.resolved) {
      return _statusBar(L.waitingForHost, Icons.hourglass_bottom);
    }
    if (!open) {
      return _statusBar(L.buzzerClosed, Icons.lock_outline);
    }

    return _BuzzButton(
      status: _buzzSent ? BuzzButtonStatus.pending : BuzzButtonStatus.ready,
      onTap: _buzz,
    );
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
    return SnapshotBuilder<(String?, int?, int?, String?, List<BoardColumn>)>(
      feed: _feed,
      select: (s) => (
        s?.currentClue?.topicName,
        s?.teamById(_teamId)?.score,
        s?.teamById(_teamId)?.wager,
        s?.pickingTeamId,
        s?.board ?? const <BoardColumn>[],
      ),
      equals: (a, b) =>
          a.$1 == b.$1 &&
          a.$2 == b.$2 &&
          a.$3 == b.$3 &&
          a.$4 == b.$4 &&
          boardsEqual(a.$5, b.$5),
      builder: (context, value) {
        final snap = _feed.snapshot;
        if (snap == null) return const SizedBox.shrink();

        final topic = value.$1;
        if (topic == null) {
          return _topicEliminationPhase(snap);
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

  Widget _topicEliminationPhase(Snapshot snap) {
    final isMyTurn = snap.pickingTeamId == _teamId;
    final pickingTeam = snap.teamById(snap.pickingTeamId);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isMyTurn ? const Color(0x33C89B3C) : JColors.surface,
                    borderRadius: BorderRadius.circular(JRadius.card),
                    border: Border.all(
                      color: isMyTurn ? JColors.goldBright : JColors.line,
                      width: isMyTurn ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isMyTurn
                            ? Icons.touch_app
                            : Icons.hourglass_top_outlined,
                        color:
                            isMyTurn ? JColors.goldBright : JColors.textMuted,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isMyTurn
                              ? L.yourTurnToEliminate
                              : '${pickingTeam?.name ?? ''}: ${L.waitingForElimination}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isMyTurn ? FontWeight.bold : FontWeight.w500,
                            color: isMyTurn
                                ? JColors.goldBright
                                : JColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  L.eliminationPhase,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                const Text(
                  'დარჩება მხოლოდ 1 ფინალური თემა',
                  style: TextStyle(color: JColors.textFaint, fontSize: 13),
                ),
                const SizedBox(height: 14),
                for (final col in snap.board) ...[
                  _buildTeamEliminationTopicCard(col, isMyTurn),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTeamEliminationTopicCard(BoardColumn col, bool isMyTurn) {
    final tile = col.tiles.firstOrNull;
    if (tile == null) return const SizedBox.shrink();
    final eliminated = tile.status == TileStatus.done;

    return Card(
      color: eliminated ? const Color(0x331E293B) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JRadius.card),
        side: BorderSide(
          color: eliminated ? JColors.line : JColors.brass,
          width: eliminated ? 1 : 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    col.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      decoration:
                          eliminated ? TextDecoration.lineThrough : null,
                      color: eliminated ? JColors.textFaint : Colors.white,
                    ),
                  ),
                  if (eliminated) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.close_rounded,
                          size: 13,
                          color: JColors.wrongBright,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          L.topicEliminated,
                          style: const TextStyle(
                            fontSize: 12,
                            color: JColors.wrongBright,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (!eliminated && isMyTurn) ...[
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: JColors.wrong,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () => _eliminateTopic(tile.clueId),
                icon: const Icon(Icons.close, size: 16),
                label: const Text(L.eliminateTopic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _finalPhase() {
    return SnapshotBuilder<(int?, bool, bool, String?, bool)>(
      feed: _feed,
      select: (s) => (
        s?.currentClue?.clueId,
        s?.answerRevealed ?? false,
        s?.finalAnswersLocked ?? false,
        s?.teamById(_teamId)?.finalAnswer,
        s?.teamById(_teamId)?.hasFinalAnswer ?? false,
      ),
      builder: (context, _) {
        final snap = _feed.snapshot;
        final clue = snap?.currentClue;
        if (snap == null || clue == null) return const SizedBox.shrink();

        final locked = snap.finalAnswersLocked;
        final isResult = snap.state == GameState.finalResult;

        return ClueLayout(
          panel: CluePanel(
            clue: _hideQuestionIfNeeded(clue, snap),
            showAnswer: snap.answerRevealed,
            banner: isResult
                ? null
                : locked
                    ? const CluePanelBanner(
                        text: L.answersLocked,
                        color: JColors.goldBright,
                        icon: Icons.lock_outline,
                      )
                    : FinalRoundCountdown(
                        totalSeconds: 30,
                        builder: (context, secondsLeft) => CluePanelBanner(
                          text: secondsLeft > 0
                              ? '${L.timeRemaining}: $secondsLeft წმ'
                              : 'დრო ამოიწურა — დაელოდეთ ჰოსტს...',
                          color: secondsLeft > 0
                              ? JColors.gold
                              : JColors.wrongBright,
                          icon: secondsLeft > 0
                              ? Icons.timer_outlined
                              : Icons.hourglass_disabled,
                        ),
                      ),
          ),
          controls: (side) => ControlShelf(
            side: side,
            children: [
              _finalAnswerArea(snap, locked, isResult),
            ],
          ),
        );
      },
    );
  }

  Widget _finalAnswerArea(Snapshot snap, bool locked, bool isResult) {
    final myAnswer = _me?.finalAnswer;
    final hasAnswer = _me?.hasFinalAnswer ?? false;

    if (isResult) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _statusBar(L.answersLocked, Icons.lock_outline),
          if (myAnswer != null && myAnswer.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${L.yourFinalAnswer}: „$myAnswer“',
              style: const TextStyle(
                color: JColors.goldBright,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ],
      );
    }

    if (locked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _statusBar(L.answersLocked, Icons.lock_outline),
          const SizedBox(height: 8),
          Text(
            myAnswer != null && myAnswer.trim().isNotEmpty
                ? '${L.yourFinalAnswer}: „$myAnswer“'
                : L.noAnswerGiven,
            style: TextStyle(
              color: myAnswer != null && myAnswer.trim().isNotEmpty
                  ? JColors.goldBright
                  : JColors.textMuted,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _finalAnswer,
                textInputAction: TextInputAction.send,
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) _submitFinalAnswer(val.trim());
                },
                decoration: InputDecoration(
                  labelText: L.yourFinalAnswer,
                  hintText: 'ჩაწერეთ პასუხი...',
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  suffixIcon: hasAnswer
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: JColors.correct,
                          size: 18,
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onPressed: () {
                final txt = _finalAnswer.text.trim();
                if (txt.isNotEmpty) _submitFinalAnswer(txt);
              },
              icon: const Icon(Icons.send, size: 16),
              label: Text(hasAnswer ? 'განახლება' : L.submitAnswer),
            ),
          ],
        ),
        if (hasAnswer) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check,
                size: 13,
                color: JColors.correct,
              ),
              const SizedBox(width: 4),
              Text(
                '${L.answerSubmitted}: „${myAnswer ?? _finalAnswer.text}“',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: JColors.correct,
                ),
              ),
            ],
          ),
        ],
      ],
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

/// The visual and interactive state of the buzzer on a player's screen.
enum BuzzButtonStatus {
  /// Open and ready to buzz: breathes red, inviting the press.
  ready,

  /// Pressed! Waiting for arbitration: amber/orange with spinner ("მოიცადეთ...").
  pending,

  /// This team won the race: bright green with checkmark ("თქვენ დააჭირეთ! უპასუხეთ").
  won,

  /// Another team buzzed first: red with close icon ("სხვამ დაასწრო").
  lost,
}

/// The one control that has to be unmissable and fast.
///
/// Full width, tall enough to hit without looking, and lit from within: while
/// the buzzer is open the glow breathes, which is what tells a player across the
/// room that it is their moment without them reading anything. The instant it is
/// pressed it turns amber/orange ("მოიცადეთ...") to indicate arbitration is pending,
/// before settling into green (won) or red (lost).
class _BuzzButton extends StatefulWidget {
  const _BuzzButton({
    required this.status,
    required this.onTap,
    this.lostLabel,
  });

  final BuzzButtonStatus status;
  final VoidCallback onTap;
  final String? lostLabel;

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
    if (widget.status == BuzzButtonStatus.ready ||
        widget.status == BuzzButtonStatus.pending) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_BuzzButton old) {
    super.didUpdateWidget(old);
    final shouldAnimate = widget.status == BuzzButtonStatus.ready ||
        widget.status == BuzzButtonStatus.pending;
    if (shouldAnimate && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!shouldAnimate && _pulse.isAnimating) {
      _pulse.stop();
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
          final glow = switch (widget.status) {
            BuzzButtonStatus.ready => 34 + 26 * t,
            BuzzButtonStatus.pending => 20 + 16 * t,
            BuzzButtonStatus.won => 28.0,
            BuzzButtonStatus.lost => 0.0,
          };
          final glowColor = switch (widget.status) {
            BuzzButtonStatus.ready => JColors.buzz.withValues(alpha: 0.55),
            BuzzButtonStatus.pending =>
              JColors.buzzPending.withValues(alpha: 0.55),
            BuzzButtonStatus.won => JColors.correct.withValues(alpha: 0.55),
            BuzzButtonStatus.lost => Colors.transparent,
          };
          final colors = switch (widget.status) {
            BuzzButtonStatus.ready => const [
              JColors.buzzBright,
              JColors.buzz,
              Color(0xFF7D0B1B),
            ],
            BuzzButtonStatus.pending => const [
              JColors.buzzPendingBright,
              JColors.buzzPending,
              JColors.buzzPendingDeep,
            ],
            BuzzButtonStatus.won => const [
              Color(0xFF3FD98A),
              JColors.correct,
              Color(0xFF14663B),
            ],
            BuzzButtonStatus.lost => const [
              Color(0xFFE53935),
              JColors.wrong,
              Color(0xFF5C0B14),
            ],
          };

          final content = switch (widget.status) {
            BuzzButtonStatus.ready => const Text(
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
            BuzzButtonStatus.pending => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.5,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  L.buzzWaiting,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                    shadows: [
                      Shadow(
                        color: Color(0x66000000),
                        offset: Offset(0, 3),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            BuzzButtonStatus.won => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 52, color: Colors.white),
                SizedBox(height: 6),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    L.youBuzzed,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5,
                      shadows: [
                        Shadow(
                          color: Color(0x66000000),
                          offset: Offset(0, 3),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            BuzzButtonStatus.lost => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.close, size: 48, color: Colors.white),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    widget.lostLabel ?? L.someoneElseBuzzed,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5,
                      shadows: [
                        Shadow(
                          color: Color(0x66000000),
                          offset: Offset(0, 3),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          };

          final canTap = widget.status == BuzzButtonStatus.ready;

          return Container(
            height: 168,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.9),
                radius: 1.4,
                colors: colors,
                stops: const [0, 0.45, 1],
              ),
              borderRadius: BorderRadius.circular(JRadius.panel),
              boxShadow: [
                if (glow > 0)
                  BoxShadow(
                    color: glowColor,
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
            // A tap only completes when the finger lifts, and only once the
            // gesture arena has ruled out a scroll -- easily 100 ms after the
            // press, longer for a player who leans on the button. The buzzer
            // goes on the finger landing; the tap stays for keyboards and
            // screen readers, and the press handler ignores the second call.
            child: Listener(
              onPointerDown: canTap ? (_) => widget.onTap() : null,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: canTap ? widget.onTap : null,
                  splashColor: const Color(0x40FFFFFF),
                  child: Center(child: content),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
