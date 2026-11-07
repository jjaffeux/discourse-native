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
}
