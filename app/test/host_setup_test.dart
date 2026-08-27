@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeopard_app/core/models.dart';
import 'package:jeopard_app/core/providers.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/host/host_setup_screen.dart';

/// The picker holds thirty packages of two different provenances, and which one
/// a host is choosing is the thing they most need to see.
///
/// Choosing is also all the first screen does: the options that follow are a
/// page away on a phone and a panel away on a desktop, so that picking a
/// package is never followed by a scroll past the twenty that come after it.
void main() {
  PackageSummary package(int number, {required bool generated}) =>
      PackageSummary(
        id: number,
        number: number,
        title: 'პაკეტი #$number',
        subtitle: generated ? 'გენერირებული პაკეტი (AI) · მუსიკა' : '2008 წელი',
        sourceUrl: generated ? 'generated:gemini-3.1-pro' : null,
        rounds: [
          for (var i = 1; i <= 3; i++)
            RoundSummary(
                id: number * 10 + i,
                idx: i,
                finalRound: false,
                playable: true,
                topicCount: 6),
          RoundSummary(
              id: number * 10 + 4,
              idx: 4,
              finalRound: true,
              playable: false,
              topicCount: 2),
        ],
      );

  Widget setupScreen(List<PackageSummary> packages) => ProviderScope(
        overrides: [
          packagesProvider.overrideWith((ref) => packages),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: const HostSetupScreen(),
        ),
      );

  /// A phone: narrow enough for the two-step flow, and as tall as a real one.
  /// The 800x600 test default is shorter than any device this runs on, and a
  /// ListView does not build what is below the fold.
  void usePhoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Wide enough for the list and the options side by side.
  void useWideScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('archive and generated packages are listed separately',
      (tester) async {
    await tester.pumpWidget(setupScreen([
      package(1, generated: false),
      package(2, generated: false),
      package(7, generated: true),
      package(8, generated: true),
      package(9, generated: true),
    ]));
    await tester.pumpAndSettle();

    expect(find.textContaining(L.originalPackages), findsOneWidget);
    expect(find.textContaining(L.generatedPackages), findsOneWidget);
    // The heading carries the count, so a host can see at a glance how much of
    // the set is archive material.
    expect(find.text('${L.originalPackages.toUpperCase()}  ·  2'), findsOneWidget);
    expect(find.text('${L.generatedPackages.toUpperCase()}  ·  3'), findsOneWidget);
  });

  testWidgets('a section with nothing in it is not shown at all',
      (tester) async {
    await tester.pumpWidget(setupScreen([package(1, generated: false)]));
    await tester.pumpAndSettle();

    expect(find.textContaining(L.originalPackages), findsOneWidget);
    expect(find.textContaining(L.generatedPackages), findsNothing);
  });

  testWidgets('on a narrow screen the list is only a list', (tester) async {
    await tester.pumpWidget(setupScreen([package(1, generated: false)]));
    await tester.pumpAndSettle();

    // Nothing to set up and nothing to press yet: the options used to sit below
    // the last package, which on thirty of them is a long way down.
    expect(find.text(L.wholePackage), findsNothing);
    expect(find.widgetWithText(FilledButton, L.create), findsNothing);
  });

  testWidgets('choosing a package opens the options, and back returns to the list',
      (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(setupScreen([
      package(1, generated: false),
      package(2, generated: false),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('პაკეტი #1'));
    await tester.pumpAndSettle();

    // A page of its own, holding the chosen package and nothing but its setup.
    expect(find.text('პაკეტი #1'), findsOneWidget);
    expect(find.text('პაკეტი #2'), findsNothing);
    expect(find.text(L.wholePackage), findsOneWidget);
    expect(find.text(L.hostPlaysToo), findsOneWidget);
    final create = find.widgetWithText(FilledButton, L.create);
    expect(tester.widget<FilledButton>(create).onPressed, isNotNull);

    await tester.tap(find.text(L.changePackage));
    await tester.pumpAndSettle();

    // Back on the list, with the choice still marked.
    expect(find.text('პაკეტი #2'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('a single round can be picked instead of the whole package',
      (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(setupScreen([package(1, generated: false)]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('პაკეტი #1'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, '${L.roundLabel} 1'), findsNothing);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    // The first board stands in, so turning the switch off does not disable the
    // button with nothing on screen to explain why.
    final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '${L.roundLabel} 1'));
    expect(chip.selected, isTrue);
    final create = find.widgetWithText(FilledButton, L.create);
    expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
  });

  testWidgets('the buzzer opens the way the host chose, and a timer needs a number',
      (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(setupScreen([package(1, generated: false)]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('პაკეტი #1'));
    await tester.pumpAndSettle();

    // Whoever says nothing gets the old behaviour: the host opens it.
    expect(find.text(L.buzzModeHost), findsOneWidget);
    expect(find.text(L.buzzModeInstant), findsOneWidget);
    expect(find.text(L.buzzDelayLabel), findsNothing);

    await tester.tap(find.text(L.buzzModeTimer));
    await tester.pumpAndSettle();

    // Seconds only matter for the automatic buzzer, so they appear with it.
    expect(find.text(L.buzzDelayLabel), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '10 ${L.seconds}'), findsOneWidget);
    final create = find.widgetWithText(FilledButton, L.create);
    expect(tester.widget<FilledButton>(create).onPressed, isNotNull);

    await tester.tap(find.text(L.customDelay));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '900');
    await tester.pumpAndSettle();

    // Nine hundred seconds is not reading time, and the server would refuse it,
    // so the button does -- in Georgian, before the request.
    expect(find.text(L.buzzDelayRange), findsOneWidget);
    expect(tester.widget<FilledButton>(create).onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, '25');
    await tester.pumpAndSettle();
    expect(find.text(L.buzzDelayRange), findsNothing);
    expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
  });

  testWidgets('on a wide screen the options sit beside the list',
      (tester) async {
    useWideScreen(tester);
    await tester.pumpWidget(setupScreen([
      package(1, generated: false),
      package(2, generated: false),
    ]));
    await tester.pumpAndSettle();

    // Nothing chosen: the panel says what it is for rather than sitting empty.
    expect(find.text(L.choosePackage), findsOneWidget);
    expect(find.widgetWithText(FilledButton, L.create), findsNothing);

    await tester.tap(find.text('პაკეტი #1'));
    await tester.pumpAndSettle();

    // No page was pushed -- the list is still there, and so are the options.
    expect(find.textContaining(L.originalPackages), findsOneWidget);
    expect(find.text(L.wholePackage), findsOneWidget);
    expect(find.text(L.changePackage), findsNothing);
    final create = find.widgetWithText(FilledButton, L.create);
    expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
    // Named twice: once in the list, once at the head of the panel.
    expect(find.text('პაკეტი #1'), findsNWidgets(2));
  });

  testWidgets('switching packages in the panel drops the round chosen for the old one',
      (tester) async {
    useWideScreen(tester);
    await tester.pumpWidget(setupScreen([
      package(1, generated: false),
      package(2, generated: false),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('პაკეტი #1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, '${L.roundLabel} 1'))
            .selected,
        isTrue);

    await tester.tap(find.text('პაკეტი #2'));
    await tester.pumpAndSettle();

    // Round ids belong to the package they came from, so package two starts
    // with nothing chosen -- but the switch the host set stays set.
    expect(find.text('პაკეტი #2'), findsNWidgets(2));
    expect(
        tester
            .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, '${L.roundLabel} 1'))
            .selected,
        isFalse);
    final create = find.widgetWithText(FilledButton, L.create);
    expect(tester.widget<FilledButton>(create).onPressed, isNull);
  });
}
