import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/theme.dart';

/// Running scores, as plates along the front of the stage.
///
/// The team that just buzzed lights up gold; the leader keeps a brass frame; a
/// team locked out of the current clue dims and strikes through. Scores are set
/// in the same condensed face as the board values, which is what ties the strip
/// to the grid above it.
class Scoreboard extends StatelessWidget {
  const Scoreboard({
    super.key,
    required this.teams,
    this.buzzedTeamId,
    this.myTeamId,
  });

  final List<TeamView> teams;
  final String? buzzedTeamId;
  final String? myTeamId;

  @override
  Widget build(BuildContext context) {
    if (teams.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          L.noTeamsYet,
          style: TextStyle(color: JColors.textFaint, fontSize: 13),
        ),
      );
    }

    final top = teams
        .map((t) => t.score)
        .fold<int>(-1 << 40, (a, b) => a > b ? a : b);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          for (final team in teams)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _TeamPlate(
                team: team,
                buzzed: team.id == buzzedTeamId,
                isMe: team.id == myTeamId,
                leading: team.score == top && team.score > 0,
              ),
            ),
        ],
      ),
    );
  }
}

class _TeamPlate extends StatelessWidget {
  const _TeamPlate({
    required this.team,
    required this.buzzed,
    required this.isMe,
    required this.leading,
  });

  final TeamView team;
  final bool buzzed;
  final bool isMe;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    final negative = team.score < 0;
    final dim = team.lockedOut && !buzzed;
    final frame = buzzed
        ? JColors.goldBright
        : isMe
        ? JColors.gold
        : leading
        ? JColors.brass
        : JColors.line;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      constraints: const BoxConstraints(minWidth: 116),
      padding: const EdgeInsets.fromLTRB(13, 8, 13, 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: buzzed
              ? const [Color(0xFFFFF0C4), JColors.goldBright, Color(0xFFC99A2E)]
              : const [Color(0xFF232B47), JColors.surfaceHigh, JColors.surface],
          stops: const [0, 0.12, 1],
        ),
        borderRadius: BorderRadius.circular(JRadius.card),
        border: Border.all(color: frame, width: buzzed || isMe ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
          if (buzzed)
            BoxShadow(
              color: JColors.gold.withValues(alpha: 0.45),
              blurRadius: 28,
              spreadRadius: -6,
            ),
        ],
      ),
      child: Opacity(
        opacity: dim ? 0.42 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (team.host)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.co_present_outlined,
                      size: 12,
                      color: buzzed
                          ? const Color(0xFF3A2A00)
                          : JColors.textFaint,
                    ),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 132),
                  child: Text(
                    team.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      color: buzzed
                          ? const Color(0xFF2A1D00)
                          : JColors.textMuted,
                      decoration: team.lockedOut
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: buzzed
                          ? const Color(0xFF2A1D00)
                          : JColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${team.score}',
              style: engraved(
                29,
                color: buzzed
                    ? const Color(0xFF14120A)
                    : negative
                    ? JColors.wrongBright
                    : JColors.gold,
                glow: false,
              ),
            ),
            // Only worth saying when the team is more than one person.
            if (team.players.length > 1)
              Text(
                '${team.players.length} ${L.members}',
                style: TextStyle(
                  fontSize: 10,
                  color: buzzed ? const Color(0xFF4A3705) : JColors.textFaint,
                ),
              ),
            if (team.wager != null)
              Text(
                '${L.wager}: ${team.wager}',
                style: TextStyle(
                  fontSize: 10,
                  color: buzzed ? const Color(0xFF4A3705) : JColors.textFaint,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
