import 'dart:async';

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
import '../widgets/topic_suggestion_dialog.dart';
import 'host_game_screen.dart';
import 'package_builder_screen.dart';
import 'topic_picker_dialog.dart';
import 'package_search.dart';

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

  /// The generated packet, once created -- not part of [packagesProvider]'s
  /// fetched list, so it is tracked separately.
  PackageSummary? _extraPackage;
  bool _generatingRandom = false;

  @override
  void initState() {
    super.initState();
    // The list is fetched at app start rather than here (see main.dart), which
    // is what makes this screen usually open on packages instead of a spinner.
    // The cost of that is a failed prefetch outliving its cause -- a backend
    // still booting, a phone not yet on the Wi-Fi -- so a stale failure is
    // thrown away and tried again rather than shown to a host who has only
    // just arrived.
    if (ref.read(packagesProvider).hasError) ref.invalidate(packagesProvider);
  }

  void _pick(PackageSummary package, {required bool twoPane}) {
    setState(() => _packageId = package.id);
    if (twoPane) return;
    // A pushed route rather than a step inside this screen: the list keeps its
    // scroll position underneath, and the browser's own back button walks back
    // to it like any other page.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HostOptionsScreen(
          package: package,
          onPackageChanged: (updated) {
            setState(() {
              if (_extraPackage?.id == updated.id) {
                _extraPackage = updated;
              }
            });
          },
        ),
      ),
    );
  }

  Future<void> _pickRandom({required bool twoPane}) async {
    setState(() => _generatingRandom = true);
    try {
      final generated = await ref.read(restClientProvider).randomPackage();
      if (!mounted) return;
      setState(() {
        _extraPackage = generated;
        _generatingRandom = false;
      });
      _pick(generated, twoPane: twoPane);
    } catch (e) {
      if (!mounted) return;
      setState(() => _generatingRandom = false);
      showToast(context, L.randomPackageError, error: true);
    }
  }

  Future<void> _openBuilder({required bool twoPane}) async {
    final created = await Navigator.of(context).push<PackageSummary>(
      MaterialPageRoute(builder: (_) => const PackageBuilderScreen()),
    );
    if (!mounted || created == null) return;
    setState(() {
      _extraPackage = created;
      _packageId = created.id;
    });
    _pick(created, twoPane: twoPane);
  }

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(packagesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(L.newGame),
        actions: [
          IconButton(
            tooltip: L.suggestTopic,
            icon: const Icon(Icons.lightbulb_outline),
            onPressed: () => showTopicSuggestionDialog(context),
          ),
        ],
      ),
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
        final selected = _extraPackage?.id == _packageId
            ? _extraPackage
            : list.where((p) => p.id == _packageId).firstOrNull;

        final packageList = _PackageList(
          packages: list,
          selectedId: _packageId,
          // Where the options are already on screen the card is a choice; where
          // tapping it opens a page, it says so with a chevron instead.
          opensPage: !twoPane,
          onPick: (p) => _pick(p, twoPane: twoPane),
          onPickRandom: () => _pickRandom(twoPane: twoPane),
          onOpenBuilder: () => _openBuilder(twoPane: twoPane),
          generatingRandom: _generatingRandom,
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
                  : _OptionsPane(
                      package: selected,
                      onPackageChanged: (updated) {
                        setState(() {
                          if (_extraPackage?.id == updated.id) {
                            _extraPackage = updated;
                          }
                        });
                      },
                    ),
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
  const HostOptionsScreen({
    super.key,
    required this.package,
    this.onPackageChanged,
  });

  final PackageSummary package;
  final ValueChanged<PackageSummary>? onPackageChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(L.newGame)),
      body: _OptionsPane(
        package: package,
        onChangePackage: () => Navigator.of(context).pop(),
        onPackageChanged: onPackageChanged,
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
  const _OptionsPane({
    required this.package,
    this.onChangePackage,
    this.onPackageChanged,
  });

  final PackageSummary package;

  /// Offered only where the list is not on screen: a way back to it that is not
  /// the app bar's arrow.
  final VoidCallback? onChangePackage;
  final ValueChanged<PackageSummary>? onPackageChanged;

  @override
  ConsumerState<_OptionsPane> createState() => _OptionsPaneState();
}

