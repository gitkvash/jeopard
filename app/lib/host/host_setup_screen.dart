import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../core/rest_client.dart';
import '../core/session.dart';
import '../core/session_store.dart';
import '../core/theme.dart';
import '../widgets/stage.dart';
import '../widgets/toast.dart';
import 'host_game_screen.dart';

/// Above this width the options sit beside the list; below it they get a page
/// of their own.
///
/// Thirty packages are longer than any screen, so the options used to live
/// under the end of a scroll: choosing a package meant scrolling past twenty
/// more of them to reach the one switch and the one button that follow. Now
/// picking a package is the step, and setting it up is the next step -- either
/// on its own page, or in a panel that is already open beside the list on a
/// screen wide enough to hold both.
const double _twoPaneWidth = 880;

/// The options panel, sized for a switch with a two-line subtitle.
const double _optionsWidth = 400;

/// What the server will accept as reading time for an automatic buzzer. Kept in
/// step with GameService.MIN/MAX_BUZZ_DELAY_SECONDS, so a number it would refuse
/// is refused here first, in Georgian, instead of coming back as an HTTP 400.
const int _minDelay = 1;
const int _maxDelay = 120;

/// A package list a metre wide reads as a spreadsheet, so the cards stay at a
/// comfortable width and the pane pads around them.
const double _listWidth = 720;

/// Step one: pick a package.
///
/// On a wide screen the panel to the right is step two; on a narrow one,
/// tapping a package opens it.
class HostSetupScreen extends ConsumerStatefulWidget {
  const HostSetupScreen({super.key});

  @override
  ConsumerState<HostSetupScreen> createState() => _HostSetupScreenState();
}

class _HostSetupScreenState extends ConsumerState<HostSetupScreen> {
  int? _packageId;

  void _pick(PackageSummary package, {required bool twoPane}) {
    setState(() => _packageId = package.id);
    if (twoPane) return;
    // A pushed route rather than a step inside this screen: the list keeps its
    // scroll position underneath, and the browser's own back button walks back
    // to it like any other page.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HostOptionsScreen(package: package)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(packagesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(L.newGame)),
      body: packages.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorPane(
          message: '$e',
          onRetry: () => ref.invalidate(packagesProvider),
        ),
        data: (list) => _buildBody(list),
      ),
    );
  }

  Widget _buildBody(List<PackageSummary> list) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoPane = constraints.maxWidth >= _twoPaneWidth;
        final selected = list.where((p) => p.id == _packageId).firstOrNull;

        final packageList = _PackageList(
          packages: list,
          selectedId: _packageId,
          // Where the options are already on screen the card is a choice; where
          // tapping it opens a page, it says so with a chevron instead.
          opensPage: !twoPane,
          onPick: (p) => _pick(p, twoPane: twoPane),
        );

        if (!twoPane) return packageList;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: packageList),
            const VerticalDivider(width: 1),
            SizedBox(
              width: _optionsWidth,
              child: selected == null
                  ? const _NoPackageChosen()
                  : _OptionsPane(package: selected),
            ),
          ],
        );
      },
    );
  }
}

/// Step two on a narrow screen: everything about the chosen package, and
/// nothing else.
class HostOptionsScreen extends StatelessWidget {
  const HostOptionsScreen({super.key, required this.package});

