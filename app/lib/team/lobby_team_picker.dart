import 'package:flutter/material.dart';

import '../core/game_feed.dart';
import '../core/models.dart';
import '../core/theme.dart';

/// Where a player waits for the host, and where they can still change their mind
/// about who they play with: stay on their team, sit with another, start a new
/// one, or leave and play alone.
///
/// Only shown before the game starts; after that it is the host who moves people.
/// [onChange] gets the same three-way choice the server does -- both null means
/// "on my own".
class LobbyTeamPicker extends StatefulWidget {
  const LobbyTeamPicker({
    super.key,
    required this.feed,
    required this.myTeamId,
    required this.onChange,
  });

  final GameFeed feed;

  /// Asked on every build: the team this player is on moves as they change it.
  final String? Function() myTeamId;

  final Future<void> Function({String? teamId, String? newTeamName}) onChange;

  @override
  State<LobbyTeamPicker> createState() => _LobbyTeamPickerState();
}

class _LobbyTeamPickerState extends State<LobbyTeamPicker> {
  final _newTeam = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _newTeam.dispose();
    super.dispose();
  }

  Future<void> _change({String? teamId, String? newTeamName}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onChange(teamId: teamId, newTeamName: newTeamName);
      if (newTeamName != null) _newTeam.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SnapshotBuilder<List<TeamView>>(
      feed: widget.feed,
      select: (s) => s?.teams ?? const <TeamView>[],
      equals: rosterEqual,
      builder: (context, teams) {
        final myId = widget.myTeamId();
        TeamView? mine;
        for (final t in teams) {
          if (t.id == myId) mine = t;
        }
        final solo = mine == null || mine.solo;
        // A solo player's team is that person; nobody can sit with them.
        final others = [
          for (final t in teams)
            if (!t.solo && t.id != myId) t,
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: JColors.surface,
                borderRadius: BorderRadius.circular(JRadius.card),
                border: Border.all(color: JColors.brass),
              ),
              child: Row(
                children: [
                  Icon(
                    solo ? Icons.person_outline : Icons.groups_outlined,
                    size: 18,
                    color: JColors.brass,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          L.yourTeam,
                          style: const TextStyle(
                            color: JColors.textFaint,
                            fontSize: 10,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          solo ? L.noTeam : mine.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!solo)
                    TextButton(
                      onPressed: _busy ? null : () => _change(),
                      child: const Text(L.leaveTeam),
                    ),
                ],
              ),
            ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                solo ? L.chooseTeam : L.otherTeams,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final t in others)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _OtherTeamTile(
                    team: t,
                    onTap: _busy ? null : () => _change(teamId: t.id),
                  ),
                ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _newTeam,
              textInputAction: TextInputAction.go,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: L.newTeamName,
                counterText: '',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _newTeam.text.trim().isEmpty
                  ? null
                  : _change(newTeamName: _newTeam.text.trim()),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: (_busy || _newTeam.text.trim().isEmpty)
                  ? null
                  : () => _change(newTeamName: _newTeam.text.trim()),
              icon: const Icon(Icons.group_add_outlined, size: 20),
              label: const Text(L.createTeam),
            ),
          ],
        );
      },
    );
  }
}

class _OtherTeamTile extends StatelessWidget {
  const _OtherTeamTile({required this.team, this.onTap});

  final TeamView team;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: JColors.surface,
      borderRadius: BorderRadius.circular(JRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(JRadius.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(JRadius.card),
            border: Border.all(color: JColors.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (team.players.isNotEmpty)
                      Text(
                        team.players.map((p) => p.name).join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: JColors.textFaint,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                L.joinThisTeam,
                style: TextStyle(
                  color: JColors.goldBright,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Icon(Icons.chevron_right, color: JColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
