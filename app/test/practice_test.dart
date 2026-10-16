@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeopard_app/core/providers.dart';
import 'package:jeopard_app/core/rest_client.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/practice/practice_screen.dart';
import 'package:jeopard_app/role_screen.dart';

/// Practice: random cards, the answer only on request, and a tally of what
/// the player says they knew.
void main() {
  Map<String, dynamic> card(int id) => {
    'id': id,
    'topicName': 'ისტორია',
    'value': 40,
    'finalRound': false,
    'question': 'შეკითხვა $id',
    'answer': 'პასუხი $id',
    'correctionNote': null,
    'packageTitle': 'პაკეტი #7',
  };

  /// How many batches the screen asked for.
  var fetches = 0;

  /// Each fetch deals the next [perBatch] ids, except that every batch also
  /// repeats card 1 -- which the screen must not deal twice.
  Widget app(Widget home, {int perBatch = 3}) {
    fetches = 0;
    final client = MockClient((request) async {
      expect(request.url.path, '/api/practice/questions');
      final first = fetches * perBatch + 1;
      fetches++;
      return http.Response(
        jsonEncode({
          'questions': [
            card(1),
            for (var i = first; i < first + perBatch; i++)
              if (i != 1) card(i),
          ],
          'attribution': 'moazrovne.net',
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    return ProviderScope(
      overrides: [
        restClientProvider.overrideWithValue(RestClient(client: client)),
      ],
      child: MaterialApp(theme: buildTheme(), home: home),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  void useSize(WidgetTester tester) {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(400, 800) * 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('the start screen opens practice straight onto a question', (
    tester,
  ) async {
    useSize(tester);
    await tester.pumpWidget(app(const RoleScreen()));
    await settle(tester);

    await tester.tap(find.text(L.practiceHint));
    await settle(tester);
    expect(find.text('შეკითხვა 1'), findsOneWidget);
    expect(find.text(L.showAnswer), findsOneWidget);
  });

  testWidgets('the answer waits to be asked for, then the player rules', (
    tester,
  ) async {
    useSize(tester);
    await tester.pumpWidget(app(const PracticeScreen()));
    await settle(tester);

    expect(find.text('შეკითხვა 1'), findsOneWidget);
    expect(find.text('პასუხი 1'), findsNothing);
    expect(find.text(L.practiceKnew), findsNothing);

    await tester.tap(find.text(L.showAnswer));
    await settle(tester);
    expect(find.text('პასუხი 1'), findsOneWidget);

    await tester.tap(find.text(L.practiceKnew));
    await settle(tester);
    expect(find.text('შეკითხვა 2'), findsOneWidget);
    expect(find.text('პასუხი 2'), findsNothing);

    await tester.tap(find.text(L.showAnswer));
    await settle(tester);
    await tester.tap(find.text(L.practiceDidNotKnow));
    await settle(tester);

    // One known, one not, in the tally.
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('1')),
      findsNWidgets(2),
    );
  });

  testWidgets('cards keep coming, and none is dealt twice', (tester) async {
    useSize(tester);
    await tester.pumpWidget(app(const PracticeScreen()));
    await settle(tester);

    final dealt = <String>[];
    for (var i = 0; i < 8; i++) {
      final shown = tester
          .widgetList<Text>(find.textContaining('შეკითხვა '))
          .single
          .data!;
      dealt.add(shown);
      await tester.tap(find.text(L.practiceSkip));
      await settle(tester);
    }
    expect(dealt.toSet(), hasLength(dealt.length));
    expect(fetches, greaterThan(1));
  });

  testWidgets('on a keyboard: space shows the answer, 1 and 2 rule', (
    tester,
  ) async {
    useSize(tester);
    await tester.pumpWidget(app(const PracticeScreen()));
    await settle(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settle(tester);
    expect(find.text('პასუხი 1'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await settle(tester);
    expect(find.text('შეკითხვა 2'), findsOneWidget);
    expect(find.text('პასუხი 2'), findsNothing);
  });
}
