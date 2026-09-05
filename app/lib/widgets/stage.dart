import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The room the game is played in.
///
/// Everything else in this app was drawn on a flat colour, which is what made it
/// read as a web page rather than a quiz. Two gradients fix that: light pooling
/// from above, and a vignette pulling the corners down to almost black. The
/// board then looks lit rather than painted, and nothing else has to work as
/// hard.
class Stage extends StatelessWidget {
  const Stage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Both gradients are screen-sized and neither ever changes, so each gets a
    // repaint boundary of its own. Sharing a layer with the content meant every
    // scrolled pixel -- of a forty-package list, of a board -- re-rasterised two
    // full-screen radial gradients along with it, which on CanvasKit is most of
    // a frame's budget spent redrawing something identical.
    return Stack(
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -1.15),
                radius: 1.35,
                colors: [JColors.stageLit, JColors.stage],
                stops: [0.0, 0.78],
              ),
            ),
          ),
        ),
        child,
        // Drawn over the content, but only at the edges and only faintly.
        const IgnorePointer(
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.2),
                  radius: 1.1,
                  colors: [Color(0x00000000), Color(0x66000000)],
                  stops: [0.55, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A raised plate: the surface everything that is not the board sits on.
///
/// Bevelled rather than outlined -- a one-pixel highlight along the top edge and
/// a shadow underneath do what a border used to, and read as a physical object
/// under stage light.
class Plate extends StatelessWidget {
  const Plate({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.accent,
    this.lit = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Draws a rule in this colour along the bottom, for a plate that needs to
  /// announce itself (a selected package, the answer block).
  final Color? accent;

  /// Brass frame and a soft glow: used for the thing currently in play.
  final bool lit;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final decorated = Container(
      padding: padding,
      decoration: BoxDecoration(
        // The pale first stop is the bevel: a highlight along the top edge,
        // which a border cannot provide on a rounded box.
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF232B47), JColors.surfaceHigh, JColors.surface],
          stops: [0, 0.10, 1],
        ),
        borderRadius: BorderRadius.circular(JRadius.card),
        border: Border.all(
          color: accent ?? (lit ? JColors.brass : JColors.line),
          width: accent != null ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          if (lit)
            BoxShadow(
              color: JColors.gold.withValues(alpha: 0.22),
              blurRadius: 26,
              spreadRadius: -6,
            ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return decorated;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(JRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(JRadius.card),
        onTap: onTap,
        child: decorated,
      ),
    );
  }
}

/// Small brass all-caps heading, the counterweight to the big numerals.
class Ticker extends StatelessWidget {
  const Ticker(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), style: kTicker)),
          ?trailing,
        ],
      ),
    );
  }
}

/// A thin brass rule, the app's one piece of ornament.
class BrassRule extends StatelessWidget {
  const BrassRule({super.key, this.width});

  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 2,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0x008A6A2A), JColors.brass, Color(0x008A6A2A)],
        ),
      ),
    );
  }
}

/// The shelf the game controls sit on.
///
/// A full-width row of buttons is fine on a phone and wrong on a desktop
/// browser, where the primary action ends up a metre wide and nothing is where
/// the hand expects it. So: a shelf with its own surface and a brass edge, the
/// controls centred inside it and capped at a comfortable reading width.
class ControlShelf extends StatelessWidget {
  const ControlShelf({super.key, required this.children, this.trailing});

  /// Laid out in a row, each taking an equal share, wrapping on narrow screens.
  final List<Widget> children;

  /// A quieter action (peeking at the answer), kept out of the main row.
  final Widget? trailing;

  static const double _maxWidth = 760;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x9905070F), Color(0xFF05070F)],
          stops: [0, 0.35, 1],
        ),
        border: Border(top: BorderSide(color: Color(0x338A6A2A))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Below this, an icon-and-label button pair does not fit side by
                  // side without truncating, so they stack instead.
                  final tight = constraints.maxWidth < 420;
                  final row = tight
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < children.length; i++) ...[
                              if (i > 0) const SizedBox(height: 8),
                              children[i],
                            ],
                          ],
                        )
                      : Row(
                          children: [
                            for (var i = 0; i < children.length; i++) ...[
                              if (i > 0) const SizedBox(width: 10),
                              Expanded(child: children[i]),
                            ],
                          ],
                        );

                  if (trailing == null) return row;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [row, const SizedBox(height: 6), trailing!],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