class _OptionsPaneState extends ConsumerState<_OptionsPane> {
  late PackageSummary _package;
  /// True to play the package end to end (boards 1-3 then the final, scores
  /// carried across) rather than a single round.
  bool _wholePackage = true;
  int? _roundId;
  int _previewRoundIdx = 1;
  int? _rerollingTopicId;
  bool _hostPlays = false;
  bool _creating = false;
  final _hostTeamName = TextEditingController();

  /// Off makes a team listen rather than read: the host still gets the clue
  /// text regardless, just not on a participant's own device. Off unless the
  /// host asks otherwise -- most rooms play by ear.
  bool _questionsVisibleToParticipants = false;

  /// On hands the choice of tile to the players, a team (or a solo player) at a
  /// time. The host can still choose at any moment.
  bool _playersPickClues = false;

  /// Who opens the buzzer, and after how long when that is a timer.
  BuzzMode _buzzMode = BuzzMode.instant;
  int _delaySeconds = _delayPresets[1];
  bool _customDelay = false;
  final _customSeconds = TextEditingController(text: '20');

  /// Reading times worth a chip. Five is a one-line clue, fifteen a long one.
  static const List<int> _delayPresets = [5, 10, 15];

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
  void initState() {
    super.initState();
    _package = widget.package;
    _previewRoundIdx =
        _package.rounds.isNotEmpty ? _package.rounds.first.idx : 1;
  }

  @override
  void didUpdateWidget(covariant _OptionsPane old) {
    super.didUpdateWidget(old);
    // A round id belongs to the package it came from, so switching packages in
    // the list beside this panel invalidates it -- but not the host's own
    // switches, which they should not have to set a second time.
    if (old.package.id != widget.package.id) {
      _package = widget.package;
      _roundId = null;
      _previewRoundIdx =
          _package.rounds.isNotEmpty ? _package.rounds.first.idx : 1;
    } else if (old.package != widget.package) {
      _package = widget.package;
    }
  }

