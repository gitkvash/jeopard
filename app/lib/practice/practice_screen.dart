import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../core/rest_client.dart';
import '../core/sfx.dart';
import '../core/theme.dart';
import '../widgets/clue_panel.dart';
import '../widgets/game_chrome.dart';
import '../widgets/stage.dart';

/// Practice: one random question after another, for one person on their own.
///
/// No game behind it -- no package, no board, no score anyone else sees. A
/// card shows a question; the player thinks, looks at the answer, and says
/// whether they knew it, and the next card comes up. The tally is this
/// screen's alone and goes when it closes.
///
/// On a keyboard: space or enter shows the answer, then 1 is "knew it" and 2
/// is "did not".
class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({super.key});

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  /// Fetched again when this few cards are left, so the next one is always in
  /// hand by the time it is wanted.
  static const _refillAt = 5;

  final _queue = <PracticeQuestion>[];

  /// Everything dealt so far, so a later batch cannot deal a card again.
  final _seen = <int>{};

  PracticeQuestion? _current;
  bool _revealed = false;
  int _knew = 0;
  int _didNotKnow = 0;

  bool _loading = false;
  bool _failed = false;
  String? _attribution;

  @override
  void initState() {
    super.initState();
    _fill();
  }

  Future<void> _fill() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final batch = await ref.read(restClientProvider).practiceQuestions();
      if (!mounted) return;
      setState(() {
        _attribution = batch.attribution ?? _attribution;
        for (final q in batch.questions) {
          if (_seen.contains(q.id) || _queue.any((x) => x.id == q.id)) continue;
          _queue.add(q);
        }
      });
    } catch (e) {
      debugPrint('practice questions failed: ${describeError(e)}');
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (mounted && _current == null && _queue.isNotEmpty) _deal();
  }

  void _deal() {
    setState(() {
      _current = _queue.isEmpty ? null : _queue.removeAt(0);
      _revealed = false;
      final dealt = _current;
      if (dealt != null) _seen.add(dealt.id);
    });
    if (_queue.length < _refillAt) _fill();
  }

  void _reveal() {
    if (_current == null || _revealed) return;
    setState(() => _revealed = true);
  }

  void _judge(bool knew) {
    if (_current == null || !_revealed) return;
    Sfx.instance.play(knew ? Cue.correct : Cue.wrong);
    setState(() => knew ? _knew++ : _didNotKnow++);
    _deal();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (!_revealed &&
        (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter)) {
      _reveal();
      return KeyEventResult.handled;
    }
    if (_revealed &&
        (key == LogicalKeyboardKey.digit1 ||
            key == LogicalKeyboardKey.numpad1)) {
      _judge(true);
      return KeyEventResult.handled;
    }
    if (_revealed &&
        (key == LogicalKeyboardKey.digit2 ||
            key == LogicalKeyboardKey.numpad2)) {
      _judge(false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(L.practice),
        actions: [
          _Tally(knew: _knew, didNotKnow: _didNotKnow),
          const SizedBox(width: 4),
          const SoundToggle(),
          IconButton(
            onPressed: () => showAboutJeopard(context, _attribution),
            icon: const Icon(Icons.info_outline, size: 20),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(top: false, bottom: false, child: _body()),
      ),
    );
  }

  Widget _body() {
    final q = _current;
    if (q == null) {
      if (_failed && !_loading) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                L.practiceLoadError,
                style: TextStyle(color: JColors.textMuted),
              ),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: _fill, child: const Text(L.retry)),
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Where the card came from, quietly: generated packages say so in
        // their title, and the original ones deserve their name.
        PhaseHint(
          q.finalRound
              ? '${q.packageTitle ?? ''} · ${L.finalRound}'
              : q.packageTitle ?? '',
        ),
        Expanded(
          child: ClueLayout(
            panel: CluePanel(
              // Keyed by card, so a new question starts at the top of its
              // scroll rather than wherever the last long one was left.
              key: ValueKey(q.id),
              clue: q.toClue(withAnswer: _revealed),
              showAnswer: _revealed,
              banner: CluePanelBanner(
                text: _revealed ? L.practiceDidYouKnow : L.practiceThink,
                color: JColors.goldBright,
                icon: _revealed ? Icons.rule : Icons.lightbulb_outline,
              ),
            ),
            controls: (side) => _revealed
                ? ControlShelf(
                    side: side,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: JColors.correct,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _judge(true),
                        icon: const Icon(Icons.check, size: 20),
                        label: const Text(L.practiceKnew),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: JColors.wrong,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _judge(false),
                        icon: const Icon(Icons.close, size: 20),
                        label: const Text(L.practiceDidNotKnow),
                      ),
                    ],
                  )
                : ControlShelf(
                    side: side,
                    trailing: TextButton.icon(
                      onPressed: _deal,
                      icon: const Icon(Icons.skip_next, size: 18),
                      label: const Text(L.practiceSkip),
                    ),
                    children: [
                      FilledButton.icon(
                        onPressed: _reveal,
                        icon: const Icon(Icons.visibility_outlined, size: 20),
                        label: const Text(L.showAnswer),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// How the session is going: known and not known, nothing more.
class _Tally extends StatelessWidget {
  const _Tally({required this.knew, required this.didNotKnow});

  final int knew;
  final int didNotKnow;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check, size: 16, color: JColors.correct),
        const SizedBox(width: 3),
        Text('$knew', style: style.copyWith(color: JColors.correct)),
        const SizedBox(width: 12),
        const Icon(Icons.close, size: 16, color: JColors.wrongBright),
        const SizedBox(width: 3),
        Text('$didNotKnow', style: style.copyWith(color: JColors.wrongBright)),
      ],
    );
  }
}
