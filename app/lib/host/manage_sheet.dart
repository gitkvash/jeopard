import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/game_feed.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../widgets/stage.dart';

/// Where a person is being sent. [teamId] and [newTeamName] both null means
/// "on their own".
typedef MovePlayer =
    Future<void> Function(
      String playerId, {
      String? teamId,
      String? newTeamName,
    });

/// The states the server lets a person be moved in: between clues, when no buzz,
/// lockout or judging mark is naming a team that is about to change.
bool canMovePlayers(GameState? state) =>
    state == GameState.lobby ||
    state == GameState.board ||
    state == GameState.resolved ||
    state == GameState.finalWager;

/// The host's corrections: edit a team's score, and move people between teams or
/// out on their own. Everyone is told what the host changes -- the server sends
/// the notice -- so nothing here needs to announce itself.
///
/// It watches [feed], so it stays right as the changes it makes come back.
Future<void> showManageSheet(
  BuildContext context, {
  required GameFeed feed,
  required Future<void> Function(String teamId, int score) onSetScore,
  required MovePlayer onMove,
  VoidCallback? onEndGame,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: JColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(JRadius.panel)),
    ),
    builder: (_) =>
        ManagePanel(feed: feed, onSetScore: onSetScore, onMove: onMove, onEndGame: onEndGame),
  );
}

class ManagePanel extends StatelessWidget {
  const ManagePanel({
    super.key,
    required this.feed,
    required this.onSetScore,
    required this.onMove,
    this.onEndGame,
  });

  final GameFeed feed;
  final Future<void> Function(String teamId, int score) onSetScore;
  final MovePlayer onMove;
  final VoidCallback? onEndGame;

  @override
  Widget build(BuildContext context) {
    return SnapshotBuilder<(GameState?, List<TeamView>)>(
      feed: feed,
      select: (s) => (s?.state, s?.teams ?? const <TeamView>[]),
      equals: (a, b) => a.$1 == b.$1 && rosterEqual(a.$2, b.$2),
      builder: (context, value) {
        final movable = canMovePlayers(value.$1);
        final teams = value.$2;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.88,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        L.manage,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: L.cancel,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
                if (!movable) ...[
                  const SizedBox(height: 4),
                  Text(
                    L.movesBetweenClues,
                    style: const TextStyle(
                      color: JColors.textFaint,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (teams.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      L.noTeamsYet,
                      style: TextStyle(color: JColors.textFaint, fontSize: 13),
                    ),
                  ),
                for (final team in teams)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TeamCard(
                      team: team,
                      others: [
                        for (final t in teams)
                          if (!t.solo && t.id != team.id) t,
                      ],
                      movable: movable,
                      onSetScore: onSetScore,
                      onMove: onMove,
                    ),
                  ),
                if (onEndGame != null) ...[
                  const SizedBox(height: 16),
                  const Divider(color: JColors.line),
                  const SizedBox(height: 12),
                  Center(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: JColors.wrongBright,
                        side: const BorderSide(color: JColors.wrong),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        onEndGame!();
                      },
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text(L.endGame),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.others,
    required this.movable,
    required this.onSetScore,
    required this.onMove,
  });

  final TeamView team;

  /// Teams a person here could be sent to: chosen teams, not solo players.
  final List<TeamView> others;
  final bool movable;
  final Future<void> Function(String teamId, int score) onSetScore;
  final MovePlayer onMove;

  Future<void> _editScore(BuildContext context) async {
    final score = await showDialog<int>(
      context: context,
      builder: (_) => _ScoreDialog(team: team),
    );
    if (score != null && score != team.score) {
      await onSetScore(team.id, score);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Plate(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (team.solo) ...[
                const Icon(
                  Icons.person_outline,
                  size: 16,
                  color: JColors.textFaint,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  team.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${team.score}',
                style: engraved(
                  24,
                  color: team.score < 0 ? JColors.wrongBright : JColors.gold,
                  glow: false,
                ),
              ),
              IconButton(
                tooltip: L.editScore,
                onPressed: () => _editScore(context),
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
            ],
          ),
          for (final p in team.players)
            _PlayerRow(
              player: p,
              team: team,
              others: others,
              movable: movable,
              onMove: onMove,
            ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.team,
    required this.others,
    required this.movable,
    required this.onMove,
  });

  final PlayerView player;
  final TeamView team;
  final List<TeamView> others;
  final bool movable;
  final MovePlayer onMove;

  Future<void> _choose(BuildContext context, _Destination d) async {
    switch (d) {
      case _ToTeam(:final team):
        await onMove(player.id, teamId: team.id);
      case _ToNewTeam():
        final name = await showDialog<String>(
          context: context,
          builder: (_) => const _NewTeamDialog(),
        );
        if (name != null && name.isNotEmpty) {
          await onMove(player.id, newTeamName: name);
        }
      case _Alone():
        await onMove(player.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2),
      child: Row(
        children: [
          Icon(
            player.host ? Icons.co_present_outlined : Icons.person_outline,
            size: 15,
            color: player.host ? JColors.brass : JColors.textFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              player.host ? '${player.name}  ·  ${L.hostSeat}' : player.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: JColors.textMuted, fontSize: 13),
            ),
          ),
          // The host's own seat stays where it is: the server refuses to move it.
          if (!player.host)
            PopupMenuButton<_Destination>(
              tooltip: L.moveTo,
              enabled: movable,
              icon: const Icon(Icons.swap_horiz, size: 20),
              onSelected: (d) => _choose(context, d),
              itemBuilder: (_) => [
                for (final t in others) PopupMenuItem(value: _ToTeam(t), child: Text(t.name)),
                const PopupMenuItem(
                  value: _ToNewTeam(),
                  child: Text(L.moveToNewTeam),
                ),
                if (!team.solo)
                  const PopupMenuItem(value: _Alone(), child: Text(L.moveAlone)),
              ],
            ),
        ],
      ),
    );
  }
}

sealed class _Destination {
  const _Destination();
}

class _ToTeam extends _Destination {
  const _ToTeam(this.team);
  final TeamView team;
}

class _ToNewTeam extends _Destination {
  const _ToNewTeam();
}

class _Alone extends _Destination {
  const _Alone();
}

class _ScoreDialog extends StatefulWidget {
  const _ScoreDialog({required this.team});

  final TeamView team;

  @override
  State<_ScoreDialog> createState() => _ScoreDialogState();
}

class _ScoreDialogState extends State<_ScoreDialog> {
  late final _controller = TextEditingController(text: '${widget.team.score}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? get _value => int.tryParse(_controller.text.trim());

  void _submit() {
    final v = _value;
    if (v != null) Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${L.editScore} — ${widget.team.name}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^-?\d{0,7}')),
        ],
        decoration: const InputDecoration(labelText: L.newScore),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(L.cancel),
        ),
        TextButton(
          onPressed: _value == null ? null : _submit,
          child: const Text(L.save),
        ),
      ],
    );
  }
}

class _NewTeamDialog extends StatefulWidget {
  const _NewTeamDialog();

  @override
  State<_NewTeamDialog> createState() => _NewTeamDialogState();
}

class _NewTeamDialogState extends State<_NewTeamDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    if (v.isNotEmpty) Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(L.createTeam),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(labelText: L.newTeamName),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(L.cancel),
        ),
        TextButton(
          onPressed: _controller.text.trim().isEmpty ? null : _submit,
          child: const Text(L.save),
        ),
      ],
    );
  }
}
