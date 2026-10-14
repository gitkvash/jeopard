import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/responsive.dart';
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

    // Sideways on a phone the strip competes with the clue for 360 pixels, so it
    // gives up its second line; upright on a small one it only trims.
    final density = context.isShort
        ? _Density.tight
        : context.isCompactHeight
        ? _Density.compact
        : _Density.regular;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: density == _Density.tight ? 6 : 10,
      ),
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
                density: density,
              ),
            ),
        ],
      ),
    );
  }
}

enum _Density { regular, compact, tight }

class _TeamPlate extends StatelessWidget {
  const _TeamPlate({
    required this.team,
    required this.buzzed,
    required this.isMe,
    required this.leading,
    required this.density,
  });

  final _Density density;

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
      constraints: BoxConstraints(
        minWidth: density == _Density.tight ? 0 : 116,
      ),
      padding: switch (density) {
        _Density.regular => const EdgeInsets.fromLTRB(13, 8, 13, 9),
        _Density.compact => const EdgeInsets.fromLTRB(11, 6, 11, 6),
        _Density.tight => const EdgeInsets.fromLTRB(10, 5, 10, 5),
      },
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
      child: Opacity(opacity: dim ? 0.42 : 1, child: _content(negative)),
    );
  }

  Widget _content(bool negative) {
    final name = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (team.host || team.solo)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(
              team.host ? Icons.co_present_outlined : Icons.person_outline,
              size: 12,
              color: buzzed ? const Color(0xFF3A2A00) : JColors.textFaint,
            ),
          ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: density == _Density.tight ? 96 : 132,
          ),
          child: Text(
            team.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: buzzed ? const Color(0xFF2A1D00) : JColors.textMuted,
              decoration: team.lockedOut ? TextDecoration.lineThrough : null,
              decorationColor: buzzed
                  ? const Color(0xFF2A1D00)
                  : JColors.textMuted,
            ),
          ),
        ),
      ],
    );

    final score = Text(
      '${team.score}',
      style: engraved(
        switch (density) {
          _Density.regular => 29,
          _Density.compact => 24,
          _Density.tight => 20,
        },
        color: buzzed
            ? const Color(0xFF14120A)
            : negative
            ? JColors.wrongBright
            : JColors.gold,
        glow: false,
      ),
    );

    // One line: the name and the number side by side, which is all a score strip
    // has to say when it is sharing a 360-pixel-tall screen with a clue.
    if (density == _Density.tight) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [name, const SizedBox(width: 10), score],
      );
    }

    final detail = TextStyle(
      fontSize: 10,
      color: buzzed ? const Color(0xFF4A3705) : JColors.textFaint,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        name,
        const SizedBox(height: 2),
        score,
        // Only worth saying when the team is more than one person.
        if (team.players.length > 1)
          Text('${team.players.length} ${L.members}', style: detail),
        if (team.wager != null)
          Text('${L.wager}: ${team.wager}', style: detail),
      ],
    );
  }
}
