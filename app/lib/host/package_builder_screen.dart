import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../core/theme.dart';
import '../widgets/stage.dart';
import '../widgets/toast.dart';
import 'host_setup_screen.dart';
import 'topic_picker_dialog.dart';

class PackageBuilderScreen extends ConsumerStatefulWidget {
  const PackageBuilderScreen({super.key});

  @override
  ConsumerState<PackageBuilderScreen> createState() => _PackageBuilderScreenState();
}

class _PackageBuilderScreenState extends ConsumerState<PackageBuilderScreen> {
  /// Step 0: Round 1, Step 1: Round 2, Step 2: Round 3, Step 3: Final, Step 4: Overview
  int _currentStep = 0;

  final List<AvailableTopic> _round1Topics = [];
  final List<AvailableTopic> _round2Topics = [];
  final List<AvailableTopic> _round3Topics = [];
  final List<AvailableTopic> _finalTopics = [];

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _titleCtrl = TextEditingController(text: L.defaultCustomPackageTitle);

  List<AvailableTopic> _availablePool = [];
  bool _loadingPool = true;
  String _searchQuery = '';

  PackageSummary? _builtPackage;
  bool _isBuilding = false;
  int? _actionTopicId; // For rerolling / replacing spinner

  @override
  void initState() {
    super.initState();
    _fetchPoolForStep(_currentStep);
    _searchCtrl.addListener(() {
      final text = _searchCtrl.text.trim();
      if (text != _searchQuery) {
        setState(() => _searchQuery = text);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  int _roundIdxForStep(int step) => switch (step) {
        0 => 1,
        1 => 2,
        2 => 3,
        _ => 4,
      };

  int _maxForStep(int step) => step == 3 ? 2 : 6;

  List<AvailableTopic> _selectedForStep(int step) => switch (step) {
        0 => _round1Topics,
        1 => _round2Topics,
        2 => _round3Topics,
        3 => _finalTopics,
        _ => [],
      };

  Future<void> _fetchPoolForStep(int step) async {
    if (step >= 4) return;
    setState(() => _loadingPool = true);
    try {
      final topics = await ref.read(restClientProvider).availableTopics(
            roundIdx: _roundIdxForStep(step),
          );
      if (!mounted) return;
      setState(() {
        _availablePool = topics;
        _loadingPool = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPool = false);
    }
  }

  void _onStepChanged(int newStep) {
    if (newStep == _currentStep) return;
    setState(() {
      _currentStep = newStep;
      _searchCtrl.clear();
      _searchQuery = '';
    });
    if (newStep < 4) {
      _fetchPoolForStep(newStep);
    }
  }

  bool _isTopicSelectedAnywhere(int topicId) {
    return _round1Topics.any((t) => t.id == topicId) ||
        _round2Topics.any((t) => t.id == topicId) ||
        _round3Topics.any((t) => t.id == topicId) ||
        _finalTopics.any((t) => t.id == topicId);
  }

  void _toggleTopic(AvailableTopic topic) {
    final list = _selectedForStep(_currentStep);
    final existingIdx = list.indexWhere((t) => t.id == topic.id);

    if (existingIdx != -1) {
      setState(() => list.removeAt(existingIdx));
      return;
    }

    final max = _maxForStep(_currentStep);
    if (list.length >= max) {
      showToast(context, L.maxTopicsReached);
      return;
    }

    setState(() => list.add(topic));
  }

  void _removeTopicAt(int index) {
    final list = _selectedForStep(_currentStep);
    if (index >= 0 && index < list.length) {
      setState(() => list.removeAt(index));
    }
  }

  /// At ANY point in time, user can click to fill the rest randomly and view
  /// the complete assembled package.
  Future<void> _buildAndReview({bool fillRestRandomly = true}) async {
    if (_isBuilding) return;
    setState(() => _isBuilding = true);

    try {
      final created = await ref.read(restClientProvider).buildPackage(
            title: _titleCtrl.text.trim(),
            round1TopicIds: _round1Topics.map((t) => t.id).toList(),
            round2TopicIds: _round2Topics.map((t) => t.id).toList(),
            round3TopicIds: _round3Topics.map((t) => t.id).toList(),
            finalTopicIds: _finalTopics.map((t) => t.id).toList(),
          );

      if (!mounted) return;
      setState(() {
        _builtPackage = created;
        _currentStep = 4; // Overview step
        _isBuilding = false;
      });

      if (fillRestRandomly) {
        showToast(context, 'პაკეტი წარმატებით აეწყო!');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBuilding = false);
      showToast(context, L.buildPackageError, error: true);
    }
  }

  Future<void> _rerollTopicInBuilt(TopicSummary topic) async {
    if (_builtPackage == null || _actionTopicId != null) return;
    setState(() => _actionTopicId = topic.id);
    try {
      final updated = await ref
          .read(restClientProvider)
          .rerollTopic(_builtPackage!.id, topic.id);

      if (!mounted) return;
      final newRounds = _builtPackage!.rounds.map((r) {
        return r.copyWith(
          topics: r.topics
              .map((t) => t.id == topic.id ? updated : t)
              .toList(),
        );
      }).toList();

      setState(() {
        _builtPackage = _builtPackage!.copyWith(rounds: newRounds);
        _actionTopicId = null;
      });
      showToast(context, '${L.categoryReplaced}: ${updated.name}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionTopicId = null);
      showToast(context, L.rerollError, error: true);
    }
  }

  Future<void> _replaceTopicWithLibrary(int roundIdx, TopicSummary topic) async {
    if (_builtPackage == null || _actionTopicId != null) return;

    final picked = await showTopicPickerDialog(
      context,
      ref: ref,
      roundIdx: roundIdx,
      currentTopicName: topic.name,
    );

    if (picked == null || !mounted) return;

    setState(() => _actionTopicId = topic.id);
    try {
      final updated = await ref
          .read(restClientProvider)
          .replaceTopic(_builtPackage!.id, topic.id, picked.id);

      if (!mounted) return;
      final newRounds = _builtPackage!.rounds.map((r) {
        return r.copyWith(
          topics: r.topics
              .map((t) => t.id == topic.id ? updated : t)
              .toList(),
        );
      }).toList();

      setState(() {
        _builtPackage = _builtPackage!.copyWith(rounds: newRounds);
        _actionTopicId = null;
      });
      showToast(context, '${L.topicReplaced}: ${updated.name}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionTopicId = null);
      showToast(context, 'თემის ჩანაცვლება ვერ მოხერხდა', error: true);
    }
  }

  void _proceedToGameOptions() {
    if (_builtPackage == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HostOptionsScreen(package: _builtPackage!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(L.buildPackageTitle),
        actions: [
          if (_currentStep < 4)
            TextButton.icon(
              onPressed: _isBuilding ? null : () => _buildAndReview(fillRestRandomly: true),
              icon: _isBuilding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.shuffle, size: 18, color: JColors.goldBright),
              label: const Text(
                L.fillRestRandomly,
                style: TextStyle(
                  color: JColors.goldBright,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildStepperHeader(),
            const Divider(height: 1),
            Expanded(
              child: _currentStep < 4 ? _buildRoundStepView() : _buildOverviewView(),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepperHeader() {
    final steps = [
      (label: L.round1Title, count: _round1Topics.length, max: 6),
      (label: L.round2Title, count: _round2Topics.length, max: 6),
      (label: L.round3Title, count: _round3Topics.length, max: 6),
      (label: L.finalRoundTitle, count: _finalTopics.length, max: 2),
      (label: L.packageOverview, count: 0, max: 0),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.chevron_right, size: 16, color: JColors.line),
              ),
            InkWell(
              borderRadius: BorderRadius.circular(JRadius.control),
              onTap: () {
                if (i == 4) {
                  if (_builtPackage != null) {
                    _onStepChanged(4);
                  } else {
                    _buildAndReview(fillRestRandomly: true);
                  }
                } else {
                  _onStepChanged(i);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _currentStep == i ? JColors.goldBright : JColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(JRadius.control),
                  border: Border.all(
                    color: _currentStep == i ? JColors.goldBright : JColors.line,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      steps[i].label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _currentStep == i ? JColors.backdrop : JColors.text,
                      ),
                    ),
                    if (steps[i].max > 0) ...[
                      const SizedBox(width: 5),
                      Text(
                        '(${steps[i].count}/${steps[i].max})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _currentStep == i
                              ? JColors.backdrop.withValues(alpha: 0.8)
                              : JColors.brass,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoundStepView() {
    final selected = _selectedForStep(_currentStep);
    final max = _maxForStep(_currentStep);
    final roundIdx = _roundIdxForStep(_currentStep);
    final isFinal = _currentStep == 3;

    // Local filter for search
    final filteredPool = _searchQuery.isEmpty
        ? _availablePool
        : _availablePool
            .where((t) => t.name.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Chosen topics card / slots
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${isFinal ? L.finalRoundTitle : "$roundIdx ${L.stepRound}"} · ${selected.length}/$max არჩეული',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: JColors.goldBright,
                      ),
                    ),
                  ),
                  if (selected.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => selected.clear()),
                      child: const Text('გასუფთავება', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // Slot chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < max; i++)
                    if (i < selected.length)
                      Chip(
                        backgroundColor: JColors.surfaceHigh,
                        side: const BorderSide(color: JColors.brass),
                        avatar: CircleAvatar(
                          radius: 10,
                          backgroundColor: JColors.goldBright,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: JColors.backdrop,
                            ),
                          ),
                        ),
                        label: Text(
                          selected[i].name,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => _removeTopicAt(i),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: JColors.stageLit,
                          borderRadius: BorderRadius.circular(JRadius.control),
                          border: Border.all(
                            color: JColors.line,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: JColors.textFaint,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'შემთხვევითი',
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: JColors.textFaint,
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),
        const Divider(height: 1),

        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: JColors.text, fontSize: 14),
            decoration: InputDecoration(
              hintText: L.searchTopicsHint,
              hintStyle: const TextStyle(color: JColors.textFaint, fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: JColors.brass, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => _searchCtrl.clear(),
                    )
                  : null,
              filled: true,
              fillColor: JColors.surfaceHigh,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
        ),

        // Topics list
        Expanded(
          child: _loadingPool
              ? const Center(child: CircularProgressIndicator())
              : filteredPool.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off, size: 36, color: JColors.brass),
                          const SizedBox(height: 8),
                          const Text(
                            L.noTopicsFound,
                            style: TextStyle(color: JColors.textMuted, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      itemCount: filteredPool.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final topic = filteredPool[i];
                        final isSelectedInThisRound = selected.any((t) => t.id == topic.id);
                        final isSelectedElsewhere = !isSelectedInThisRound &&
                            _isTopicSelectedAnywhere(topic.id);

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                          dense: true,
                          title: Text(
                            topic.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isSelectedInThisRound
                                  ? JColors.goldBright
                                  : isSelectedElsewhere
                                      ? JColors.textFaint
                                      : JColors.text,
                            ),
                          ),
                          subtitle: Text(
                            topic.packageTitle.isNotEmpty
                                ? '${topic.packageTitle} · ${topic.finalRound ? L.finalRoundTitle : "${topic.roundIdx} ტური"}'
                                : (topic.finalRound ? L.finalRoundTitle : '${topic.roundIdx} ტური'),
                            style: const TextStyle(fontSize: 11, color: JColors.textFaint),
                          ),
                          trailing: isSelectedInThisRound
                              ? const Icon(Icons.check_circle, color: JColors.goldBright, size: 22)
                              : isSelectedElsewhere
                                  ? const Text(
                                      'სხვა ტურშია',
                                      style: TextStyle(fontSize: 11, color: JColors.textFaint),
                                    )
                                  : const Icon(Icons.add_circle_outline, color: JColors.brass, size: 22),
                          onTap: isSelectedElsewhere ? null : () => _toggleTopic(topic),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildOverviewView() {
    if (_builtPackage == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.layers_clear, size: 40, color: JColors.brass),
            const SizedBox(height: 12),
            const Text(
              'პაკეტი ჯერ არ არის აწყობილი',
              style: TextStyle(color: JColors.textMuted, fontSize: 16),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _buildAndReview(fillRestRandomly: true),
              icon: const Icon(Icons.shuffle, size: 18),
              label: const Text(L.fillRestRandomly),
            ),
          ],
        ),
      );
    }

    final pkg = _builtPackage!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Header
        Plate(
          lit: true,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFF0C4), JColors.goldBright, Color(0xFFC99A2E)],
                      ),
                      borderRadius: BorderRadius.circular(JRadius.tile),
                    ),
                    child: const Icon(Icons.check, color: Color(0xFF14120A), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pkg.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: JColors.goldBright,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          L.packageOverviewHint,
                          style: TextStyle(fontSize: 12, color: JColors.textFaint),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Rounds and topics
        for (final round in pkg.rounds) ...[
          _buildOverviewRoundCard(round),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _buildOverviewRoundCard(RoundSummary round) {
    final title = round.finalRound ? L.finalRoundTitle : '${round.idx} ${L.stepRound}';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: JColors.surfaceHigh,
            child: Row(
              children: [
                Text(
                  title.toUpperCase(),
                  style: kTicker.copyWith(letterSpacing: 1.5, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  '${round.topics.length} თემა',
                  style: const TextStyle(color: JColors.textFaint, fontSize: 11),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (var i = 0; i < round.topics.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _buildOverviewTopicRow(round.idx, round.topics[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildOverviewTopicRow(int roundIdx, TopicSummary topic) {
    final isActing = _actionTopicId == topic.id;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
          if (isActing)
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
            // Reroll random button
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              color: JColors.goldBright,
              tooltip: L.randomizeThisTopic,
              visualDensity: VisualDensity.compact,
              onPressed: () => _rerollTopicInBuilt(topic),
            ),
            // Replace with specific topic from library
            IconButton(
              icon: const Icon(Icons.search, size: 18),
              color: JColors.brass,
              tooltip: L.replaceWithSpecific,
              visualDensity: VisualDensity.compact,
              onPressed: () => _replaceTopicWithLibrary(roundIdx, topic),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: JColors.surface,
        border: Border(top: BorderSide(color: JColors.line)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          if (_currentStep == 4) ...[
            // In overview step
            OutlinedButton.icon(
              onPressed: () => _onStepChanged(0),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('რედაქტირება'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _proceedToGameOptions,
              icon: const Icon(Icons.play_arrow, size: 20),
              label: const Text(L.startGameWithOptions),
            ),
          ] else ...[
            // In round steps (0 to 3)
            if (_currentStep > 0)
              OutlinedButton.icon(
                onPressed: () => _onStepChanged(_currentStep - 1),
                icon: const Icon(Icons.chevron_left, size: 18),
                label: const Text(L.previousRound),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () {
                if (_currentStep < 3) {
                  _onStepChanged(_currentStep + 1);
                } else {
                  _buildAndReview(fillRestRandomly: true);
                }
              },
              icon: Icon(
                _currentStep < 3 ? Icons.chevron_right : Icons.check,
                size: 18,
              ),
              label: Text(_currentStep < 3 ? L.nextRound : L.finishAndReview),
            ),
          ],
        ],
      ),
    );
  }
}
