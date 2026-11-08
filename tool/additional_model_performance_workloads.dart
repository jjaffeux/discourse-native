import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_theme_library.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/post_checklist.dart';
import 'package:discourse_native/src/models/topic_tracking_message_filter.dart';

Map<String, int> measureAdditionalModelPerformance() {
  final times = <String, int>{};
  void measure(String name, int iterations, void Function() action) {
    for (var i = 0; i < 10; i++) {
      action();
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      action();
    }
    watch.stop();
    times[name] = watch.elapsedMicroseconds;
  }

  final source = [
    '<p>Tasks &amp; notes</p>',
    for (var i = 0; i < 40; i++)
      '<p><span class="chcklst-box fa-square-o" data-chk-src="$i:0" '
          'aria-checked="false"></span> Task $i &amp; notes</p>',
    '<aside class="quote" data-post="10">'
        '<span class="chcklst-box checked"></span> Quoted</aside>',
  ].join();
  final document = PostChecklistDocument(source);
  final expectedFingerprint = document.fingerprint;
  final expectedUpdated = document.withStates({0: true, 39: true});
  measure('checklist_state_and_fingerprint', 1000, () {
    if (document.withStates({0: true, 39: true}) != expectedUpdated ||
        document.fingerprint != expectedFingerprint) {
      throw StateError('Checklist transformation changed');
    }
  });

  final theme = forumThemePresets.first;
  for (final count in [10, 300]) {
    final wire = {
      'version': 2,
      'customThemes': [
        for (var i = 0; i < count; i++)
          {'id': 'custom-$i', ...theme.copyWith(name: 'Theme $i').toJson()},
      ],
    };
    measure(
      count == 10 ? 'theme_library_decode_small' : 'theme_library_decode',
      count == 10 ? 3000 : 300,
      () {
        final preferences = ForumThemePreferences.fromJson(wire);
        if (preferences.customThemes.length != count ||
            preferences.customThemes.last.id != 'custom-${count - 1}' ||
            preferences.customThemes.last.name != 'Theme ${count - 1}') {
          throw StateError('Theme decode changed');
        }
      },
    );
  }

  final library = ForumThemeLibrary(
    themes: [
      for (var i = 0; i < 300; i++)
        theme.copyWith(id: 'custom-$i', name: 'Held $i'),
    ],
  );
  final legacy = ForumThemePreferences(
    customId: 'custom-299',
    source: ForumThemeSource.custom,
    customThemes: [
      for (var i = 200; i < 400; i++)
        theme.copyWith(id: 'custom-$i', name: 'Legacy $i'),
    ],
  );
  measure('theme_library_migration_empty', 3000, () {
    final migrated = library.migrate(
      'https://new.example.com',
      ForumThemePreferences.defaults,
    );
    if (migrated.themes.length != 300 ||
        migrated.forSite('https://new.example.com').source !=
            ForumThemeSource.forum) {
      throw StateError('Empty theme migration changed');
    }
  });
  measure('theme_library_migration', 300, () {
    final migrated = library.migrate('https://example.com', legacy);
    if (migrated.themes.length != 500 ||
        migrated.themes[300].id != 'custom-200-2' ||
        migrated.themes.last.id != 'custom-399' ||
        migrated.forSite('https://example.com').customId != 'custom-299-2') {
      throw StateError('Theme migration changed');
    }
  });

  final now = DateTime.utc(2026);
  final filter = TopicTrackingMessageFilter(clock: () => now);
  for (var i = 0; i < 1000; i++) {
    filter.accepts({'topic_id': i + 1, 'message_type': 'unmuted'});
  }
  const user = DiscourseUser(username: 'reader', mutedCategoryIds: [1]);
  final arrival = {
    'topic_id': 1,
    'message_type': 'new_topic',
    'payload': {'category_id': 1},
  };
  measure('tracking_hint_event_filter', 10000, () {
    if (!filter.accepts(arrival, user: user) ||
        !filter.admitsIncoming(arrival, user: user)) {
      throw StateError('Hint admission changed');
    }
  });
  return times;
}
