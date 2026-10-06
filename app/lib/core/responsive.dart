import 'package:flutter/material.dart';

/// How much room a screen has, as the layouts need to ask it.
///
/// Decided by the space available rather than by what kind of device it is: a
/// phone held sideways is 360 logical pixels tall, and what has to give there is
/// the same whether it is an iPhone or a small browser window.
extension ScreenRoom on BuildContext {
  /// A phone on its side. Wide enough for two columns, far too short for the
  /// stacked layout: an app bar, a score strip and a shelf of buttons add up to
  /// the whole screen before the clue gets any of it.
  bool get isShort => MediaQuery.sizeOf(this).height < 480;

  /// A phone upright, or anything like one. Not short, but the chrome still
  /// costs a third of the screen unless it is trimmed.
  bool get isCompactHeight => MediaQuery.sizeOf(this).height < 700;

  /// Narrower than a modern phone: the 360px class of Android handset.
  bool get isNarrow => MediaQuery.sizeOf(this).width < 400;

  /// Height of the app bar: a landscape phone cannot spare Material's 56.
  double get appBarHeight => isShort ? 44 : kToolbarHeight;
}
