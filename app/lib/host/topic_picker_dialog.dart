import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../core/theme.dart';
import '../widgets/stage.dart';

/// Shows a dialog or sheet to search and pick a topic from the library.
Future<AvailableTopic?> showTopicPickerDialog(
  BuildContext context, {
  required WidgetRef ref,
  required int roundIdx,
  String? currentTopicName,
}) async {
  return showDialog<AvailableTopic>(
    context: context,
    builder: (dialogCtx) => _TopicPickerDialog(
      roundIdx: roundIdx,
      currentTopicName: currentTopicName,
    ),
  );
}

class _TopicPickerDialog extends ConsumerStatefulWidget {
  const _TopicPickerDialog({
    required this.roundIdx,
    this.currentTopicName,
  });

  final int roundIdx;
  final String? currentTopicName;

  @override
  ConsumerState<_TopicPickerDialog> createState() => _TopicPickerDialogState();
}

class _TopicPickerDialogState extends ConsumerState<_TopicPickerDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<AvailableTopic> _allTopics = [];
  bool _loading = true;
  String? _error;
  bool _allRounds = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _fetchTopics();
    _searchCtrl.addListener(() {
      final text = _searchCtrl.text.trim();
      if (text != _query) {
        setState(() => _query = text);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchTopics() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final topics = await ref.read(restClientProvider).availableTopics(
            roundIdx: _allRounds ? null : widget.roundIdx,
          );
      if (!mounted) return;
      setState(() {
        _allTopics = topics;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<AvailableTopic> get _filteredTopics {
    if (_query.isEmpty) return _allTopics;
    final q = _query.toLowerCase();
    return _allTopics
        .where((t) => t.name.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFinal = widget.roundIdx > 3;
    final roundLabel = isFinal ? L.finalRoundTitle : '${widget.roundIdx} ${L.stepRound}';
    final filtered = _filteredTopics;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: JColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(JRadius.control),
                      border: Border.all(color: JColors.brass),
                    ),
                    child: const Icon(Icons.search, size: 20, color: JColors.goldBright),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          L.chooseFromLibrary,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: JColors.goldBright,
                          ),
                        ),
                        if (widget.currentTopicName != null)
                          Text(
                            'მიმდინარე: ${widget.currentTopicName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: JColors.textMuted,
                            ),
                          )
                        else
                          Text(
                            roundLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              color: JColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'დახურვა',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Search box
              TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: JColors.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: L.searchTopicsHint,
                  hintStyle: const TextStyle(color: JColors.textFaint, fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: JColors.brass, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => _searchCtrl.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: JColors.surfaceHigh,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
              const SizedBox(height: 10),

              // Filter toggle
              Row(
                children: [
                  ChoiceChip(
                    label: Text(roundLabel),
                    selected: !_allRounds,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      color: !_allRounds ? JColors.backdrop : JColors.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    onSelected: (_) {
                      setState(() => _allRounds = false);
                      _fetchTopics();
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text(L.allRoundsFilter),
                    selected: _allRounds,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      color: _allRounds ? JColors.backdrop : JColors.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    onSelected: (_) {
                      setState(() => _allRounds = true);
                      _fetchTopics();
                    },
                  ),
                  const Spacer(),
                  if (!_loading && _error == null)
                    Text(
                      '${filtered.length} თემა',
                      style: const TextStyle(color: JColors.textFaint, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),

              // Content list
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, color: JColors.wrong, size: 32),
                                const SizedBox(height: 8),
                                Text(
                                  _error!,
                                  style: const TextStyle(color: JColors.textMuted, fontSize: 12),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: _fetchTopics,
                                  child: const Text('ხელახლა ცდა'),
                                ),
                              ],
                            ),
                          )
                        : filtered.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.search_off, size: 36, color: JColors.brass),
                                    const SizedBox(height: 10),
                                    const Text(
                                      L.noTopicsFound,
                                      style: TextStyle(
                                        color: JColors.textMuted,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final topic = filtered[i];
                                  final isCurrent = widget.currentTopicName == topic.name;

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                    dense: true,
                                    title: Text(
                                      topic.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isCurrent ? JColors.goldBright : JColors.text,
                                      ),
                                    ),
                                    subtitle: Text(
                                      topic.packageTitle.isNotEmpty
                                          ? '${topic.packageTitle} · ${topic.finalRound ? L.finalRoundTitle : "${topic.roundIdx} ტური"}'
                                          : (topic.finalRound ? L.finalRoundTitle : '${topic.roundIdx} ტური'),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: JColors.textFaint,
                                      ),
                                    ),
                                    trailing: isCurrent
                                        ? const Icon(Icons.check_circle, color: JColors.goldBright, size: 20)
                                        : const Icon(Icons.add_circle_outline, color: JColors.brass, size: 20),
                                    onTap: () => Navigator.of(context).pop(topic),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
