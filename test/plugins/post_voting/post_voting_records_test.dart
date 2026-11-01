import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings retain unknown enablement and round-trip supplied limits', () {
    final value = PostVotingSettings.fromJson({
      'post_voting_comment_limit_per_post': 3,
      'post_voting_comment_max_raw_length': 240,
      'min_post_length': 8,
      'post_voting_enable_likes_on_answers': true,
    });
    expect(value.enabled, isNull);
    expect(value.commentsEnabled, isTrue);
    expect(value.commentLimitPerPost, 3);
    expect(value.commentMaxRawLength, 240);
    expect(value.commentMinRawLength, 8);
    expect(value.answerLikesEnabled, isTrue);
    final restored = const PostVotingSettingsCodec().decode(
      const PostVotingSettingsCodec().encode(value),
    )!;
    expect(restored.enabled, isNull);
    expect(restored.commentLimitPerPost, 3);
    expect(
      const PostVotingSettings().allowsTopic(
        const PostVotingTopicData(enabled: true),
        privateMessage: false,
      ),
      isTrue,
    );
    expect(
      const PostVotingSettings(enabled: false).allowsTopic(
        const PostVotingTopicData(enabled: true),
        privateMessage: false,
      ),
      isFalse,
    );
    expect(
      value.allowsTopic(
        const PostVotingTopicData(enabled: true),
        privateMessage: true,
      ),
      isFalse,
    );
  });

  test(
    'topic partial omissions preserve mode but authoritative omissions retire it',
    () {
      const held = PostVotingTopicData(
        enabled: true,
        answerCount: 3,
        serverReadState: false,
      );
      final sparse = PostVotingTopicData.fromContext(
        {},
        const TopicRecordDecodeContext.partial(),
      );
      expect(held.merge(sparse).enabled, isTrue);
      expect(held.merge(sparse).answerCount, 3);
      expect(held.merge(sparse).serverReadState, isFalse);
      final detail = PostVotingTopicData.fromContext(
        {},
        const TopicRecordDecodeContext.detail(),
      );
      expect(held.merge(detail).enabled, isFalse);
      expect(held.merge(detail).answerCount, isNull);
      final nested = PostVotingTopicData.fromContext({
        'is_post_voting': true,
        'is_nested_view': true,
      }, const TopicRecordDecodeContext.detail());
      expect(nested.enabled, isFalse);
      final pm = PostVotingTopicData.fromContext({
        'is_post_voting': true,
        'archetype': 'private_message',
      }, const TopicRecordDecodeContext.detail());
      expect(pm.enabled, isFalse);
    },
  );

  test('signed score and current-user direction merge independently', () {
    final held = PostVotingPostData(
      score: -2,
      hasVotes: true,
      myVote: PostVoteDirection.down,
      myVoteKnown: true,
    );
    final partial = PostVotingPostData.fromJson({
      'id': 7,
      'post_voting_vote_count': 0,
      'comments_count': 0,
    });
    final merged = held.merge(partial);
    expect(merged.score, 0);
    expect(merged.hasVotes, isTrue);
    expect(merged.myVote, PostVoteDirection.down);
    expect(merged.myVoteKnown, isTrue);
    final complete = PostVotingPostData.fromJson({
      'id': 7,
      'post_voting_vote_count': 0,
    }, authoritativeVote: true);
    expect(held.merge(complete).myVote, isNull);
    expect(held.merge(complete).myVoteKnown, isTrue);
    final malformed = PostVotingPostData.fromJson({
      'id': 7,
      'post_voting_user_voted_direction': 'sideways',
    }, authoritativeVote: true);
    expect(held.merge(malformed).myVote, PostVoteDirection.down);
    expect(PostVotingPostData.fromJson({}).hasData, isFalse);
  });

  test(
    'category defaults use direct basic serializer fields or custom fields',
    () {
      final direct = PostVotingCategoryData.fromJson({
        'create_as_post_voting_default': false,
        'only_post_voting_in_this_category': true,
      });
      expect(direct.defaultOn, isFalse);
      expect(direct.requiredOn, isTrue);
      final detail = PostVotingCategoryData.fromJson({
        'custom_fields': {
          'create_as_post_voting_default': true,
          'only_post_voting_in_this_category': false,
        },
      });
      expect(detail.defaultOn, isTrue);
      expect(detail.requiredOn, isFalse);
      expect(
        PostVotingActor.fromJson({
          'can_flag_post_voting_comments': true,
        }).canFlagComments,
        isTrue,
      );
    },
  );

  test('received score distinguishes absent, zero and negative values', () {
    expect(PostVotingUserScore.fromJson({}), isNull);
    expect(PostVotingUserScore.fromJson({'vote_count': '2'}), isNull);
    expect(
      PostVotingUserScore.fromJson({'vote_count': 0})!.receivedNetScore,
      0,
    );
    expect(
      PostVotingUserScore.fromJson({'vote_count': -3})!.receivedNetScore,
      -3,
    );
  });

  test(
    'zero unread count without a server position does not prove read state',
    () {
      final unknown = PostVotingTopicData.fromContext({
        'is_post_voting': true,
        'unread_posts': 0,
      }, const TopicRecordDecodeContext.list());
      expect(unknown.serverReadState, isNull);
      final caughtUp = PostVotingTopicData.fromContext({
        'is_post_voting': true,
        'highest_post_number': 7,
        'last_read_post_number': 7,
      }, const TopicRecordDecodeContext.list());
      expect(caughtUp.serverReadState, isTrue);
      final unread = PostVotingTopicData.fromContext({
        'is_post_voting': true,
        'highest_post_number': 7,
        'last_read_post_number': 3,
      }, const TopicRecordDecodeContext.list());
      expect(unread.serverReadState, isFalse);
    },
  );

  test(
    'comment identity belongs to parent and server cooked body is retained',
    () {
      final comment = PostVotingComment.fromJson(_comment(), parentPostId: 8);
      expect(comment.parentPostId, 8);
      expect(comment.username, isNull);
      expect(comment.authorId, isNull);
      expect(comment.cooked, '<p>Server <em>cooked</em></p>');
      expect(comment.availableFlags, ['notify_moderators']);
      expect(comment.myUpvote, isFalse);
      expect(comment.copyWith(myUpvote: true, score: 4).myUpvote, isTrue);
      expect(
        comment.copyWith(myUpvote: true).copyWith(myUpvote: false).myUpvote,
        isFalse,
      );
      expect(comment.copyWith(clearMyUpvote: true).myUpvote, isNull);
      expect(
        () => PostVotingComment.fromJson({
          ..._comment(),
          'post_id': 9,
        }, parentPostId: 8),
        throwsFormatException,
      );
      expect(
        () => PostVotingComment.fromJson({
          ..._comment(),
          'id': 0,
        }, parentPostId: 8),
        throwsFormatException,
      );
      expect(
        () => PostVotingComment.fromJson({
          ..._comment(),
          'url': 'javascript:bad()',
        }, parentPostId: 8),
        throwsFormatException,
      );
    },
  );
}

Map<String, dynamic> _comment() => {
  'id': 3,
  'user_id': null,
  'username': null,
  'created_at': '2026-11-01T10:00:00Z',
  'raw': 'Server cooked',
  'cooked': '<p>Server <em>cooked</em></p>',
  'post_voting_vote_count': 3,
  'user_voted': false,
  'available_flags': ['notify_moderators'],
  'url': '/discuss/p/8#post-voting-comment-3',
};