  Future<void> _rerollTopic(TopicSummary topic) async {
    if (_rerollingTopicId != null) return;
    setState(() => _rerollingTopicId = topic.id);
    try {
      final updated = await ref
          .read(restClientProvider)
          .rerollTopic(_package.id, topic.id);
      if (!mounted) return;
      final newRounds = _package.rounds.map((r) {
        return r.copyWith(
          topics: r.topics
              .map((t) => t.id == topic.id ? updated : t)
              .toList(),
        );
      }).toList();
      final newPackage = _package.copyWith(rounds: newRounds);
      setState(() {
        _package = newPackage;
        _rerollingTopicId = null;
      });
      widget.onPackageChanged?.call(newPackage);
      showToast(context, '${L.categoryReplaced}: ${updated.name}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _rerollingTopicId = null);
      showToast(context, L.rerollError, error: true);
    }
  }

  Future<void> _replaceTopic(TopicSummary topic) async {
    if (_rerollingTopicId != null) return;
    final round = _package.rounds.firstWhere(
      (r) => r.topics.any((t) => t.id == topic.id),
      orElse: () => _package.rounds.first,
    );
    final picked = await showTopicPickerDialog(
      context,
      ref: ref,
      roundIdx: round.idx,
      currentTopicName: topic.name,
    );
    if (picked == null || !mounted) return;

    setState(() => _rerollingTopicId = topic.id);
    try {
      final updated = await ref
          .read(restClientProvider)
          .replaceTopic(_package.id, topic.id, picked.id);
      if (!mounted) return;
      final newRounds = _package.rounds.map((r) {
        return r.copyWith(
          topics: r.topics
              .map((t) => t.id == topic.id ? updated : t)
              .toList(),
        );
      }).toList();
      final newPackage = _package.copyWith(rounds: newRounds);
      setState(() {
        _package = newPackage;
        _rerollingTopicId = null;
      });
      widget.onPackageChanged?.call(newPackage);
      showToast(context, '${L.topicReplaced}: ${updated.name}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _rerollingTopicId = null);
      showToast(context, 'თემის ჩანაცვლება ვერ მოხერხდა', error: true);
    }
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
      final prev = SessionStore.read();
      if (prev != null) {
        if (prev.isHost && prev.hostToken != null) {
          unawaited(ref
              .read(restClientProvider)
              .deleteGame(prev.gameId, prev.hostToken!)
              .catchError((_) {}));
        } else if (!prev.isHost && prev.playerToken != null) {
          unawaited(ref
              .read(restClientProvider)
              .leavePlayer(prev.gameId, prev.playerToken!)
              .catchError((_) {}));
        }
        SessionStore.clear();
      }

      final created = await ref
          .read(restClientProvider)
          .createGame(
            packageId: _wholePackage ? _package.id : null,
            roundId: _wholePackage ? null : _roundId,
            hostPlays: _hostPlays,
            hostTeamName: _hostPlays ? _hostTeamName.text.trim() : null,
            buzzMode: _buzzMode,
            buzzDelaySeconds: _delay,
            questionsVisibleToParticipants: _questionsVisibleToParticipants,
            playersPickClues: _playersPickClues,
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
                      if (_roundId != null) {
                        _previewRoundIdx = _package.rounds
                            .firstWhere((r) => r.id == _roundId,
                                orElse: () => _package.rounds.first)
                            .idx;
                      }
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
                        onTap: () => setState(() {
                          _roundId = r.id;
                          _previewRoundIdx = r.idx;
                        }),
                      ),
                  ],
                ),
              ],
              if (_package.isRandom) ...[
                _CategoriesSection(
                  package: _package,
                  selectedRoundIdx: _wholePackage
                      ? _previewRoundIdx
                      : (_package.rounds
                              .where((r) => r.id == _roundId)
                              .firstOrNull
                              ?.idx ??
                          _previewRoundIdx),
                  showRoundTabs: _wholePackage,
                  onSelectRoundIdx: (idx) =>
                      setState(() => _previewRoundIdx = idx),
                  onReroll: _rerollTopic,
                  onReplace: _replaceTopic,
                  rerollingTopicId: _rerollingTopicId,
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
                child: SwitchListTile(
                  value: _questionsVisibleToParticipants,
                  onChanged: (v) =>
                      setState(() => _questionsVisibleToParticipants = v),
                  title: const Text(L.participantsSeeQuestions),
                  subtitle: const Text(L.participantsSeeQuestionsHint),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: SwitchListTile(
                  value: _playersPickClues,
                  onChanged: (v) => setState(() => _playersPickClues = v),
                  title: const Text(L.playersPickClues),
                  subtitle: const Text(L.playersPickCluesHint),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                ),
              ),
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

/// The packages, with smart search, provenance filters, and sections.
class _PackageList extends StatefulWidget {
  const _PackageList({
    required this.packages,
    required this.selectedId,
    required this.opensPage,
    required this.onPick,
    required this.onPickRandom,
    required this.onOpenBuilder,
    required this.generatingRandom,
  });

  final List<PackageSummary> packages;
  final int? selectedId;
  final bool opensPage;
  final ValueChanged<PackageSummary> onPick;
  final VoidCallback onPickRandom;
  final VoidCallback onOpenBuilder;
  final bool generatingRandom;

  @override
  State<_PackageList> createState() => _PackageListState();
}

class _PackageListState extends State<_PackageList> {
  final TextEditingController _searchController = TextEditingController();
  PackageSourceFilter _filter = PackageSourceFilter.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final text = _searchController.text;
    if (text != _query) {
      setState(() => _query = text);
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _query = '';
      _filter = PackageSourceFilter.all;
    });
  }

  List<_Row> _rows() {
    final trimmedQuery = _query.trim();
    final isFiltering = _filter != PackageSourceFilter.all;
    final isSearching = trimmedQuery.isNotEmpty || isFiltering;

    if (!isSearching) {
      // Default categorized catalogue view
      final original = <_Row>[];
      final generated = <_Row>[];
      final argon = <_Row>[];
      final ai = <_Row>[];
      for (final p in widget.packages) {
        if (p.isAi) {
          ai.add(_PackageRow(p));
        } else if (p.isArgon) {
          argon.add(_PackageRow(p));
        } else if (p.isGemini || p.generated) {
          generated.add(_PackageRow(p));
        } else {
          original.add(_PackageRow(p));
        }
      }

      return [
        const _QuickActionsRow(),
        for (final group in [
          (label: L.originalPackages, rows: original),
          (label: L.generatedPackages, rows: generated),
          (label: L.argonPackages, rows: argon),
          (label: L.aiPackages, rows: ai),
        ])
          if (group.rows.isNotEmpty) ...[
            _HeaderRow('${group.label}  ·  ${group.rows.length}'),
            ...group.rows,
          ],
      ];
    }

    final searchResults = PackageSearch.search(
      widget.packages,
      trimmedQuery,
      filter: _filter,
    );

    final rows = <_Row>[];

    // Include random package card if matching keyword or empty query with filter
    final qLower = trimmedQuery.toLowerCase();
    final matchesBuilder = qLower.contains('აწყობ') || qLower.contains('კონსტრუქტ') || qLower.contains('შექმნ') || qLower.contains('build') || qLower.contains('custom');
    if (trimmedQuery.isNotEmpty && (PackageSearch.matchesRandom(trimmedQuery) || matchesBuilder)) {
      rows.add(const _QuickActionsRow());
    }

    if (searchResults.isEmpty && rows.isEmpty) {
      return const [_EmptyRow()];
    }

    if (searchResults.isNotEmpty) {
      final headerTitle = trimmedQuery.isNotEmpty
          ? '${L.searchResults.toUpperCase()}  ·  ${searchResults.length}'
          : switch (_filter) {
              PackageSourceFilter.original =>
                '${L.originalPackages.toUpperCase()}  ·  ${searchResults.length}',
              PackageSourceFilter.gemini =>
                '${L.generatedPackages.toUpperCase()}  ·  ${searchResults.length}',
              PackageSourceFilter.argon =>
                '${L.argonPackages.toUpperCase()}  ·  ${searchResults.length}',
              PackageSourceFilter.ai =>
                '${L.aiPackages.toUpperCase()}  ·  ${searchResults.length}',
              PackageSourceFilter.all =>
                '${L.packageLabel.toUpperCase()}  ·  ${searchResults.length}',
            };

      rows.add(_HeaderRow(headerTitle));
      for (final res in searchResults) {
        rows.add(
          _PackageRow(
            res.package,
            titleHighlights: res.titleHighlights,
            subtitleHighlights: res.subtitleHighlights,
          ),
        );
      }
    }

    return rows;
  }

  Widget _buildSearchHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          style: const TextStyle(
            color: JColors.text,
            fontSize: 14,
          ),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: L.searchPackages,
            hintStyle: const TextStyle(color: JColors.textFaint, fontSize: 14),
            prefixIcon: const Icon(Icons.search, color: JColors.brass, size: 20),
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: JColors.textMuted, size: 18),
                    tooltip: L.clearSearch,
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: JColors.surfaceHigh,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(JRadius.control),
              borderSide: const BorderSide(color: JColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(JRadius.control),
              borderSide: const BorderSide(color: JColors.brass, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Chip(
              label: L.filterAll,
              selected: _filter == PackageSourceFilter.all,
              onTap: () => setState(() => _filter = PackageSourceFilter.all),
            ),
            _Chip(
              label: L.filterOriginal,
              selected: _filter == PackageSourceFilter.original,
              onTap: () => setState(() => _filter = PackageSourceFilter.original),
            ),
            _Chip(
              label: L.filterGemini,
              selected: _filter == PackageSourceFilter.gemini,
              onTap: () => setState(() => _filter = PackageSourceFilter.gemini),
            ),
            _Chip(
              label: L.filterArgon,
              selected: _filter == PackageSourceFilter.argon,
              onTap: () => setState(() => _filter = PackageSourceFilter.argon),
            ),
            _Chip(
              label: L.filterAi,
              selected: _filter == PackageSourceFilter.ai,
              onTap: () => setState(() => _filter = PackageSourceFilter.ai),
            ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = (constraints.maxWidth - _listWidth) / 2;
        final gutter = side > 16 ? side : 16.0;

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 4),
              child: _buildSearchHeader(context),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 24),
                itemCount: rows.length,
                itemBuilder: (context, i) => switch (rows[i]) {
                  _HeaderRow(label: final label) => _SectionLabel(label),
                  _EmptyRow() => Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 36,
                        horizontal: 16,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.search_off,
                              size: 40,
                              color: JColors.brass,
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              L.noPackagesFound,
                              style: TextStyle(
                                color: JColors.textMuted,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              L.noPackagesFoundHint,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: JColors.textFaint,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _clearSearch,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text(L.clearSearch),
                            ),
                          ],
                        ),
                      ),
                    ),
                  _QuickActionsRow() => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _QuickActionsCard(
                        generatingRandom: widget.generatingRandom,
                        onPickRandom: widget.onPickRandom,
                        onOpenBuilder: widget.onOpenBuilder,
                      ),
                    ),
                  _PackageRow(
                    package: final p,
                    titleHighlights: final th,
                    subtitleHighlights: final sh,
                  ) =>
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PackageCard(
                        package: p,
                        selected: p.id == widget.selectedId,
                        onTap: () => widget.onPick(p),
                        titleHighlights: th,
                        subtitleHighlights: sh,
                        trailing: Icon(
                          p.id == widget.selectedId
                              ? Icons.check_circle
                              : (widget.opensPage
                                    ? Icons.chevron_right
                                    : Icons.circle_outlined),
                          color: p.id == widget.selectedId
                              ? JColors.goldBright
                              : (widget.opensPage ? JColors.brass : JColors.line),
                          size: 21,
                        ),
                      ),
                    ),
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One line of the picker.
sealed class _Row {
  const _Row();
}

