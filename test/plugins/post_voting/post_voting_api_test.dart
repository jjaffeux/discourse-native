import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_api.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_data.dart';
import 'package:discourse_plugin_api/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://forum.example/discuss';
const _credentials = PluginRequestCredentials(
  apiKey: 'key',
  clientId: 'client',
);

void main() {
  test(
    'ranked metadata cannot replace held chronological stream membership',
    () async {
      final transport = RecordingPluginTransport(
        responses: {'GET /t/7.json': _topic()},
      );
      final result =
          await PostVotingApi(
            transport,
            const DiscourseModelCodec.core(),
          ).loadWindow(
            siteUrl: _site,
            topicId: 7,
            order: PostVotingOrder.votes,
            credentials: _credentials,
            heldTopic: const TopicDetail(
              id: 7,
              title: 'Held',
              stream: [101, 102, 103],
            ),
          );
      expect(result.orderedStreamIds, [101, 103, 102]);
      expect(result.metadata.stream, [101, 102, 103]);
    },
  );

  test('post link lookup returns only validated parent location', () async {
    final transport = RecordingPluginTransport(
      responses: {
        'GET /posts/101.json': {
          'id': 101,
          'topic_id': 7,
          'post_number': 3,
          'topic_slug': 'the-question',
          'cooked': '<p>Standalone body is not ingested</p>',
        },
      },
    );
    final api = PostVotingApi(transport, const DiscourseModelCodec.core());
    final result = await api.lookupPost(
      siteUrl: _site,
      postId: 101,
      credentials: _credentials,
    );
    expect(result.topicId, 7);
    expect(result.postNumber, 3);
    expect(result.slug, 'the-question');
    transport.responses['GET /posts/101.json'] = {
      'id': 102,
      'topic_id': 7,
      'post_number': 3,
    };
    await expectLater(
      api.lookupPost(siteUrl: _site, postId: 101, credentials: _credentials),
      throwsFormatException,
    );
  });

  test(
    'authenticated comment remainder settles a nullable absent upvote as false',
    () async {
      final wire = _comment(1)..['user_voted'] = null;
      final transport = RecordingPluginTransport(
        responses: {
          'GET /post_voting/comments.json?post_id=101&last_comment_id=0': {
            'comments': [wire],
          },
        },
      );
      final result = await PostVotingApi(
        transport,
        const DiscourseModelCodec.core(),
      ).comments(siteUrl: _site, postId: 101, credentials: _credentials);
      expect(result.comments.single.myUpvote, isFalse);
    },
  );

  test(
    'ranked window keeps server stream order and settles absent own vote',
    () async {
      final transport = RecordingPluginTransport(
        responses: {'GET /t/7.json': _topic()},
      );
      final result =
          await PostVotingApi(
            transport,
            const DiscourseModelCodec.core(),
          ).loadWindow(
            siteUrl: _site,
            topicId: 7,
            order: PostVotingOrder.votes,
            credentials: _credentials,
          );
      expect(result.orderedStreamIds, [101, 103, 102]);
      expect(result.posts.map((post) => post.post.id), [101, 103]);
      expect(result.metadata.plugins.get(postVotingTopicKey)!.enabled, isTrue);
      final vote = result.posts.last.post.plugins.get(postVotingPostKey)!;
      expect(vote.score, -1);
      expect(vote.myVote, isNull);
      expect(vote.myVoteKnown, isTrue);
      expect(transport.reads.single.siteUrl, _site);
      expect(transport.reads.single.apiKey, 'key');
      expect(transport.reads.single.clientId, 'client');
    },
  );

  test(
    'activity and numbered windows use explicit server query parameters',
    () async {
      final transport = RecordingPluginTransport(
        responders: {
          'GET /t/7.json?filter=activity&post_number=3&page=2': (_) => _topic(),
        },
      );
      await PostVotingApi(
        transport,
        const DiscourseModelCodec.core(),
      ).loadWindow(
        siteUrl: _site,
        topicId: 7,
        order: PostVotingOrder.activity,
        nearPostNumber: 3,
        page: 2,
        credentials: _credentials,
      );
      expect(Uri.parse(transport.reads.single.path).queryParameters, {
        'filter': 'activity',
        'post_number': '3',
        'page': '2',
      });
    },
  );

  test(
    'post chunks reject foreign identities and preserve requested ID order',
    () async {
      final transport = RecordingPluginTransport(
        responses: {
          'GET /t/7/posts.json?post_ids[]=102&post_ids[]=103&filter=activity': {
            'post_stream': {
              'posts': [_post(103, 3), _post(102, 2)],
            },
          },
        },
      );
      final api = PostVotingApi(transport, const DiscourseModelCodec.core());
      final result = await api.loadPosts(
        siteUrl: _site,
        topicId: 7,
        postIds: [102, 103],
        order: PostVotingOrder.activity,
        credentials: _credentials,
      );
      expect(result.map((post) => post.post.id), [102, 103]);
      transport
          .responses['${transport.reads.single.method} ${transport.reads.single.path}'] = {
        'post_stream': {
          'posts': [_post(500, 3)],
        },
      };
      await expectLater(
        api.loadPosts(
          siteUrl: _site,
          topicId: 7,
          postIds: [102, 103],
          order: PostVotingOrder.activity,
          credentials: _credentials,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'all malformed or mismatched stream identities fail before admission',
    () async {
      for (final bad in [
        {..._topic(), 'id': 9},
        {
          ..._topic(),
          'post_stream': {
            'stream': [101, 101],
            'posts': [_post(101, 1)],
          },
        },
        {
          ..._topic(),
          'post_stream': {
            'stream': [101],
            'posts': [
              {..._post(101, 1), 'topic_id': 8},
            ],
          },
        },
        {
          ..._topic(),
          'post_stream': {
            'stream': [101],
            'posts': [_post(102, 2)],
          },
        },
      ]) {
        final transport = RecordingPluginTransport(
          responses: {'GET /t/7.json': bad},
        );
        await expectLater(
          PostVotingApi(transport, const DiscourseModelCodec.core()).loadWindow(
            siteUrl: _site,
            topicId: 7,
            order: PostVotingOrder.votes,
            credentials: _credentials,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'redacted post disposition cannot be mistaken for complete content',
    () async {
      final topic = _topic();
      topic['post_stream'] = {
        'stream': [101],
        'posts': [
          {
            'id': 101,
            'post_number': 1,
            'topic_id': 7,
            'deleted_post_placeholder': true,
          },
        ],
      };
      final transport = RecordingPluginTransport(
        responses: {'GET /t/7.json': topic},
      );
      final result =
          await PostVotingApi(
            transport,
            const DiscourseModelCodec.core(),
          ).loadWindow(
            siteUrl: _site,
            topicId: 7,
            order: PostVotingOrder.votes,
            credentials: _credentials,
          );
      expect(result.posts.single.disposition, TopicContentDisposition.redacted);
    },
  );

  test(
    'comments always supply cursor zero and return all server remainder',
    () async {
      final transport = RecordingPluginTransport(
        responses: {
          'GET /post_voting/comments.json?post_id=101&last_comment_id=0': {
            'comments': [_comment(1), _comment(3), _comment(4)],
          },
          'GET /post_voting/comments.json?post_id=101&last_comment_id=4': {
            'comments': [_comment(9)],
          },
        },
      );
      final api = PostVotingApi(transport, const DiscourseModelCodec.core());
      final initial = await api.comments(
        siteUrl: _site,
        postId: 101,
        credentials: _credentials,
      );
      expect(initial.comments.map((comment) => comment.id), [1, 3, 4]);
      expect(initial.lastCommentId, 4);
      expect(initial.remainderLoaded, isTrue);
      final more = await api.comments(
        siteUrl: _site,
        postId: 101,
        afterCommentId: 4,
        credentials: _credentials,
      );
      expect(more.comments.single.id, 9);
      expect(more.remainderLoaded, isTrue);
    },
  );

  test(
    'comment cursor response must increase and match the requested parent',
    () async {
      for (final bad in [
        [_comment(4)],
        [_comment(6), _comment(5)],
        [
          {..._comment(5), 'post_id': 102},
        ],
      ]) {
        final transport = RecordingPluginTransport(
          responses: {
            'GET /post_voting/comments.json?post_id=101&last_comment_id=4': {
              'comments': bad,
            },
          },
        );
        await expectLater(
          PostVotingApi(transport, const DiscourseModelCodec.core()).comments(
            siteUrl: _site,
            postId: 101,
            afterCommentId: 4,
            credentials: _credentials,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'voters retain signed directions and the unpageable remaining total',
    () async {
      final transport = RecordingPluginTransport(
        responses: {
          'GET /post_voting/voters.json?post_id=101': {
            'voters': [
              {'id': 8, 'username': 'sam', 'direction': 'down'},
              {'id': 9, 'username': 'maya', 'direction': 'up'},
            ],
            'total_voters_count': 25,
          },
        },
      );
      final result = await PostVotingApi(
        transport,
        const DiscourseModelCodec.core(),
      ).voters(siteUrl: _site, postId: 101, credentials: _credentials);
      expect(result.users.first.direction, PostVoteDirection.down);
      expect(result.users.last.direction, PostVoteDirection.up);
      expect(result.remaining, 23);
      transport.responses['GET /post_voting/voters.json?post_id=101'] = {
        'voters': List.generate(
          21,
          (index) => {
            'id': index + 1,
            'username': 'u$index',
            'direction': 'up',
          },
        ),
        'total_voters_count': 21,
      };
      await expectLater(
        PostVotingApi(
          transport,
          const DiscourseModelCodec.core(),
        ).voters(siteUrl: _site, postId: 101, credentials: _credentials),
        throwsFormatException,
      );
    },
  );

  test(
    'mutation verbs, bodies and acknowledgement-only returns match upstream',
    () async {
      final transport = RecordingPluginTransport(
        responses: {
          'POST /post_voting/vote.json': {'success': 'OK'},
          'DELETE /post_voting/vote.json': {'success': 'OK'},
          'POST /post_voting/vote/comment.json': {'success': 'OK'},
          'DELETE /post_voting/vote/comment.json': {'success': 'OK'},
          'DELETE /post_voting/comments.json': {'success': 'OK'},
          'PUT /post_voting/comments/flag.json': {'success': 'OK'},
        },
      );
      final api = PostVotingApi(transport, const DiscourseModelCodec.core());
      await api.votePost(
        siteUrl: _site,
        postId: 101,
        direction: PostVoteDirection.down,
        credentials: _credentials,
      );
      await api.undoPostVote(
        siteUrl: _site,
        postId: 101,
        credentials: _credentials,
      );
      await api.upvoteComment(
        siteUrl: _site,
        commentId: 1,
        credentials: _credentials,
      );
      await api.undoCommentVote(
        siteUrl: _site,
        commentId: 1,
        credentials: _credentials,
      );
      await api.deleteComment(
        siteUrl: _site,
        commentId: 1,
        credentials: _credentials,
      );
      await api.flagComment(
        siteUrl: _site,
        command: const PostVotingFlagCommand(
          commentId: 1,
          flagTypeId: 7,
          message: 'Please review',
          takeAction: true,
        ),
        credentials: _credentials,
      );
      expect(transport.writes.map((request) => request.body), [
        {'post_id': 101, 'direction': 'down'},
        {'post_id': 101},
        {'comment_id': 1},
        {'comment_id': 1},
        {'comment_id': 1},
        {
          'comment_id': 1,
          'flag_type_id': 7,
          'message': 'Please review',
          'is_warning': false,
          'take_action': true,
          'queue_for_review': false,
        },
      ]);
      expect(
        transport.writes.every(
          (request) => request.apiKey == 'key' && request.clientId == 'client',
        ),
        isTrue,
      );
    },
  );

  test(
    'comment creation and edit use unrooted returned cooked record',
    () async {
      final transport = RecordingPluginTransport(
        responses: {
          'POST /post_voting/comments.json': _comment(1),
          'PUT /post_voting/comments.json': {
            ..._comment(1),
            'raw': 'changed',
            'cooked': '<p>changed</p>',
          },
        },
      );
      final api = PostVotingApi(transport, const DiscourseModelCodec.core());
      final created = await api.createComment(
        siteUrl: _site,
        postId: 101,
        raw: 'raw',
        credentials: _credentials,
      );
      expect(created.id, 1);
      final edited = await api.editComment(
        siteUrl: _site,
        parentPostId: 101,
        commentId: 1,
        raw: 'changed',
        credentials: _credentials,
      );
      expect(edited.cooked, '<p>changed</p>');
      expect(transport.writes.map((request) => request.body), [
        {'post_id': 101, 'raw': 'raw'},
        {'comment_id': 1, 'raw': 'changed'},
      ]);
      transport.responses['PUT /post_voting/comments.json'] = _comment(2);
      await expectLater(
        api.editComment(
          siteUrl: _site,
          parentPostId: 101,
          commentId: 1,
          raw: 'changed',
          credentials: _credentials,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'missing credentials fail before transport and server errors stay localized',
    () async {
      final transport = RecordingPluginTransport(
        responses: {
          'POST /post_voting/vote.json': {
            'errors': ['Vote window expired'],
          },
        },
      );
      final api = PostVotingApi(transport, const DiscourseModelCodec.core());
      await expectLater(
        api.votePost(
          siteUrl: _site,
          postId: 101,
          direction: PostVoteDirection.up,
          credentials: const PluginRequestCredentials(
            apiKey: null,
            clientId: '',
          ),
        ),
        throwsA(
          isA<WriteException>().having(
            (error) => error.notSent,
            'notSent',
            isTrue,
          ),
        ),
      );
      expect(transport.requests, isEmpty);
      await expectLater(
        api.votePost(
          siteUrl: _site,
          postId: 101,
          direction: PostVoteDirection.up,
          credentials: _credentials,
        ),
        throwsA(
          isA<WriteException>().having((error) => error.errors, 'errors', [
            'Vote window expired',
          ]),
        ),
      );
    },
  );

  test(
    'every transport invocation stays inside the supplied account executor',
    () async {
      var admitted = 0;
      final credentials = PluginRequestCredentials(
        apiKey: 'old-account',
        clientId: 'client',
        execute: <T>(Future<T> Function() action) async {
          admitted++;
          return action();
        },
      );
      final transport = RecordingPluginTransport(
        responses: {
          'GET /post_voting/comments.json?post_id=101&last_comment_id=0': {
            'comments': <Object?>[],
          },
          'POST /post_voting/vote.json': {'success': 'OK'},
        },
      );
      final api = PostVotingApi(transport, const DiscourseModelCodec.core());
      await api.comments(siteUrl: _site, postId: 101, credentials: credentials);
      await api.votePost(
        siteUrl: _site,
        postId: 101,
        direction: PostVoteDirection.up,
        credentials: credentials,
      );
      expect(admitted, 2);
      expect(
        transport.requests.every((request) => request.apiKey == 'old-account'),
        isTrue,
      );
    },
  );
}

Map<String, dynamic> _topic() => {
  'id': 7,
  'title': 'Question',
  'is_post_voting': true,
  'answer_count': 2,
  'post_stream': {
    'stream': [101, 103, 102],
    'posts': [
      _post(101, 1),
      {..._post(103, 3), 'post_voting_vote_count': -1},
    ],
  },
};
Map<String, dynamic> _post(int id, int number) => {
  'id': id,
  'topic_id': 7,
  'post_number': number,
  'username': 'author',
  'cooked': '<p>Post</p>',
  'post_voting_vote_count': 0,
  'post_voting_has_votes': true,
  'comments': <Object?>[],
  'comments_count': 0,
};
Map<String, dynamic> _comment(int id) => {
  'id': id,
  'user_id': 8,
  'username': 'sam',
  'created_at': '2026-11-01T10:00:00Z',
  'raw': 'raw',
  'cooked': '<p>raw</p>',
  'post_voting_vote_count': 0,
  'user_voted': false,
  'available_flags': <String>[],
};
