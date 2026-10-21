import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../core/rest_client.dart';
import '../core/theme.dart';
import 'toast.dart';

/// Shows a dialog allowing users to suggest a new topic or category for future game packages.
Future<void> showTopicSuggestionDialog(
  BuildContext context, {
  RestClient? client,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => TopicSuggestionDialog(client: client),
  );
}

class TopicSuggestionDialog extends StatefulWidget {
  const TopicSuggestionDialog({super.key, this.client});

  final RestClient? client;

  @override
  State<TopicSuggestionDialog> createState() => _TopicSuggestionDialogState();
}

class _TopicSuggestionDialogState extends State<TopicSuggestionDialog> {
  final _topicController = TextEditingController();
  final _descController = TextEditingController();
  final _authorController = TextEditingController();

  final _focusNode = FocusNode();
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _topicController.dispose();
    _descController.dispose();
    _authorController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  RestClient _resolveClient(BuildContext context) {
    if (widget.client != null) return widget.client!;
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      return container.read(restClientProvider);
    } catch (_) {
      return RestClient();
    }
  }

  Future<void> _submit() async {
    final topic = _topicController.text.trim();
    if (topic.length < 2) {
      setState(() {
        _errorText = L.topicErrorMinLength;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final client = _resolveClient(context);
      final TopicSuggestionResult result = await client.suggestTopic(
        topicName: topic,
        description: _descController.text.trim(),
        authorName: _authorController.text.trim(),
      );
      if (!mounted) return;

      Navigator.of(context).pop();
      showToast(
        context,
        result.message.isNotEmpty ? result.message : L.topicSuccess,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: JColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JRadius.panel),
        side: const BorderSide(color: JColors.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2C14E).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(JRadius.control),
                      border: Border.all(
                        color: JColors.gold.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.lightbulb_outline,
                      color: JColors.goldBright,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      L.suggestTopicTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: L.cancel,
                    onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Intro text
              Text(
                L.suggestTopicIntro,
                style: const TextStyle(
                  color: JColors.textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),

              // Topic Name (Required)
              Text(
                L.topicNameField,
                style: const TextStyle(
                  color: JColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _topicController,
                focusNode: _focusNode,
                autofocus: true,
                maxLength: 100,
                enabled: !_submitting,
                style: const TextStyle(fontSize: 14, color: Colors.white),
                decoration: const InputDecoration(
                  hintText: L.topicNameHint,
                  hintStyle: TextStyle(fontSize: 13, color: JColors.textFaint),
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  counterStyle: TextStyle(color: JColors.textFaint, fontSize: 11),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 10),

              // Description / details (Optional)
              Text(
                L.topicDescField,
                style: const TextStyle(
                  color: JColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _descController,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                enabled: !_submitting,
                style: const TextStyle(fontSize: 14, color: Colors.white),
                decoration: const InputDecoration(
                  hintText: L.topicDescHint,
                  hintStyle: TextStyle(fontSize: 13, color: JColors.textFaint),
                  contentPadding: EdgeInsets.all(12),
                  counterStyle: TextStyle(color: JColors.textFaint, fontSize: 11),
                ),
              ),
              const SizedBox(height: 10),

              // Author Name (Optional)
              Text(
                L.topicAuthorField,
                style: const TextStyle(
                  color: JColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _authorController,
                maxLength: 60,
                enabled: !_submitting,
                style: const TextStyle(fontSize: 14, color: Colors.white),
                decoration: const InputDecoration(
                  hintText: L.topicAuthorHint,
                  hintStyle: TextStyle(fontSize: 13, color: JColors.textFaint),
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  counterStyle: TextStyle(color: JColors.textFaint, fontSize: 11),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),

              // Error display
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: JColors.wrong.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(JRadius.control),
                    border: Border.all(color: JColors.wrong.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: JColors.wrong),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorText!,
                          style: const TextStyle(color: JColors.wrong, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(80, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text(L.topicCancel),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: JColors.goldBright,
                      foregroundColor: JColors.backdrop,
                      minimumSize: const Size(100, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: JColors.backdrop,
                            ),
                          )
                        : const Text(
                            L.topicSubmit,
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