class _EmptyRow extends _Row {
  const _EmptyRow();
}

class _QuickActionsRow extends _Row {
  const _QuickActionsRow();
}

class _HeaderRow extends _Row {
  const _HeaderRow(this.label);

  final String label;
}

class _PackageRow extends _Row {
  const _PackageRow(
    this.package, {
    this.titleHighlights = const [],
    this.subtitleHighlights = const [],
  });

  final PackageSummary package;
  final List<(int, int)> titleHighlights;
  final List<(int, int)> subtitleHighlights;
}

/// The card offered above every named packet: assembles a fresh one from
/// topics sampled across the whole library, rather than picking a fixed set.
class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.generatingRandom,
    required this.onPickRandom,
    required this.onOpenBuilder,
  });

  final bool generatingRandom;
  final VoidCallback onPickRandom;
  final VoidCallback onOpenBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 440;
        final randomTile = _ActionTile(
          icon: Icons.shuffle,
          iconGradient: const [
            Color(0xFFFFF0C4),
            JColors.goldBright,
            Color(0xFFC99A2E),
          ],
          iconColor: const Color(0xFF14120A),
          title: L.randomPackage,
          subtitle: L.randomPackageHint,
          loading: generatingRandom,
          onTap: generatingRandom ? null : onPickRandom,
        );

        final builderTile = _ActionTile(
          icon: Icons.tune,
          iconGradient: const [
            Color(0xFF3A56F5),
            JColors.boardLit,
            JColors.boardDeep,
          ],
          iconColor: JColors.goldBright,
          title: L.buildPackage,
          subtitle: L.buildPackageHint,
          loading: false,
          onTap: onOpenBuilder,
        );

        if (isNarrow) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              randomTile,
              const SizedBox(height: 8),
              builderTile,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: randomTile),
            const SizedBox(width: 8),
            Expanded(child: builderTile),
          ],
        );
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.iconGradient,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final List<Color> iconGradient;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Plate(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: iconGradient,
                stops: const [0, 0.12, 1],
              ),
              borderRadius: BorderRadius.circular(JRadius.tile),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: JColors.goldBright,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: JColors.textFaint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.chevron_right, color: JColors.brass, size: 18),
        ],
      ),
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

