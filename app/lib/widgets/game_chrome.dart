import 'dart:async';

import 'package:flutter/material.dart';

import '../core/game_feed.dart';
import '../core/models.dart';
import '../core/theme.dart';

/// Bits of furniture both consoles need: the connection indicator, the phase
/// hint above the board, the final standings, and the attribution dialog.

/// Live/offline, and a tap to force a REST resync.
class ConnectionDot extends StatelessWidget {
  const ConnectionDot({super.key, required this.feed, required this.onTap});

  final GameFeed feed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SnapshotBuilder<bool>(
      feed: feed,
      select: (_) => feed.connected,
      builder: (context, up) => IconButton(
        tooltip: up ? L.online : L.offline,
        onPressed: onTap,
        icon: Icon(
          up ? Icons.cloud_done_outlined : Icons.cloud_off,
          size: 20,
          color: up ? JColors.textMuted : JColors.wrong,
        ),
      ),
    );
  }
}

/// A quiet line saying what is expected right now.
class PhaseHint extends StatelessWidget {
  const PhaseHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: JColors.textFaint, fontSize: 12),
      ),
    );
  }
}

/// What is left of the reading time before an automatic buzzer opens.
///
/// Fed the remaining milliseconds from the snapshot rather than a deadline: the
/// server sends how long is left, not when it will be, so a device whose clock
/// is minutes out still counts the same seconds as everyone else. The buzzer
/// itself opens on the server -- this only says when to expect it.
class BuzzCountdown extends StatefulWidget {
  const BuzzCountdown({
    super.key,
    required this.remainingMs,
    required this.builder,
  });

  final int remainingMs;

  /// Given whole seconds left, rounded up so it reads 5, 4, 3, 2, 1 rather
  /// than sitting on 0 for the last part of a second.
  final Widget Function(BuildContext context, int secondsLeft) builder;

  @override
  State<BuzzCountdown> createState() => _BuzzCountdownState();
}

class _BuzzCountdownState extends State<BuzzCountdown> {
  late DateTime _deadline;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _arm();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant BuzzCountdown old) {
    super.didUpdateWidget(old);
    // A fresh snapshot for the same clue -- a team joining mid-read, say --
    // restates how long is left, and the server is the one keeping time.
    if (old.remainingMs != widget.remainingMs) _arm();
  }

  void _arm() {
    _deadline = DateTime.now().add(Duration(milliseconds: widget.remainingMs));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = _deadline.difference(DateTime.now()).inMilliseconds;
    return widget.builder(context, left <= 0 ? 0 : (left / 1000).ceil());
  }
}

/// Final standings, shared by the host console and the player devices.
class ResultsView extends StatelessWidget {
  const ResultsView({
    super.key,
    required this.teams,
    required this.attribution,
    required this.onRestart,
    this.highlightTeamId,
  });

  final List<TeamView> teams;
  final String? attribution;
  final VoidCallback onRestart;

  /// The viewer's own team, so a player can find themselves in the table.
  final String? highlightTeamId;

  @override
  Widget build(BuildContext context) {
    final ranked = [...teams]..sort((a, b) => b.score.compareTo(a.score));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      children: [
        Center(
          child: Text(
            L.gameOver.toUpperCase(),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: JColors.goldBright,
              letterSpacing: 2,
              shadows: const [Shadow(color: Color(0x66F2C14E), blurRadius: 28)],
            ),
          ),
        ),
        const SizedBox(height: 24),
        for (final (i, t) in ranked.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: i == 0
                      ? const [
                          Color(0xFFFFF0C4),
                          JColors.goldBright,
                          Color(0xFFC99A2E),
                        ]
                      : const [
                          Color(0xFF232B47),
                          JColors.surfaceHigh,
                          JColors.surface,
                        ],
                  stops: const [0, 0.12, 1],
                ),
                borderRadius: BorderRadius.circular(JRadius.card),
                border: Border.all(
                  color: i == 0
                      ? JColors.goldBright
                      : t.id == highlightTeamId
                      ? JColors.gold
                      : JColors.line,
                ),
                boxShadow: [
                  if (i == 0)
                    BoxShadow(
                      color: JColors.gold.withValues(alpha: 0.35),
                      blurRadius: 30,
                      spreadRadius: -8,
                    ),
                ],
              ),
              child: Row(
                children: [
                  Text(
                    '${i + 1}',
                    style: engraved(
                      20,
                      color: i == 0
                          ? const Color(0xFF14120A)
                          : JColors.textFaint,
                      glow: false,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: i == 0 ? JColors.backdrop : JColors.text,
                      ),
                    ),
                  ),
                  if (i == 0)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.emoji_events,
                        size: 18,
                        color: Color(0xFF14120A),
                      ),
                    ),
                  Text(
                    '${t.score}',
                    style: engraved(
                      27,
                      color: i == 0 ? const Color(0xFF14120A) : JColors.gold,
                      glow: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 26),
        if (attribution != null)
          Text(
            attribution!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: JColors.textFaint,
              fontSize: 11,
              height: 1.5,
            ),
          ),
        const SizedBox(height: 20),
        OutlinedButton(onPressed: onRestart, child: const Text(L.backToStart)),
      ],
    );
  }
}

/// The questions belong to their authors, so the credit travels with them.
void showAboutJeopard(BuildContext context, String? attribution) {
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text(L.appTitle),
      content: Text(
        attribution ?? 'moazrovne.net',
        style: const TextStyle(color: JColors.textMuted, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(L.ok),
        ),
      ],
    ),
  );
}

/// "Person (Team)" so everyone knows who is answering.
String buzzerLabel(Snapshot snap, TeamView? team) {
  final playerId = snap.buzzedPlayerId;
  if (team != null && playerId != null) {
    for (final p in team.players) {
      if (p.id == playerId) return '${p.name} (${team.name})';
    }
  }
  return team?.name ?? '';
}
