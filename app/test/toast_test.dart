@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/widgets/toast.dart';

/// Messages arrive at the top because the controls are at the bottom.
///
/// The peek warning used to land on top of "სწორი" and "არასწორი" at the exact
/// moment the host was reaching for them.
void main() {
  /// A screen shaped like the consoles: app bar above, buttons along the
  /// bottom edge, and something in the middle that raises a message.
  Widget console({VoidCallback? onSecond}) => MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          appBar: AppBar(title: const Text('თამაში')),
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => showToast(context, L.peekWarning),
                  child: const Text('peek'),
                ),
                TextButton(
                  onPressed: () =>
                      showToast(context, 'გატყდა', error: true),
                  child: const Text('fail'),
                ),
                const Spacer(),
                FilledButton(onPressed: () {}, child: const Text(L.correct)),
              ],
            ),
          ),
        ),
      );

  testWidgets('a toast sits at the top, clear of the controls',
      (tester) async {
    await tester.pumpWidget(console());
    await tester.tap(find.text('peek'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text(L.peekWarning), findsOneWidget);

    final message = tester.getRect(find.text(L.peekWarning));
    final button = tester.getRect(find.widgetWithText(FilledButton, L.correct));
    final screen = tester.getSize(find.byType(MaterialApp));

    // Below the app bar, in the top third, and nowhere near the button it used
    // to cover.
    expect(message.top, greaterThan(kToolbarHeight));
    expect(message.bottom, lessThan(screen.height / 3));
    expect(message.bottom, lessThan(button.top));

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text(L.peekWarning), findsNothing);
  });

  testWidgets('tapping a toast dismisses it early', (tester) async {
    await tester.pumpWidget(console());
    await tester.tap(find.text('peek'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text(L.peekWarning));
    await tester.pumpAndSettle();
    expect(find.text(L.peekWarning), findsNothing);
  });

  testWidgets('a second message replaces the first rather than stacking',
      (tester) async {
    await tester.pumpWidget(console());
    await tester.tap(find.text('peek'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('fail'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text(L.peekWarning), findsNothing);
    expect(find.text('გატყდა'), findsOneWidget);
    // Failures are crimson and carry a different icon to a warning.
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsNothing);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
