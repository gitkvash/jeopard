import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/providers.dart';
import '../core/rest_client.dart';
import '../core/theme.dart';
import 'toast.dart';

/// Shows a dialog allowing players or the host to report an error with the clue.
Future<void> showClueReportDialog(
  BuildContext context, {
  required CurrentClue clue,
  RestClient? client,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => ClueReportDialog(clue: clue, client: client),
  );
}

class ClueReportDialog extends StatefulWidget {
  const ClueReportDialog({
    super.key,
    required this.clue,
    this.client,
  });

  final CurrentClue clue;
  final RestClient? client;

  @override
  State<ClueReportDialog> createState() => _ClueReportDialogState();
}

class _ClueReportDialogState extends State<ClueReportDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
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
    final text = _controller.text.trim();
    if (text.length < 5) {
      setState(() {
        _errorText = L.reportClueErrorMinLength;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final client = _resolveClient(context);
      final result = await client.reportClue(widget.clue.clueId, text);
      if (!mounted) return;

      Navigator.of(context).pop();
      showToast(
        context,
        result.message.isNotEmpty ? result.message : L.reportClueSuccess,
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
    final clue = widget.clue;
    final snippet = clue.question != null && clue.question!.trim().isNotEmpty
        ? (clue.question!.length > 90
            ? '${clue.question!.substring(0, 90).trim()}...'
            : clue.question!)
        : null;

    return Dialog(
      backgroundColor: JColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JRadius.panel),
        side: const BorderSide(color: JColors.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: JColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(JRadius.control),
                    ),
                    child: const Icon(
                      Icons.flag_outlined,
                      color: JColors.goldBright,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      L.reportClueTitle,
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
              const SizedBox(height: 14),

              // Category and snippet badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: JColors.backdrop.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(JRadius.control),
                  border: Border.all(color: JColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            clue.topicName.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: JColors.gold,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        if (clue.value != null)
                          Text(
                            '${clue.value} ${L.points}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    if (snippet != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: JColors.textMuted,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Description input
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                minLines: 3,
                maxLines: 5,
                maxLength: 500,
                enabled: !_submitting,
                style: const TextStyle(fontSize: 14, color: Colors.white),
                decoration: InputDecoration(
                  hintText: L.reportClueHint,
                  hintStyle: const TextStyle(fontSize: 13, color: JColors.textFaint),
                  contentPadding: const EdgeInsets.all(14),
                  counterStyle: const TextStyle(color: JColors.textFaint, fontSize: 11),
                ),
                onSubmitted: (_) => _submit(),
              ),

              // Error display
              if (_errorText != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              const SizedBox(height: 16),

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
                    child: const Text(L.reportClueCancel),
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
                            L.reportClueSubmit,
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
