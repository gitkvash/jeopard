import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeopard_app/core/models.dart';
import 'package:jeopard_app/core/providers.dart';
import 'package:jeopard_app/core/rest_client.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/role_screen.dart';
import 'package:jeopard_app/widgets/topic_suggestion_dialog.dart';

Widget host(Widget child, {Size size = const Size(900, 700), RestClient? client}) {
  return ProviderScope(
    overrides: [
      if (client != null) restClientProvider.overrideWithValue(client),
    ],
    child: MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: size.width, height: size.height, child: child),
        ),
      ),
    ),
  );
}

class FakeRestClient extends RestClient {
  String? suggestedTopicName;
  String? suggestedDescription;
  String? suggestedAuthorName;
  bool shouldThrow = false;

  @override
  Future<TopicSuggestionResult> suggestTopic({
    required String topicName,
    String? description,
    String? authorName,
  }) async {
    if (shouldThrow) {
      throw ApiException(429, 'ძალიან ბევრი შემოთავაზება');
    }
    suggestedTopicName = topicName;
    suggestedDescription = description;
    suggestedAuthorName = authorName;
    return const TopicSuggestionResult(
      status: 'ok',
      message: 'მადლობა! თემის შემოთავაზება მიღებულია.',
    );
  }
}

void main() {
  testWidgets('TopicSuggestionDialog renders title, fields, and buttons', (tester) async {
    await tester.pumpWidget(host(
      const TopicSuggestionDialog(),
      client: FakeRestClient(),
    ));
    await tester.pumpAndSettle();

    expect(find.text(L.suggestTopicTitle), findsOneWidget);
    expect(find.text(L.topicNameField), findsOneWidget);
    expect(find.text(L.topicDescField), findsOneWidget);
    expect(find.text(L.topicAuthorField), findsOneWidget);
    expect(find.text(L.topicSubmit), findsOneWidget);
    expect(find.text(L.topicCancel), findsOneWidget);
  });

  testWidgets('validation error when topic name is less than 2 characters', (tester) async {
    await tester.pumpWidget(host(
      const TopicSuggestionDialog(),
      client: FakeRestClient(),
    ));
    await tester.pumpAndSettle();

    // Leave topic name empty and tap submit
    await tester.tap(find.text(L.topicSubmit));
    await tester.pumpAndSettle();

    expect(find.text(L.topicErrorMinLength), findsOneWidget);

    // Enter single character and tap submit
    await tester.enterText(find.byType(TextField).first, 'ა');
    await tester.tap(find.text(L.topicSubmit));
    await tester.pumpAndSettle();

    expect(find.text(L.topicErrorMinLength), findsOneWidget);
  });

  testWidgets('successful submission calls suggestTopic and dismisses dialog', (tester) async {
    final fakeClient = FakeRestClient();
    await tester.pumpWidget(host(
      const TopicSuggestionDialog(),
      client: fakeClient,
    ));
    await tester.pumpAndSettle();

    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(3));

    // Field 0: Topic Name
    await tester.enterText(textFields.at(0), 'ქართული როკი');
    // Field 1: Description
    await tester.enterText(textFields.at(1), 'ვაკის პარკი, 33ა, პრესტიჟი...');
    // Field 2: Author Name
    await tester.enterText(textFields.at(2), 'გიორგი');

    await tester.tap(find.text(L.topicSubmit));
    await tester.pumpAndSettle();

    expect(fakeClient.suggestedTopicName, 'ქართული როკი');
    expect(fakeClient.suggestedDescription, 'ვაკის პარკი, 33ა, პრესტიჟი...');
    expect(fakeClient.suggestedAuthorName, 'გიორგი');
    expect(find.byType(TopicSuggestionDialog), findsNothing);
  });

  testWidgets('displays server error message on failure', (tester) async {
    final fakeClient = FakeRestClient()..shouldThrow = true;
    await tester.pumpWidget(host(
      const TopicSuggestionDialog(),
      client: fakeClient,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'ქართული როკი');
    await tester.tap(find.text(L.topicSubmit));
    await tester.pumpAndSettle();

    expect(find.text('ძალიან ბევრი შემოთავაზება'), findsOneWidget);
    expect(find.byType(TopicSuggestionDialog), findsOneWidget);
  });

  testWidgets('RoleScreen renders topic suggestion card and opens dialog on tap', (tester) async {
    final fakeClient = FakeRestClient();
    await tester.pumpWidget(host(
      const RoleScreen(),
      client: fakeClient,
    ));
    await tester.pumpAndSettle();

    // Verify suggest topic card exists
    final suggestCard = find.text(L.suggestTopic);
    expect(suggestCard, findsOneWidget);
    expect(find.text(L.suggestTopicHint), findsOneWidget);

    // Tap the card
    await tester.tap(suggestCard);
    await tester.pumpAndSettle();

    // Verify dialog opened
    expect(find.byType(TopicSuggestionDialog), findsOneWidget);
    expect(find.text(L.suggestTopicTitle), findsOneWidget);
  });
}
