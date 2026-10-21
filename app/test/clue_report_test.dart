import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeopard_app/core/models.dart';
import 'package:jeopard_app/core/rest_client.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/widgets/clue_panel.dart';
import 'package:jeopard_app/widgets/clue_report_dialog.dart';

Widget host(Widget child, {Size size = const Size(900, 700)}) {
  return MaterialApp(
    theme: buildTheme(),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );
}

class FakeRestClient extends RestClient {
  int? reportedClueId;
  String? reportedDescription;
  bool shouldThrow = false;

  @override
  Future<ReportResult> reportClue(int clueId, String description) async {
    if (shouldThrow) {
      throw ApiException(429, 'ძალიან ბევრი რეპორტი');
    }
    reportedClueId = clueId;
    reportedDescription = description;
    return const ReportResult(status: 'ok', message: 'რეპორტი მიღებულია');
  }
}

void main() {
  final sampleClue = CurrentClue(
    clueId: 42,
    topicName: 'გეოგრაფია',
    value: 50,
    question: 'რომელია ყველაზე ღრმა ტბა?',
    answer: 'ბაიკალი',
    correctionNote: null,
    lockedOutTeamIds: const [],
  );

  testWidgets('CluePanel renders report button', (tester) async {
    await tester.pumpWidget(host(CluePanel(clue: sampleClue)));
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
  });

  testWidgets('tapping report button opens ClueReportDialog', (tester) async {
    await tester.pumpWidget(host(CluePanel(clue: sampleClue)));
    await tester.tap(find.byIcon(Icons.flag_outlined));
    await tester.pumpAndSettle();

    expect(find.text(L.reportClueTitle), findsOneWidget);
    expect(find.text(L.reportClueSubmit), findsOneWidget);
    expect(find.text(L.reportClueCancel), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('validation error when description is under 5 characters',
      (tester) async {
    await tester.pumpWidget(host(
      ClueReportDialog(clue: sampleClue, client: FakeRestClient()),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ვაი');
    await tester.tap(find.text(L.reportClueSubmit));
    await tester.pumpAndSettle();

    expect(find.text(L.reportClueErrorMinLength), findsOneWidget);
  });

  testWidgets('successful submission calls reportClue and pops dialog',
      (tester) async {
    final fakeClient = FakeRestClient();
    await tester.pumpWidget(host(
      ClueReportDialog(clue: sampleClue, client: fakeClient),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField), 'კითხვაში შეცდომაა, ბაიკალი არაა');
    await tester.tap(find.text(L.reportClueSubmit));
    await tester.pumpAndSettle();

    expect(fakeClient.reportedClueId, 42);
    expect(fakeClient.reportedDescription, 'კითხვაში შეცდომაა, ბაიკალი არაა');
    expect(find.byType(ClueReportDialog), findsNothing);
  });

  testWidgets('displays server error message on failure', (tester) async {
    final fakeClient = FakeRestClient()..shouldThrow = true;
    await tester.pumpWidget(host(
      ClueReportDialog(clue: sampleClue, client: fakeClient),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'შემოწმება შეცდომის');
    await tester.tap(find.text(L.reportClueSubmit));
    await tester.pumpAndSettle();

    expect(find.text('ძალიან ბევრი რეპორტი'), findsOneWidget);
  });
}
