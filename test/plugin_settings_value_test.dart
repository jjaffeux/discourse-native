import 'package:discourse_native/src/plugins/cakeday/cakeday_data.dart';
import 'package:discourse_native/src/plugins/post_voting/post_voting_data.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Cakeday settings compare birthday flags and emoji lists by value', () {
    const settings = CakedaySettings(
      enabled: true,
      birthdays: true,
      anniversaryEmoji: ['cake', 'sailboat'],
      birthdayEmoji: ['birthday', 'tada'],
    );
    final restored = const CakedaySettingsCodec().decode(
      const CakedaySettingsCodec().encode(settings),
    );
    expect(restored, settings);
    expect(restored.hashCode, settings.hashCode);
    expect(
      const CakedaySettings(
        enabled: true,
        birthdays: true,
        anniversaryEmoji: ['sailboat', 'cake'],
        birthdayEmoji: ['birthday', 'tada'],
      ),
      isNot(settings),
    );
    expect(const CakedaySettings(enabled: true), isNot(settings));
  });

  test('User Notes settings keep value identity through storage', () {
    const settings = UserNotesSettings(
      enabled: true,
      placement: UserNotesPlacement.avatar,
      maximumLength: 256,
    );
    final restored = const UserNotesSettingsCodec().decode(
      const UserNotesSettingsCodec().encode(settings),
    );
    expect(restored, settings);
    expect(restored.hashCode, settings.hashCode);
    expect(
      const UserNotesSettings(
        enabled: true,
        placement: UserNotesPlacement.avatar,
        maximumLength: 257,
      ),
      isNot(settings),
    );
    expect(
      const UserNotesSettings(enabled: true, maximumLength: 256),
      isNot(settings),
    );
  });

  test('Post Voting settings keep all limits through storage', () {
    const settings = PostVotingSettings(
      enabled: true,
      commentsEnabled: false,
      commentLimitPerPost: 12,
      commentMaxRawLength: 700,
      commentMinRawLength: 2,
      answerLikesEnabled: true,
      dsaReportingEnabled: true,
    );
    final restored = const PostVotingSettingsCodec().decode(
      const PostVotingSettingsCodec().encode(settings),
    );
    expect(restored, settings);
    expect(restored.hashCode, settings.hashCode);
    expect(const PostVotingSettings(enabled: false), isNot(settings));
    expect(
      const PostVotingSettings(
        enabled: true,
        commentsEnabled: false,
        commentLimitPerPost: 12,
        commentMaxRawLength: 701,
        commentMinRawLength: 2,
        answerLikesEnabled: true,
        dsaReportingEnabled: true,
      ),
      isNot(settings),
    );
  });
  test('plugin record values survive independent decoding', () {
    final dates = CakedayDates.read({
      'cakedate': '2020-02-29',
      'birthdate': '1904-04-12',
    });
    final sameDates = CakedayDates.read({
      'cakedate': '2020-02-29',
      'birthdate': '1904-04-12',
    });
    expect(dates, isNotNull);
    expect(dates, sameDates);
    expect(dates.hashCode, sameDates.hashCode);
    expect(dates, isNot(CakedayDates.read({'cakedate': '2020-03-01'})));
    expect(UserNotesCount.read({'user_notes_count': 7})?.value, 7);
    expect(
      UserNotesCount.read({'user_notes_count': 7}),
      UserNotesCount.read({'user_notes_count': 7}),
    );
    expect(
      UserNotesCount.read({'user_notes_count': 7}),
      isNot(UserNotesCount.read({'user_notes_count': 8})),
    );
    expect(
      PostVotingCategoryData.fromJson({'create_as_post_voting_default': true}),
      PostVotingCategoryData.fromJson({'create_as_post_voting_default': true}),
    );
    expect(
      PostVotingActor.fromJson({'can_flag_post_voting_comments': true}),
      PostVotingActor.fromJson({'can_flag_post_voting_comments': true}),
    );
    expect(
      PostVotingUserScore.fromJson({'vote_count': 7}),
      PostVotingUserScore.fromJson({'vote_count': 7}),
    );
  });

  test(
    'post-voting equality includes independently decoded comment content and votes',
    () {
      PostVotingPostData post({String raw = 'Comment', int score = 1}) =>
          PostVotingPostData.fromJson({
            'id': 9,
            'comments_count': 1,
            'comments': [
              {
                'id': 7,
                'post_id': 9,
                'created_at': '2026-01-02T12:00:00Z',
                'raw': raw,
                'cooked': '<p>Comment</p>',
                'post_voting_vote_count': score,
              },
            ],
          });
      final value = post();
      final sameValue = post();
      expect(value, sameValue);
      expect(value.hashCode, sameValue.hashCode);
      expect(value, isNot(post(raw: 'Edited')));
      expect(value, isNot(post(score: 2)));
    },
  );
}