  final PackageSummary package;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(L.newGame)),
      body: _OptionsPane(
        package: package,
        onChangePackage: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// The setup itself: round or whole package, whether the host plays, and the
/// button that starts the game.
///
/// One widget for both layouts -- a page of its own on a phone, a panel beside
/// the list on a desktop -- so the two can never drift apart.
class _OptionsPane extends ConsumerStatefulWidget {
  const _OptionsPane({required this.package, this.onChangePackage});

  final PackageSummary package;

  /// Offered only where the list is not on screen: a way back to it that is not
  /// the app bar's arrow.
  final VoidCallback? onChangePackage;

  @override
  ConsumerState<_OptionsPane> createState() => _OptionsPaneState();
}

class _OptionsPaneState extends ConsumerState<_OptionsPane> {
  /// True to play the package end to end (boards 1-3 then the final, scores
  /// carried across) rather than a single round.
  bool _wholePackage = true;
  int? _roundId;
  bool _hostPlays = false;
  bool _creating = false;
  final _hostTeamName = TextEditingController();

  /// Who opens the buzzer, and after how long when that is a timer.
  BuzzMode _buzzMode = BuzzMode.host;
  int _delaySeconds = _delayPresets[1];
  bool _customDelay = false;
  final _customSeconds = TextEditingController(text: '20');

  /// Reading times worth a chip. Five is a one-line clue, fifteen a long one.
  static const List<int> _delayPresets = [5, 10, 15];

  PackageSummary get _package => widget.package;

  /// Null when the host typed something that is not a usable number of seconds,
  /// which is the one thing here that can hold up creating the game.
  int? get _delay {
    if (_buzzMode != BuzzMode.timer) return null;
    if (!_customDelay) return _delaySeconds;
    final typed = int.tryParse(_customSeconds.text.trim());
    if (typed == null || typed < _minDelay || typed > _maxDelay) return null;
    return typed;
  }

  bool get _canCreate =>
      (_wholePackage || _roundId != null) &&
      (_buzzMode != BuzzMode.timer || _delay != null);

  @override
  void didUpdateWidget(covariant _OptionsPane old) {
    super.didUpdateWidget(old);
    // A round id belongs to the package it came from, so switching packages in
    // the list beside this panel invalidates it -- but not the host's own
    // switches, which they should not have to set a second time.
    if (old.package.id != _package.id) _roundId = null;
  }

  @override
  void dispose() {
    _hostTeamName.dispose();
    _customSeconds.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_canCreate) return;
    setState(() => _creating = true);
    try {
      final created = await ref
          .read(restClientProvider)
          .createGame(
            packageId: _wholePackage ? _package.id : null,
            roundId: _wholePackage ? null : _roundId,
            hostPlays: _hostPlays,
            hostTeamName: _hostPlays ? _hostTeamName.text.trim() : null,
            buzzMode: _buzzMode,
            buzzDelaySeconds: _delay,
          );
      if (!mounted) return;
      // Remembered before the screen even opens, so a reload during the lobby
      // -- when the host is reading the code out loud -- is survivable.
      final session = GameSession.fromCreated(created);
      SessionStore.write(session);
      // Both setup steps go away, leaving the game on top of the role picker:
      // nothing behind the board should lead back into choosing a package.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => HostGameScreen(session: session)),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      showToast(context, describeError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // What is being set up, restated where the setting up happens:
              // on a phone the list is a page away, and on a desktop it is a
              // long scroll that may have moved on.
              _PackageCard(package: _package, selected: true),
              if (widget.onChangePackage != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onChangePackage,
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text(L.changePackage),
                  ),
                ),
              const SizedBox(height: 12),
              const _SectionLabel(L.gameOptions),
              Card(
                child: SwitchListTile(
                  value: _wholePackage,
                  onChanged: (v) => setState(() {
                    _wholePackage = v;
                    // Turning it off with no round chosen would disable the
                    // button for a reason nothing on screen explains, so the
                    // first board stands in until another chip is tapped.
                    if (!v) {
                      _roundId ??= _package.rounds
                          .where((r) => r.playable)
                          .firstOrNull
                          ?.id;
                    }
                  }),
                  title: const Text(L.wholePackage),
                  subtitle: const Text(L.wholePackageHint),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                ),
              ),
              if (!_wholePackage) ...[
                const SizedBox(height: 16),
                const _SectionLabel(L.roundLabel),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in _package.rounds)
                      _Chip(
                        label: r.finalRound
                            ? L.finalRound
                            : '${L.roundLabel} ${r.idx}',
                        selected: _roundId == r.id,
                        onTap: () => setState(() => _roundId = r.id),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const _SectionLabel(L.buzzModeLabel),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final choice in const [
                    (BuzzMode.host, L.buzzModeHost),
                    (BuzzMode.instant, L.buzzModeInstant),
                    (BuzzMode.timer, L.buzzModeTimer),
                  ])
                    _Chip(
                      label: choice.$2,
                      selected: _buzzMode == choice.$1,
                      onTap: () => setState(() => _buzzMode = choice.$1),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // One line, about the choice that is actually made: three hints
              // stacked under three radio rows cost more height than every
              // other option on this page put together.
              Text(
                switch (_buzzMode) {
                  BuzzMode.host => L.buzzModeHostHint,
                  BuzzMode.instant => L.buzzModeInstantHint,
                  BuzzMode.timer => L.buzzModeTimerHint,
                },
                style: const TextStyle(
                  color: JColors.textFaint,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              if (_buzzMode == BuzzMode.timer) ...[
                const SizedBox(height: 16),
                const _SectionLabel(L.buzzDelayLabel),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _delayPresets)
                      _Chip(
                        label: '$s ${L.seconds}',
                        selected: !_customDelay && _delaySeconds == s,
                        onTap: () => setState(() {
                          _customDelay = false;
                          _delaySeconds = s;
                        }),
                      ),
                    _Chip(
                      label: L.customDelay,
                      selected: _customDelay,
                      onTap: () => setState(() => _customDelay = true),
                    ),
                  ],
                ),
                if (_customDelay) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customSeconds,
                    keyboardType: TextInputType.number,
                    // The create button turns on the moment the number is
                    // usable, so the field has to report every keystroke.
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: L.customDelayField,
                      suffixText: L.seconds,
                      errorText: _delay == null ? L.buzzDelayRange : null,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _hostPlays,
                      onChanged: (v) => setState(() => _hostPlays = v),
                      title: const Text(L.hostPlaysToo),
                      subtitle: const Text(L.peekWarning),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                    ),
                    if (_hostPlays)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: TextField(
                          controller: _hostTeamName,
                          decoration: const InputDecoration(
                            labelText: L.hostTeamName,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Pinned: the one button that matters should never be at the bottom of
        // a scroll.
        Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: JColors.line)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (!_canCreate || _creating) ? null : _create,
                  icon: _creating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: JColors.textFaint,
                          ),
                        )
                      : const Icon(Icons.play_arrow, size: 20),
                  label: const Text(L.create),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The packages, in two sections.
class _PackageList extends StatelessWidget {
  const _PackageList({
    required this.packages,
    required this.selectedId,
    required this.opensPage,
    required this.onPick,
  });

  final List<PackageSummary> packages;
  final int? selectedId;
  final bool opensPage;
  final ValueChanged<PackageSummary> onPick;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = (constraints.maxWidth - _listWidth) / 2;
        final gutter = side > 16 ? side : 16.0;

        return ListView(
          padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 24),
          children: [
            // Two provenances, two sections. With thirty packages a flat list is
            // a long scroll in which the six authentic games are lost among the
            // generated ones, and which of the two a host is picking is the thing
            // they most need to know.
            for (final group in [
              (
                label: L.originalPackages,
                items: packages.where((p) => !p.generated),
              ),
              (
                label: L.generatedPackages,
                items: packages.where((p) => p.generated),
              ),
            ])
              if (group.items.isNotEmpty) ...[
                _SectionLabel('${group.label}  ·  ${group.items.length}'),
                for (final p in group.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PackageCard(
                      package: p,
                      selected: p.id == selectedId,
                      onTap: () => onPick(p),
                      trailing: Icon(
                        p.id == selectedId
                            ? Icons.check_circle
                            : (opensPage
                                  ? Icons.chevron_right
                                  : Icons.circle_outlined),
                        color: p.id == selectedId
                            ? JColors.goldBright
                            : (opensPage ? JColors.brass : JColors.line),
                        size: 21,
                      ),
                    ),
                  ),
              ],
          ],
        );
      },
    );
  }
}