String? _cardSubtitle(String? raw) {
  if (raw == null) return null;
  final dot = raw.indexOf(' · ');
  if (dot != -1 && raw.startsWith('გენერირებული პაკეტი')) {
    return raw.substring(dot + 3).trim();
  }
  return raw;
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.package,
    required this.selected,
    this.onTap,
    this.trailing,
    this.titleHighlights = const [],
    this.subtitleHighlights = const [],
  });

  final PackageSummary package;
  final bool selected;

  /// Absent where the card is a heading rather than a choice.
  final VoidCallback? onTap;
  final Widget? trailing;
  final List<(int, int)> titleHighlights;
  final List<(int, int)> subtitleHighlights;

  Widget _buildSpanText({
    required String text,
    required TextStyle baseStyle,
    required TextStyle highlightStyle,
    required List<(int, int)> highlights,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    if (highlights.isEmpty) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final spans = <TextSpan>[];
    var curr = 0;
    for (final (start, end) in highlights) {
      if (start > curr && start <= text.length) {
        spans.add(TextSpan(text: text.substring(curr, start), style: baseStyle));
      }
      if (start < text.length) {
        final safeEnd = end.clamp(start, text.length);
        spans.add(
          TextSpan(
            text: text.substring(start, safeEnd),
            style: highlightStyle,
          ),
        );
        curr = safeEnd;
      }
    }
    if (curr < text.length) {
      spans.add(TextSpan(text: text.substring(curr), style: baseStyle));
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

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
              // A generated packet is numbered below zero so it cannot collide
              // with a catalogue number the seeder may still need (see
              // ContentService.generateRandomPackage). The sign is bookkeeping;
              // what the host is shown is which random packet this is.
              '${package.number.abs()}',
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
                _buildSpanText(
                  text: package.title,
                  baseStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: selected ? JColors.goldBright : JColors.text,
                  ),
                  highlightStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: JColors.goldBright,
                  ),
                  highlights: titleHighlights,
                ),
                if (package.subtitle != null) ...[
                  const SizedBox(height: 3),
                  _buildSpanText(
                    text: _cardSubtitle(package.subtitle)!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    baseStyle: const TextStyle(
                      color: JColors.textFaint,
                      fontSize: 12,
                      height: 1.35,
                    ),
                    highlightStyle: const TextStyle(
                      color: JColors.goldBright,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      height: 1.35,
                    ),
                    highlights: subtitleHighlights,
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

class _CategoriesSection extends StatelessWidget {
  const _CategoriesSection({
    required this.package,
    required this.selectedRoundIdx,
    required this.showRoundTabs,
    required this.onSelectRoundIdx,
    required this.onReroll,
    required this.onReplace,
    required this.rerollingTopicId,
  });

  final PackageSummary package;
  final int selectedRoundIdx;
  final bool showRoundTabs;
  final ValueChanged<int> onSelectRoundIdx;
  final ValueChanged<TopicSummary> onReroll;
  final ValueChanged<TopicSummary> onReplace;
  final int? rerollingTopicId;

  @override
  Widget build(BuildContext context) {
    final rounds = package.rounds;
    if (rounds.isEmpty) return const SizedBox.shrink();

    final activeRound = rounds.firstWhere(
      (r) => r.idx == selectedRoundIdx,
      orElse: () => rounds.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const _SectionLabel(L.categories),
        if (showRoundTabs) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in rounds)
                _Chip(
                  label:
                      r.finalRound ? L.finalRound : '${L.roundLabel} ${r.idx}',
                  selected: r.idx == activeRound.idx,
                  onTap: () => onSelectRoundIdx(r.idx),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (activeRound.topics.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'თემები არ მოიძებნა',
                      style: TextStyle(color: JColors.textMuted, fontSize: 13),
                    ),
                  ),
                )
              else
                for (var i = 0; i < activeRound.topics.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _TopicTile(
                    topic: activeRound.topics[i],
                    isRerolling:
                        rerollingTopicId == activeRound.topics[i].id,
                    onReroll: () => onReroll(activeRound.topics[i]),
                    onReplace: () => onReplace(activeRound.topics[i]),
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TopicTile extends StatelessWidget {
  const _TopicTile({
    required this.topic,
    required this.isRerolling,
    required this.onReroll,
    required this.onReplace,
  });

  final TopicSummary topic;
  final bool isRerolling;
  final VoidCallback onReroll;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: JColors.surfaceHigh,
              borderRadius: BorderRadius.circular(JRadius.control),
              border: Border.all(color: JColors.line),
            ),
            child: Text(
              '${topic.idx}',
              style: const TextStyle(
                fontFamily: 'Condensed',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: JColors.gold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              topic.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: JColors.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isRerolling)
            const SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              color: JColors.goldBright,
              tooltip: L.rerollCategoryTooltip,
              visualDensity: VisualDensity.compact,
              onPressed: onReroll,
            ),
            IconButton(
              icon: const Icon(Icons.search, size: 18),
              color: JColors.brass,
              tooltip: L.replaceWithSpecific,
              visualDensity: VisualDensity.compact,
              onPressed: onReplace,
            ),
          ],
        ],
      ),
    );
  }
}
