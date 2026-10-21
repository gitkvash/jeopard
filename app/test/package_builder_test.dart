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
import 'package:jeopard_app/host/package_builder_screen.dart';

class _FakeBuilderClient extends RestClient {
  _FakeBuilderClient({
    required this.availableTopicsList,
    required this.builtPackageResult,
  });

  final List<AvailableTopic> availableTopicsList;
  final PackageSummary builtPackageResult;

  int availableCalls = 0;
  int buildCalls = 0;
  int rerollCalls = 0;
  int replaceCalls = 0;

  List<int>? lastRound1Ids;
  List<int>? lastRound2Ids;
  List<int>? lastRound3Ids;
  List<int>? lastFinalIds;

  @override
  Future<List<AvailableTopic>> availableTopics({int? roundIdx, String? query}) async {
    availableCalls++;
    return availableTopicsList.where((t) {
      if (roundIdx != null) {
        if (roundIdx == 4) {
          if (!t.finalRound) return false;
        } else {
          if (t.finalRound || t.roundIdx != roundIdx) return false;
        }
      }
      if (query != null && query.isNotEmpty) {
        if (!t.name.toLowerCase().contains(query.toLowerCase())) return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<PackageSummary> buildPackage({
    String? title,
    List<int>? round1TopicIds,
    List<int>? round2TopicIds,
    List<int>? round3TopicIds,
    List<int>? finalTopicIds,
  }) async {
    buildCalls++;
    lastRound1Ids = round1TopicIds;
    lastRound2Ids = round2TopicIds;
    lastRound3Ids = round3TopicIds;
    lastFinalIds = finalTopicIds;
    return builtPackageResult;
  }

  @override
  Future<TopicSummary> rerollTopic(int packageId, int topicId) async {
    rerollCalls++;
    return TopicSummary(id: topicId, idx: 1, name: 'შემთხვევითი თემა R');
  }

  @override
  Future<TopicSummary> replaceTopic(int packageId, int topicId, int sourceTopicId) async {
    replaceCalls++;
    final source = availableTopicsList.firstWhere(
      (t) => t.id == sourceTopicId,
      orElse: () => AvailableTopic(
        id: sourceTopicId,
        name: 'ახალი თემა',
        roundIdx: 1,
        finalRound: false,
        packageTitle: 'პაკეტი 1',
      ),
    );
    return TopicSummary(id: topicId, idx: 1, name: source.name);
  }
}

void main() {
  final fakeTopics = [
    AvailableTopic(id: 101, name: 'საქართველოს ისტორია', roundIdx: 1, finalRound: false, packageTitle: 'პაკეტი 1'),
    AvailableTopic(id: 102, name: 'გეოგრაფია', roundIdx: 1, finalRound: false, packageTitle: 'პაკეტი 1'),
    AvailableTopic(id: 103, name: 'ქართული კინო', roundIdx: 1, finalRound: false, packageTitle: 'პაკეტი 1'),
    AvailableTopic(id: 201, name: 'მსოფლიო ლიტერატურა', roundIdx: 2, finalRound: false, packageTitle: 'პაკეტი 1'),
    AvailableTopic(id: 202, name: 'ასტრონომია', roundIdx: 2, finalRound: false, packageTitle: 'პაკეტი 1'),
    AvailableTopic(id: 301, name: 'მითოლოგია', roundIdx: 3, finalRound: false, packageTitle: 'პაკეტი 1'),
    AvailableTopic(id: 401, name: 'ფინალური საიდუმლო', roundIdx: 4, finalRound: true, packageTitle: 'პაკეტი 1'),
  ];

  final fakeBuiltPackage = PackageSummary(
    id: 9999,
    number: -1,
    title: 'მორგებული პაკეტი #1',
    subtitle: 'ხელით აწყობილი პაკეტი',
    sourceUrl: null,
    synthetic: true,
    rounds: [
      RoundSummary(
        id: 1,
        idx: 1,
        finalRound: false,
        playable: true,
        topicCount: 6,
        topics: [
          TopicSummary(id: 101, idx: 1, name: 'საქართველოს ისტორია'),
          TopicSummary(id: 102, idx: 2, name: 'გეოგრაფია'),
          TopicSummary(id: 103, idx: 3, name: 'ქართული კინო'),
          TopicSummary(id: 104, idx: 4, name: 'მუსიკა'),
          TopicSummary(id: 105, idx: 5, name: 'სპორტი'),
          TopicSummary(id: 106, idx: 6, name: 'თეატრი'),
        ],
      ),
      RoundSummary(
        id: 2,
        idx: 2,
        finalRound: false,
        playable: true,
        topicCount: 6,
        topics: [
          TopicSummary(id: 201, idx: 1, name: 'მსოფლიო ლიტერატურა'),
          TopicSummary(id: 202, idx: 2, name: 'ასტრონომია'),
          TopicSummary(id: 203, idx: 3, name: 'ქიმია'),
          TopicSummary(id: 204, idx: 4, name: 'ფიზიკა'),
          TopicSummary(id: 205, idx: 5, name: 'ბიოლოგია'),
          TopicSummary(id: 206, idx: 6, name: 'მხატვრობა'),
        ],
      ),
      RoundSummary(
        id: 3,
        idx: 3,
        finalRound: false,
        playable: true,
        topicCount: 6,
        topics: [
          TopicSummary(id: 301, idx: 1, name: 'მითოლოგია'),
          TopicSummary(id: 302, idx: 2, name: 'ფილოსოფია'),
          TopicSummary(id: 303, idx: 3, name: 'არქიტექტურა'),
          TopicSummary(id: 304, idx: 4, name: 'ეკონომიკა'),
          TopicSummary(id: 305, idx: 5, name: 'კულინარია'),
          TopicSummary(id: 306, idx: 6, name: 'ავტომობილები'),
        ],
      ),
      RoundSummary(
        id: 4,
        idx: 4,
        finalRound: true,
        playable: false,
        topicCount: 2,
        topics: [
          TopicSummary(id: 401, idx: 1, name: 'ფინალური საიდუმლო'),
          TopicSummary(id: 402, idx: 2, name: 'ფინალური რებუსი'),
        ],
      ),
    ],
  );

  void setScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget builderApp(RestClient client) => ProviderScope(
        overrides: [
          restClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: const PackageBuilderScreen(),
        ),
      );

  testWidgets('step by step round topic selection and search filtering', (tester) async {
    setScreen(tester);
    final client = _FakeBuilderClient(
      availableTopicsList: fakeTopics,
      builtPackageResult: fakeBuiltPackage,
    );

    await tester.pumpWidget(builderApp(client));
    await tester.pumpAndSettle();

    // Verify round 1 topics are displayed
    expect(find.text('საქართველოს ისტორია'), findsOneWidget);
    expect(find.text('გეოგრაფია'), findsOneWidget);
    expect(find.text('ქართული კინო'), findsOneWidget);

    // Search for 'ისტორია'
    await tester.enterText(find.byType(TextField).first, 'ისტორია');
    await tester.pumpAndSettle();

    expect(find.text('საქართველოს ისტორია'), findsOneWidget);
    expect(find.text('გეოგრაფია'), findsNothing);

    // Clear search
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    expect(find.text('გეოგრაფია'), findsOneWidget);

    // Tap to select topic 101
    await tester.tap(find.text('საქართველოს ისტორია'));
    await tester.pumpAndSettle();

    // 1 topic selected in round 1
    expect(find.textContaining('1/6 არჩეული'), findsOneWidget);

    // Move to Round 2
    await tester.tap(find.widgetWithText(FilledButton, L.nextRound));
    await tester.pumpAndSettle();

    expect(find.textContaining('0/6 არჩეული'), findsOneWidget);
    expect(find.text('მსოფლიო ლიტერატურა'), findsOneWidget);
  });

  testWidgets('fill rest randomly at any moment builds package and opens overview', (tester) async {
    setScreen(tester);
    final client = _FakeBuilderClient(
      availableTopicsList: fakeTopics,
      builtPackageResult: fakeBuiltPackage,
    );

    await tester.pumpWidget(builderApp(client));
    await tester.pumpAndSettle();

    // Select 1 topic in round 1
    await tester.tap(find.text('საქართველოს ისტორია'));
    await tester.pumpAndSettle();

    // Click "დანარჩენის რენდომად შევსება"
    await tester.tap(find.widgetWithText(TextButton, L.fillRestRandomly));
    await tester.pumpAndSettle();

    expect(client.buildCalls, 1);
    expect(client.lastRound1Ids, [101]);

    // Should now be on Overview screen ("პაკეტის მიმოხილვა")
    expect(find.text(fakeBuiltPackage.title), findsOneWidget);
    expect(find.text(L.packageOverviewHint), findsOneWidget);

    // All rounds and topics are visible
    expect(find.text('საქართველოს ისტორია'), findsOneWidget);
    expect(find.text('გეოგრაფია'), findsOneWidget);
    expect(find.text('ქართული კინო'), findsOneWidget);

    // Test rerolling a topic in overview
    await tester.tap(find.byTooltip(L.randomizeThisTopic).first);
    await tester.pumpAndSettle();

    expect(client.rerollCalls, 1);
    expect(find.text('შემთხვევითი თემა R'), findsOneWidget);
  });

  testWidgets('replace topic in overview opens search and updates topic', (tester) async {
    setScreen(tester);
    final client = _FakeBuilderClient(
      availableTopicsList: fakeTopics,
      builtPackageResult: fakeBuiltPackage,
    );

    await tester.pumpWidget(builderApp(client));
    await tester.pumpAndSettle();

    // Build package directly
    await tester.tap(find.widgetWithText(TextButton, L.fillRestRandomly));
    await tester.pumpAndSettle();

    // Tap replace on first topic
    await tester.tap(find.byTooltip(L.replaceWithSpecific).first);
    await tester.pumpAndSettle();

    // Dialog should open
    expect(find.text(L.chooseFromLibrary), findsOneWidget);

    // Pick 'გეოგრაფია'
    await tester.tap(find.text('გეოგრაფია').last);
    await tester.pumpAndSettle();

    expect(client.replaceCalls, 1);
  });

  testWidgets('host setup screen displays package builder card and opens builder', (tester) async {
    setScreen(tester);
    final client = _FakeBuilderClient(
      availableTopicsList: fakeTopics,
      builtPackageResult: fakeBuiltPackage,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          packagesProvider.overrideWith((ref) => [
                PackageSummary(
                  id: 1,
                  number: 1,
                  title: 'პაკეტი 1',
                  subtitle: '2008 წელი',
                  sourceUrl: null,
                  rounds: [],
                ),
              ]),
          restClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: const HostSetupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(L.buildPackage), findsOneWidget);
    expect(find.text(L.randomPackage), findsOneWidget);

    // Tap on package builder card
    await tester.tap(find.text(L.buildPackage));
    await tester.pumpAndSettle();

    expect(find.text(L.buildPackageTitle), findsOneWidget);
  });
}
