import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeopard_app/core/models.dart';
import 'package:jeopard_app/core/theme.dart';
import 'package:jeopard_app/widgets/scoreboard.dart';

/// Several people can share a team: the team scores, the player buzzes.
void main() {
  group('parsing teams with members', () {
    Map<String, dynamic> teamJson({
      required String id,
      required String name,
      int score = 0,
      List<Map<String, dynamic>> players = const [],
      bool lockedOut = false,
    }) =>
        {
          'id': id,
          'name': name,
          'score': score,
          'host': false,
          'seat': 1,
          'wager': null,
          'lockedOutOnCurrentClue': lockedOut,
          'players': players,
        };

    test('a team carries its members', () {
      final team = TeamView.fromJson(teamJson(
        id: 't1',
        name: 'მთიები',
        score: 40,
        players: [
          {'id': 'p1', 'name': 'ნინო', 'host': false},
          {'id': 'p2', 'name': 'გიორგი', 'host': false},
        ],
      ));

      expect(team.players, hasLength(2));
      expect(team.players.map((p) => p.name), ['ნინო', 'გიორგი']);
      expect(team.players.every((p) => p.host), isFalse);
    });

    test('a team with no members list still parses', () {
      final team = TeamView.fromJson(teamJson(id: 't1', name: 'მარტო'));
      expect(team.players, isEmpty);
    });

    test('the snapshot reports which player buzzed, not just the team', () {
      final snap = Snapshot.fromJson({
        'gameId': 'g1',
        'joinCode': 'ABC234',
        'state': 'BUZZED',
        'hostPlays': false,
        'roundId': 1,
        'roundIdx': 1,
        'finalRound': false,
        'progressRounds': true,
        'packageNumber': 1,
        'packageTitle': 'პაკეტი #1',
        'teams': [
          teamJson(id: 't1', name: 'მთიები', players: [
            {'id': 'p1', 'name': 'ნინო', 'host': false},
            {'id': 'p2', 'name': 'გიორგი', 'host': false},
          ]),
        ],
        'board': const [],
        'currentClue': null,
        'buzzedTeamId': 't1',
        'buzzedPlayerId': 'p2',
        'pickingTeamId': null,
        'answerRevealed': false,
        'answerPeeked': false,
        'tilesRemaining': 29,
        'seq': 5,
        'attribution': 'moazrovne.net',
      });

      expect(snap.buzzedTeamId, 't1');
      expect(snap.buzzedPlayerId, 'p2');
      // The person is resolvable from the team, which is how the host knows
      // who to listen to.
      final team = snap.teamById(snap.buzzedTeamId)!;
      final who = team.players.firstWhere((p) => p.id == snap.buzzedPlayerId);
      expect(who.name, 'გიორგი');
    });

    test('joining returns a player token, not a team token', () {
      final joined = JoinedPlayer.fromJson({
        'gameId': 'g1',
        'playerId': 'p9',
        'playerToken': 'tok-abc',
        'playerName': 'ნინო',
        'teamId': 't1',
        'teamName': 'მთიები',
        'seat': 2,
      });

      expect(joined.playerToken, 'tok-abc');
      expect(joined.playerName, 'ნინო');
      expect(joined.teamName, 'მთიები');
    });

    test('the lobby lists teams and their members for the join screen', () {
      final lobby = LobbyView.fromJson({
        'gameId': 'g1',
        'joinCode': 'ABC234',
        'state': 'LOBBY',
        'teams': [
          {
            'id': 't1',
            'name': 'მთიები',
            'seat': 1,
            'score': 0,
            'memberNames': ['ნინო', 'გიორგი'],
          },
          {
            'id': 't2',
            'name': 'ვეფხვები',
            'seat': 2,
            'score': 0,
            'memberNames': ['ლევანი'],
          },
        ],
      });

      expect(lobby.state, GameState.lobby);
      expect(lobby.teams, hasLength(2));
      expect(lobby.teams.first.memberNames, ['ნინო', 'გიორგი']);
      expect(lobby.teams.last.memberNames, ['ლევანი']);
    });
  });

  group('Scoreboard with shared teams', () {
    Widget host(Widget child) => MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: child),
        );

    TeamView team(String name, List<String> members) => TeamView(
          id: name,
          name: name,
          score: 0,
          host: false,
          seat: 1,
          wager: null,
          lockedOut: false,
          players: [
            for (final m in members)
              PlayerView(id: '$name-$m', name: m, host: false),
          ],
        );

    testWidgets('says how many members a shared team has', (tester) async {
      await tester.pumpWidget(host(Scoreboard(teams: [
        team('მთიები', const ['ნინო', 'გიორგი', 'ანა']),
      ])));

      expect(find.text('3 ${L.members}'), findsOneWidget);
    });

    testWidgets('stays quiet for a one-person team', (tester) async {
      await tester.pumpWidget(host(Scoreboard(teams: [
        team('მარტო', const ['ნინო']),
      ])));

      expect(find.textContaining(L.members), findsNothing);
    });
  });
}
