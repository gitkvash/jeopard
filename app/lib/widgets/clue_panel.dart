import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/theme.dart';

/// The clue in play, given the whole screen.
///
/// On television a clue is not a card in a column -- it fills the frame, the
/// category and value sit in a bar above it, and the text is large enough to
/// read from the back of the room. That is what this is: a lit blue field, a
/// bar, and a question centred in it. Questions run to ~800 characters in this
/// data set, so the text scrolls rather than assuming a one-liner.
class CluePanel extends StatelessWidget {
  const CluePanel({
    super.key,
    required this.clue,
    this.showAnswer = false,
    this.banner,
  });

  final CurrentClue clue;

  /// Only ever true when the server actually sent an answer.
  final bool showAnswer;

  /// Optional status strip under the bar ("read aloud", "team X buzzed").
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    final answer = clue.answer;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF2A44F0),
            Color(0xFF0C1DBE),
            Color(0xFF081394),
            Color(0xFF050C60),
          ],
          stops: [0, 0.03, 0.62, 1],
        ),
        borderRadius: BorderRadius.circular(JRadius.panel),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.9),
            blurRadius: 60,
            offset: const Offset(0, 22),
            spreadRadius: -20,
          ),
          BoxShadow(
            color: JColors.board.withValues(alpha: 0.30),
            blurRadius: 50,
            spreadRadius: -18,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category and value: on a team device this is the only way to know
          // what the host just picked, and the host reads it out from here.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 13, 18, 13),
            decoration: const BoxDecoration(
              color: Color(0x57000000),
              border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    clue.topicName.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      height: 1.25,
                    ),
                  ),
                ),
                if (clue.value != null) ...[
                  const SizedBox(width: 14),
                  Text(
                    '${clue.value} ${L.points}',
                    style: engraved(21, glow: false),
                  ),
                ],
              ],
            ),
          ),
          if (banner != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: banner!,
            ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 30, 26, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    clue.question ?? '...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      height: 1.5,
                      shadows: [
                        Shadow(
                          color: Color(0x80000000),
                          offset: Offset(0, 2),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  if (showAnswer && answer != null) ...[
                    const SizedBox(height: 26),
                    _AnswerBlock(
                      answer: answer,
                      correctionNote: clue.correctionNote,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerBlock extends StatelessWidget {
  const _AnswerBlock({required this.answer, this.correctionNote});

  final String answer;
  final String? correctionNote;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0x59000000),
        borderRadius: BorderRadius.circular(JRadius.card),
        border: const Border(left: BorderSide(color: JColors.gold, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L.answer.toUpperCase(),
            style: kTicker.copyWith(color: const Color(0xFF9FB0D8)),
          ),
          const SizedBox(height: 8),
          Text(
            answer,
            style: const TextStyle(
              color: JColors.goldBright,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.3,
              shadows: [
                Shadow(
                  color: Color(0x99000000),
                  offset: Offset(0, 2),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          if (correctionNote != null) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Color(0xFF8595BF),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    correctionNote!,
                    style: const TextStyle(
                      color: Color(0xFF8595BF),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Status strip under the clue bar: read it aloud, the buzzer is open, someone
/// buzzed. Tinted glass over the blue field rather than a flat block.
class CluePanelBanner extends StatelessWidget {
  const CluePanelBanner({
    super.key,
    required this.text,
    required this.color,
    this.icon,
  });

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0x4D000000),
        borderRadius: BorderRadius.circular(JRadius.control),
        border: Border(left: BorderSide(color: color, width: 3)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.22),
            blurRadius: 22,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
