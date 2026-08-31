import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/poll_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> pollJson({
  String name = 'poll',
  String type = 'regular',
  List<Map<String, Object?>>? options,
}) => {
  'id': 7,
  'name': name,
  'type': type,
  'status': 'open',
  'public': true,
  'dynamic': true,
  'results': 'on_vote',
  'min': 1,
  'max': 2,
  'step': 1,
  'options':
      options ??
      [
        {'id': 'a', 'html': '<strong>A</strong>', 'votes': 2},
        {'id': 'b', 'html': 'B'},
      ],
  'voters': 2,
  'close': '2030-01-02T03:04:05.000Z',
  'preloaded_voters': {
    'a': [
      {'id': 1, 'username': 'alice'},
    ],
  },
  'chart_type': 'pie',
  'groups': 'members, staff',
  'title': '<em>Choose</em>',
  'ranked_choice_outcome': {
    'tied': false,
    'winner': true,
    'winning_candidate': {'digest': 'a', 'html': 'A'},
    'tied_candidates': null,
    'round_activity': [
      {
        'round': 1,
        'majority': {'digest': 'a', 'html': 'A'},
        'eliminated': null,
      },
    ],
  },
  'closed_at': '2029-01-02T03:04:05.000Z',
  'closed_by': {
    'id': 9,
    'username': 'mod',
    'name': 'Moderator',
    'avatar_template': '/user_avatar/forum.example/mod/{size}/1.png',
  },
};

void main() {
  group('poll domain', () {
    test('absent plugin key stays absent', () {
      expect(Polls.fromJson(const {}, 'https://forum.example'), isNull);
    });

    test('parses named polls, metadata, lifecycle, and reader selections', () {
      final polls = Polls.fromJson({
        'polls': [
          pollJson(name: 'lunch', type: 'multiple'),
          pollJson(name: 'time', type: 'number'),
        ],
        'polls_votes': {
          'lunch': ['a', 'b'],
          'time': ['b'],
        },
      }, 'https://forum.example')!;

      expect(polls.byName.keys, ['lunch', 'time']);
      final poll = polls['lunch']!;
      expect(poll.id, 7);
      expect(poll.type, PollType.multiple);
      expect(poll.status, PollStatus.open);
      expect(poll.results, PollResults.onVote);
      expect(poll.isPublic, isTrue);
      expect(poll.isDynamic, isTrue);
      expect((poll.min, poll.max, poll.step), (1, 2, 1));
      expect(poll.options.first.html, '<strong>A</strong>');
      expect(poll.options.first.votes, 2);
      expect(poll.options.last.votes, isNull);
      expect(poll.voters, 2);
      expect(poll.closeAt, DateTime.utc(2030, 1, 2, 3, 4, 5));
      expect(poll.chartType, PollChartType.pie);
      expect(poll.groups, ['members', 'staff']);
      expect(poll.title, '<em>Choose</em>');
      expect(poll.closedAt, DateTime.utc(2029, 1, 2, 3, 4, 5));
      expect(poll.closedBy?.username, 'mod');
      expect(poll.rankedChoiceOutcome?.winningCandidate?.digest, 'a');
      expect(poll.rankedChoiceOutcome?.rounds.single.round, 1);
      expect(poll.selection.optionIds, ['a', 'b']);
      expect(poll.preloadedVoters, {
        'a': [
          {'id': 1, 'username': 'alice'},
        ],
      });
    });

    test('unknown future poll values remain a read-only record', () {
      final poll = Poll.fromJson({
        ...pollJson(type: 'quadratic'),
        'status': 'paused',
        'results': 'after_quorum',
        'chart_type': 'donut',
      }, 'https://forum.example')!;

      expect(poll.type.value, 'quadratic');
      expect(poll.type.isKnown, isFalse);
      expect(poll.status.value, 'paused');
      expect(poll.results.value, 'after_quorum');
      expect(poll.chartType.value, 'donut');
      expect(poll.supportsNativeVoting, isFalse);
    });

    test('ranked reader selections retain digest and rank', () {
      final poll = Poll.fromJson(
        pollJson(type: 'ranked_choice'),
        'https://forum.example',
        selection: [
          {'digest': 'a', 'rank': 2},
          {'digest': 'b', 'rank': 1},
        ],
      )!;

      expect(poll.selection.rankedChoices, const [
        RankedPollSelection(digest: 'a', rank: 2),
        RankedPollSelection(digest: 'b', rank: 1),
      ]);
    });

    test('bounds option parsing to the server setting ceiling', () {
      final options = <Object?>[
        // Raw response slots consume the server-sized budget. This keeps all
        // parsing work bounded even when a nonconforming response is corrupt.
        null,
        for (var index = 0; index < Poll.maximumOptions; index++)
          {'id': 'option-$index', 'html': '<strong>Option $index</strong>'},
      ];
      final poll = Poll.fromJson({
        ...pollJson(),
        'options': options,
      }, 'https://forum.example')!;

      expect(poll.options, hasLength(Poll.maximumOptions - 1));
      expect(poll.options.first.id, 'option-0');
      expect(poll.options.last.id, 'option-98');
      expect(
        () => poll.options.add(const PollOption(id: 'extra', html: 'Extra')),
        throwsUnsupportedError,
      );
    });
  });

  group('PollsApi', () {
    test(
      'PUT sends exact vote body and parses personalized response',
      () async {
        late http.Request sent;
        final api = DiscourseApi(
          client: MockClient((request) async {
            sent = request;
            return http.Response(
              jsonEncode({
                'poll': pollJson(name: 'lunch', type: 'multiple'),
                'vote': ['a', 'b'],
              }),
              200,
            );
          }),
        );

        final response = await PollApi(api).votePoll(
          siteUrl: 'https://forum.example',
          apiKey: 'secret',
          postId: 42,
          pollName: 'lunch',
          options: const ['a', 'b'],
        );

        expect(sent.method, 'PUT');
        expect(sent.url.path, '/polls/vote.json');
        expect(jsonDecode(sent.body), {
          'post_id': 42,
          'poll_name': 'lunch',
          'options': ['a', 'b'],
        });
        expect(response.poll.name, 'lunch');
        expect(response.selection.optionIds, ['a', 'b']);
        expect(response.poll.selection, response.selection);
      },
    );

    test('DELETE sends exact body and returns an empty selection', () async {
      late http.Request sent;
      final api = DiscourseApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({'poll': pollJson(name: 'lunch')}),
            200,
          );
        }),
      );

      final response = await PollApi(api).removePollVote(
        siteUrl: 'https://forum.example',
        apiKey: 'secret',
        postId: 42,
        pollName: 'lunch',
      );

      expect(sent.method, 'DELETE');
      expect(sent.url.path, '/polls/vote.json');
      expect(jsonDecode(sent.body), {'post_id': 42, 'poll_name': 'lunch'});
      expect(response.selection, PollSelection.none);
      expect(response.poll.selection, PollSelection.none);
    });

    test('malformed personalized success fails safely', () async {
      final api = DiscourseApi(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'poll': pollJson(name: 'somebody-else'),
              'vote': <String>[],
            }),
            200,
          ),
        ),
      );

      expect(
        PollApi(api).votePoll(
          siteUrl: 'https://forum.example',
          apiKey: 'secret',
          postId: 42,
          pollName: 'lunch',
          options: const ['a'],
        ),
        throwsA(
          isA<WriteException>().having(
            (error) => error.failure,
            'failure',
            WriteFailure.unreachable,
          ),
        ),
      );
    });
  });
}
