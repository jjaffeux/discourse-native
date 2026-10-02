import 'package:discourse_native/src/models/forum_about.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads flat About stats and server identity', () {
    final about = ForumAbout.fromJson({
      'about': {
        'title': 'Our community',
        'description': 'A forum for everyone',
        'extended_site_description':
            '<p>Welcome <strong>everyone</strong>.</p>',
        'site_creation_date': '2020-01-02T00:00:00Z',
        'can_see_about_stats': true,
        'stats': {
          'users_count': 100,
          'topics_7_days': 4,
          'voice_users_7_days': 12,
        },
      },
    });
    expect(about.title, 'Our community');
    expect(about.description, 'A forum for everyone');
    expect(about.extendedDescription, 'Welcome everyone.');
    expect(about.creationDate, DateTime.utc(2020, 1, 2));
    expect(about.members, 100);
    expect(about.voiceParticipants(voiceEnabled: true), 12);
    expect(about.voiceParticipants(voiceEnabled: false), isNull);
  });

  test('older servers, disabled analytics and zero activity omit voice', () {
    for (final stats in <Map<String, Object?>>[
      {},
      {'user_count': 8, 'topic_count': 10},
      {'voice_users_7_days': 0},
      {'voice_users_7_days': null},
      {'voice_users_7_days': -1},
      {'voice_users_7_days': '3'},
      {'voice_users_7_days': 3.5},
      {
        'voice_users_7_days': {'7_days': 3},
      },
    ]) {
      final about = ForumAbout.fromJson({
        'about': {'stats': stats},
      });
      expect(about.voiceParticipants(voiceEnabled: true), isNull);
    }
    expect(ForumAbout.fromJson({'about': <String, Object?>{}}).stats, isEmpty);
    expect(
      ForumAbout.fromJson({
        'about': {
          'stats': {'user_count': 8},
        },
      }).members,
      8,
    );
  });

  test('permission refusal suppresses all stats even if returned', () {
    final about = ForumAbout.fromJson({
      'about': {
        'can_see_about_stats': false,
        'stats': {'users_count': 8, 'voice_users_7_days': 12},
      },
    });
    expect(about.stats, isEmpty);
    expect(about.voiceParticipants(voiceEnabled: true), isNull);
  });

  test(
    'malformed response fails rather than showing an empty success page',
    () {
      for (final about in [null, 'about', <Object?>[], 4]) {
        expect(
          () => ForumAbout.fromJson({'about': about}),
          throwsFormatException,
        );
      }
    },
  );
}