/// The right-hand pane before anything has been picked.
class _NoPackageChosen extends StatelessWidget {
  const _NoPackageChosen();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.grid_view_rounded, size: 40, color: JColors.brass),
            const SizedBox(height: 18),
            const Text(
              L.choosePackage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: JColors.textMuted,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              L.choosePackageHint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: JColors.textFaint,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one chip in the app: a round to play, or a number of seconds to wait.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      labelStyle: TextStyle(
        color: selected ? JColors.backdrop : JColors.textMuted,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) => onTap(),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  /// Room kept for the rule when the label wants the whole line: the gap plus
  /// enough brass to still read as a rule rather than a stray pixel.
  static const double _ruleRoom = 40;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            // "ორიგინალური პაკეტები (2008) · 6" is wider than a phone at this
            // letter spacing, and a Row with an unbounded label in it overflows
            // rather than shortening -- which on a 420pt screen is the striped
            // banner instead of a heading.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (constraints.maxWidth - _ruleRoom).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: Text(
                text.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: kTicker,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [JColors.brass, Color(0x008A6A2A)],
                  ),
                ),
                child: SizedBox(height: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.package,
    required this.selected,
    this.onTap,
    this.trailing,
  });

  final PackageSummary package;
  final bool selected;

  /// Absent where the card is a heading rather than a choice.
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final boards = package.rounds.where((r) => r.playable).length;
    final hasFinal = package.rounds.any((r) => r.finalRound);
    final rounds = hasFinal
        ? '$boards ${L.roundLabel}  ·  ${L.finalRound}'
        : '$boards ${L.roundLabel}';

    return Plate(
      lit: selected,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        children: [
          // The package number set as a board tile: this is a game, not a list.
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: selected
                    ? const [
                        Color(0xFFFFF0C4),
                        JColors.goldBright,
                        Color(0xFFC99A2E),
                      ]
                    : const [
                        Color(0xFF3A56F5),
                        JColors.boardLit,
                        JColors.boardDeep,
                      ],
                stops: const [0, 0.12, 1],
              ),
              borderRadius: BorderRadius.circular(JRadius.tile),
            ),
            child: Text(
              '${package.number}',
              style: engraved(
                21,
                color: selected ? const Color(0xFF14120A) : JColors.gold,
                glow: false,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  package.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: selected ? JColors.goldBright : JColors.text,
                  ),
                ),
                if (package.subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    package.subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: JColors.textFaint,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  rounds,
                  style: kTicker.copyWith(
                    color: selected ? JColors.gold : JColors.textFaint,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 44, color: JColors.textFaint),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: JColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text(L.retry),
            ),
          ],
        ),
      ),
    );
  }
}
