@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeopard_app/core/models.dart';
import 'package:jeopard_app/core/providers.dart';
import 'package:jeopard_app/core/rest_client.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/host/host_setup_screen.dart';

/// A [RestClient] standing in for the real one, so a test can drive what
/// "generating a random packet" returns without a server.
class _FakeRestClient extends RestClient {
  _FakeRestClient(this.randomResult, {this.rerollResult});

  /// A package to return from [randomPackage], or null to make it throw --
  /// exercising the error path without a real network failure.
  final PackageSummary? randomResult;
  final TopicSummary? rerollResult;
  int randomCalls = 0;
  int rerollCalls = 0;

  @override
  Future<PackageSummary> randomPackage() async {
    randomCalls++;
    if (randomResult == null) {
      throw ApiException(500, 'server exploded');
    }
    return randomResult!;
  }

  @override
  Future<TopicSummary> rerollTopic(int packageId, int topicId) async {
    rerollCalls++;
    if (rerollResult != null) return rerollResult!;
    return TopicSummary(id: topicId, idx: 1, name: 'ევროპის დედაქალაქები');
  }
}

/// The picker holds thirty packages of two different provenances, and which one
/// a host is choosing is the thing they most need to see.
///
/// Choosing is also all the first screen does: the options that follow are a
/// page away on a phone and a panel away on a desktop, so that picking a
/// package is never followed by a scroll past the twenty that come after it.
void main() {
  PackageSummary package(int number,
          {required bool generated, String? sourceUrl}) =>
      PackageSummary(
        id: number,
        number: number,
        title: 'პაკეტი #$number',
        subtitle: generated ? 'გენერირებული პაკეტი (AI) · მუსიკა' : '2008 წელი',
        sourceUrl: sourceUrl ?? (generated ? 'generated:gemini-3.1-pro' : null),
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

  Widget setupScreen(List<PackageSummary> packages, {RestClient? restClient}) =>
      ProviderScope(
        overrides: [
          packagesProvider.overrideWith((ref) => packages),
          if (restClient != null) restClientProvider.overrideWithValue(restClient),
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
    expect(find.textContaining(L.generatedPackages.toUpperCase()), findsOneWidget);
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
    expect(find.textContaining(L.generatedPackages.toUpperCase()), findsNothing);
    expect(find.textContaining(L.argonPackages.toUpperCase()), findsNothing);
  });

  testWidgets('shows argon generated packages in their own section',
      (tester) async {
    await tester.pumpWidget(setupScreen([
      package(1, generated: false),
      package(7, generated: true),
      package(51, generated: true, sourceUrl: 'generated:argon'),
      package(52, generated: true, sourceUrl: 'generated:argon'),
    ]));
    await tester.pumpAndSettle();

    expect(find.textContaining(L.originalPackages), findsOneWidget);
    expect(find.textContaining(L.generatedPackages.toUpperCase()), findsOneWidget);
    expect(find.textContaining(L.argonPackages.toUpperCase()), findsOneWidget);
    expect(
        find.text('${L.originalPackages.toUpperCase()}  ·  1'), findsOneWidget);
    expect(
        find.text('${L.generatedPackages.toUpperCase()}  ·  1'), findsOneWidget);
    expect(
        find.text('${L.argonPackages.toUpperCase()}  ·  2'), findsOneWidget);
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
    // The options run past the fold of a phone; the last of them is a scroll away.
    await tester.scrollUntilVisible(find.text(L.hostPlaysToo), 200);
    expect(find.text(L.hostPlaysToo), findsOneWidget);
    final create = find.widgetWithText(FilledButton, L.create);
    expect(tester.widget<FilledButton>(create).onPressed, isNotNull);

    await tester.drag(find.byType(ListView).first, const Offset(0, 800));
    await tester.pumpAndSettle();
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

  testWidgets('the random packet card is offered first, above every named packet',
      (tester) async {
    await tester.pumpWidget(setupScreen([
      package(1, generated: false),
      package(7, generated: true),
    ]));
    await tester.pumpAndSettle();

    expect(find.text(L.randomPackage), findsOneWidget);
    final randomTop = tester.getTopLeft(find.text(L.randomPackage)).dy;
    final originalTop =
        tester.getTopLeft(find.textContaining(L.originalPackages)).dy;
    expect(randomTop, lessThan(originalTop));
  });

  testWidgets('tapping the random packet card generates one and opens it',
      (tester) async {
    usePhoneScreen(tester);
    final generated = package(99, generated: false);
    final client = _FakeRestClient(generated);
    await tester.pumpWidget(setupScreen(
      [package(1, generated: false)],
      restClient: client,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(L.randomPackage));
    await tester.pumpAndSettle();

    expect(client.randomCalls, 1);
    // Opened exactly like any other package: a page of its own, holding the
    // generated one and its setup.
    expect(find.text('პაკეტი #99'), findsOneWidget);
    expect(find.text(L.wholePackage), findsOneWidget);
  });

  testWidgets('a failed generation shows an error and leaves the list as it was',
      (tester) async {
    useWideScreen(tester);
    final client = _FakeRestClient(null);
    await tester.pumpWidget(setupScreen(
      [package(1, generated: false)],
      restClient: client,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(L.randomPackage));
    await tester.pumpAndSettle();

    expect(client.randomCalls, 1);
    expect(find.text(L.randomPackageError), findsOneWidget);
    // Still on the list, nothing picked.
    expect(find.text(L.choosePackage), findsOneWidget);

    // Let the toast's own dismiss timer run out so the test ends clean.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('random package shows categories and allows host to reroll a category',
      (tester) async {
    usePhoneScreen(tester);
    final generated = PackageSummary(
      id: 1000001,
      number: -1,
      title: 'შემთხვევითი პაკეტი #1',
      subtitle: 'თემები შემთხვევითობით აღებულია ყველა პაკეტიდან',
      sourceUrl: null,
      synthetic: true,
      rounds: [
        RoundSummary(
          id: 101,
          idx: 1,
          finalRound: false,
          playable: true,
          topicCount: 6,
          topics: [
            TopicSummary(id: 1001, idx: 1, name: 'ქართული კინო'),
            TopicSummary(id: 1002, idx: 2, name: 'ისტორია'),
          ],
        ),
        RoundSummary(
          id: 102,
          idx: 2,
          finalRound: false,
          playable: true,
          topicCount: 6,
          topics: [
            TopicSummary(id: 2001, idx: 1, name: 'სპორტი'),
          ],
        ),
      ],
    );
    final client = _FakeRestClient(
      generated,
      rerollResult: TopicSummary(id: 1001, idx: 1, name: 'ევროპის დედაქალაქები'),
    );

    await tester.pumpWidget(setupScreen(
      [package(1, generated: false)],
      restClient: client,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text(L.randomPackage));
    await tester.pumpAndSettle();

    // Verify categories section is present and shows Round 1 topics
    expect(find.text(L.categories), findsOneWidget);
    expect(find.text('ქართული კინო'), findsOneWidget);
    expect(find.text('ისტორია'), findsOneWidget);

    // Tap refresh icon on 'ქართული კინო'
    final refreshIcons = find.byIcon(Icons.refresh);
    await tester.tap(refreshIcons.first);
    await tester.pumpAndSettle();

    expect(client.rerollCalls, 1);
    // Old category replaced by new category
    expect(find.text('ქართული კინო'), findsNothing);
    expect(find.text('ევროპის დედაქალაქები'), findsOneWidget);

    // Switch to Round 2 tab
    await tester.tap(find.widgetWithText(ChoiceChip, '${L.roundLabel} 2'));
    await tester.pumpAndSettle();

    expect(find.text('სპორტი'), findsOneWidget);
    expect(find.text('ევროპის დედაქალაქები'), findsNothing);

    // Let any toast dismiss timer run out
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'questions are hidden from players by default, and players picking is opt-in',
      (tester) async {
    usePhoneScreen(tester);
    await tester.pumpWidget(setupScreen([package(1, generated: false)]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('პაკეტი #1'));
    await tester.pumpAndSettle();

    SwitchListTile row(String title) => tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, title, skipOffstage: false));

    // Off both: a room plays by ear unless the host asks for more, and the host
    // chooses the tiles unless they hand that to the players.
    expect(row(L.participantsSeeQuestions).value, isFalse);
    expect(row(L.playersPickClues).value, isFalse);

    await tester.ensureVisible(find.text(L.playersPickClues));
    await tester.tap(find.text(L.playersPickClues));
    await tester.pumpAndSettle();
    expect(row(L.playersPickClues).value, isTrue);
    expect(row(L.participantsSeeQuestions).value, isFalse);
  });
}
