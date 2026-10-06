import 'package:flutter/material.dart';

import '../core/responsive.dart';
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
  const ControlShelf({
    super.key,
    required this.children,
    this.trailing,
    this.side = false,
  });

  /// Laid out in a row, each taking an equal share, wrapping on narrow screens.
  final List<Widget> children;

  /// A quieter action (peeking at the answer), kept out of the main row.
  final Widget? trailing;

  /// A column standing beside the clue instead of a shelf under it. For a phone
  /// held sideways, where a shelf of buttons would take half the height.
  final bool side;

  static const double _maxWidth = 760;

  @override
  Widget build(BuildContext context) {
    if (side) return _buildSide();

    final short = context.isCompactHeight;
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
          padding: EdgeInsets.fromLTRB(16, short ? 10 : 14, 16, short ? 8 : 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Below this, an icon-and-label button pair does not fit side by
                  // side without truncating, so they stack instead. It is a
                  // narrow bar: a 360-pixel phone has 328 to share, which two
                  // buttons still fit, and stacking them there cost the clue
                  // above a hundred pixels it needed more.
                  final tight = constraints.maxWidth < 300;
                  // Two buttons in 328 pixels get 159 each. With the theme's 22
                  // pixels of padding on both sides and an icon, a word like
                  // "გამოტოვება" has 87 left and breaks mid-word.
                  final snug = !tight && constraints.maxWidth < 420;
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

                  final controls = snug ? _snug(context, row) : row;
                  if (trailing == null) return controls;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      controls,
                      SizedBox(height: short ? 2 : 6),
                      trailing!,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The same buttons with less padding either side, for a bar too narrow to
  /// give each of them room for its label at the theme's generous default.
  static Widget _snug(BuildContext context, Widget child) {
    final theme = Theme.of(context);
    const padding = WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 12),
    );
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: theme.filledButtonTheme.style?.copyWith(padding: padding),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: theme.outlinedButtonTheme.style?.copyWith(padding: padding),
        ),
      ),
      child: child,
    );
  }

  Widget _buildSide() {
    return SafeArea(
      left: false,
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              children[i],
            ],
            if (trailing != null) ...[const SizedBox(height: 4), trailing!],
          ],
        ),
      ),
    );
  }
}

/// A clue with the controls that go with it.
///
/// Upright, the controls are a shelf under the clue. Sideways on a phone there is
/// no height for a shelf, so the same controls stand in a column to its right and
/// the clue gets the full height back. Callers say what the controls are; this
/// decides where they go.
class ClueLayout extends StatelessWidget {
  const ClueLayout({
    super.key,
    required this.panel,
    required this.controls,
    this.sideWidth = 280,
  });

  /// The clue itself, with whatever sits under it (a host-only answer).
  final Widget panel;

  /// Builds the controls for the placement this layout chose.
  final Widget Function(bool side) controls;

  final double sideWidth;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final side = context.isShort && size.width > size.height;

    if (!side) {
      return Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: panel,
            ),
          ),
          controls(false),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: panel,
          ),
        ),
        SizedBox(width: sideWidth, child: controls(true)),
      ],
    );
  }
}
