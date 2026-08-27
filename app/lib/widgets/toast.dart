import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// A message that lands at the top of the screen rather than over the controls.
///
/// Both consoles keep the buttons that matter along the bottom edge, which is
/// exactly where a snackbar sits -- so the peek warning covered "სწორი" and
/// "არასწორი" at the moment the host was reaching for them, and every API error
/// covered whatever the host had just failed to press. A banner under the app
/// bar interrupts nothing: it slides in, holds long enough to be read, and
/// leaves. Tapping it dismisses it early.
///
/// Set [error] for something that went wrong; it comes in crimson rather than
/// brass. One toast is on screen at a time -- a second replaces the first
/// instead of stacking under it.
void showToast(BuildContext context, String message, {bool error = false}) {
  // The root overlay, so the toast outlives a route that pops while it is up.
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _current?.dismiss();

  late final _ToastHandle handle;
  handle = _ToastHandle(
    OverlayEntry(
      builder: (_) =>
          _ToastCard(message: message, error: error, handle: handle),
    ),
  );
  _current = handle;
  overlay.insert(handle.entry);
}

/// How long a toast stays up once it has finished arriving.
const Duration _dwell = Duration(milliseconds: 3600);
const Duration _slide = Duration(milliseconds: 200);

_ToastHandle? _current;

/// Removal that can be asked for twice -- by the timer that ran out and by the
/// toast that replaced this one -- without the second throwing.
class _ToastHandle {
  _ToastHandle(this.entry);

  final OverlayEntry entry;
  bool _gone = false;

  void dismiss() {
    if (_gone) return;
    _gone = true;
    entry.remove();
    if (identical(_current, this)) _current = null;
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({
    required this.message,
    required this.error,
    required this.handle,
  });

  final String message;
  final bool error;
  final _ToastHandle handle;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _slide,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(_dwell, _leave);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    _timer?.cancel();
    if (!mounted) return;
    await _controller.reverse();
    widget.handle.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.error ? JColors.wrongBright : JColors.brass;
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Positioned(
      // Under the app bar where there is one, and a comfortable distance from
      // the top edge where there is not.
      top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
      left: 12,
      right: 12,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // A message a metre wide on a desktop reads as a page banner rather
          // than as something that just happened.
          constraints: const BoxConstraints(maxWidth: 560),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.35),
              end: Offset.zero,
            ).animate(curve),
            child: FadeTransition(
              opacity: curve,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(JRadius.card),
                  onTap: _leave,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [JColors.surfaceHigh, JColors.surface],
                      ),
                      borderRadius: BorderRadius.circular(JRadius.card),
                      border: Border.all(color: accent, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.55),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          widget.error
                              ? Icons.error_outline
                              : Icons.info_outline,
                          size: 19,
                          color: widget.error ? accent : JColors.gold,
                        ),
                        const SizedBox(width: 11),
                        Flexible(
                          child: Text(
                            widget.message,
                            style: const TextStyle(
                              color: JColors.text,
                              fontSize: 13.5,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
