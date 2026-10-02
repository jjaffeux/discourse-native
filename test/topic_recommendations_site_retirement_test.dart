import 'dart:async';

import 'package:discourse_native/src/data/topic_recommendations_tab_store.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_plugin.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _other = 'https://team.discourse.org';
String _key(String site) =>
    SharedPreferencesTopicRecommendationsTabPersistence.keys.of(site);

void main() {
  testWidgets('queued Native tab choice cannot revive a removed forum key', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      _key(_other): discourseAiRelatedTopicRecommendationSourceId.value,
    });
    final delegate = SharedPreferencesStorePlatform.instance;
    final storage = _HeldWrite(delegate, 'flutter.${_key(_site)}');
    SharedPreferencesStorePlatform.instance = storage;
    addTearDown(() {
      if (!storage.release.isCompleted) storage.release.complete();
      SharedPreferencesStorePlatform.instance = delegate;
      SharedPreferences.setMockInitialValues({});
    });
    final api = FakeDiscourseApi(
      feeds: {
        '/latest.json': const [
          Topic(id: 7, title: 'A real topic', slug: 'real'),
        ],
      },
      topics: {
        7: topicPayload(
          id: 7,
          title: 'A real topic',
          posts: const [
            Post(
              id: 1,
              postNumber: 1,
              username: 'reader',
              cooked: '<p>First post body</p>',
            ),
          ],
          recommendations: TopicRecommendations(
            sources: [
              TopicRecommendationSource(
                definition: coreSuggestedTopicRecommendationSource,
                topics: const [
                  Topic(id: 8, title: 'A suggested topic', slug: 'suggested'),
                ],
              ),
              TopicRecommendationSource(
                definition: discourseAiRelatedTopicRecommendationSource,
                topics: const [
                  Topic(id: 9, title: 'An AI related topic', slug: 'related'),
                ],
              ),
            ],
          ),
        ),
      },
    );
    await pumpShell(tester, desktop, api: api);
    final shell = ShellScope.read(tester.element(find.byType(InstanceRail)));
    await tester.tap(topicListTitle('A real topic'));
    await tester.pumpAndSettle();
    storage.hold = true;
    await tester.tap(_tab(discourseAiRelatedTopicRecommendationSourceId.value));
    await tester.pumpAndSettle();
    await storage.started.future;
    // This optional UI preference is queued behind an already committed
    // write whose acknowledgement is delayed by storage.
    await tester.tap(_tab(coreSuggestedTopicRecommendationSourceId.value));
    await tester.pumpAndSettle();
    expect(storage.targetWrites, 1);
    final removal = shell.removeInstance(shell.instanceFor(_site)!);
    await tester.pump();
    expect(await removal, isTrue);
    await tester.pump();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey(_key(_site)), isFalse);
    storage.release.complete();
    await const TopicRecommendationsTabStore().read(siteUrl: _site);
    await preferences.reload();
    expect(preferences.containsKey(_key(_site)), isFalse);
    expect(storage.targetWrites, 1);
    expect(
      preferences.getString(_key(_other)),
      discourseAiRelatedTopicRecommendationSourceId.value,
    );

    expect(await shell.addInstance(instance('meta.discourse.org')), isTrue);
    shell.selectInstance(
      shell.instances.indexWhere((site) => site.url == _site),
    );
    shell.openTopicFromList(
      const Topic(id: 7, title: 'A real topic', slug: 'real'),
    );
    await tester.pumpAndSettle();
    expect(find.text('A suggested topic'), findsOneWidget);
    await tester.tap(_tab(discourseAiRelatedTopicRecommendationSourceId.value));
    await tester.pumpAndSettle();
    expect(
      await const TopicRecommendationsTabStore().read(siteUrl: _site),
      discourseAiRelatedTopicRecommendationSourceId,
    );
    await preferences.reload();
    expect(
      preferences.getString(_key(_site)),
      discourseAiRelatedTopicRecommendationSourceId.value,
    );
    expect(storage.targetWrites, 2);
    expect(
      preferences.getString(_key(_other)),
      discourseAiRelatedTopicRecommendationSourceId.value,
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

Finder _tab(String source) =>
    find.byKey(ValueKey('topic-recommendations-tab-$source'));

final class _HeldWrite extends SharedPreferencesStorePlatform {
  _HeldWrite(this.delegate, this.target);
  final SharedPreferencesStorePlatform delegate;
  final String target;
  final started = Completer<void>();
  final release = Completer<void>();
  bool hold = false;
  int targetWrites = 0;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    final saved = await delegate.setValue(type, key, value);
    if (key == target) {
      targetWrites++;
      if (hold && !started.isCompleted) {
        started.complete();
        await release.future;
      }
    }
    return saved;
  }

  @override
  Future<bool> remove(String key) => delegate.remove(key);
  @override
  Future<bool> clear() => delegate.clear();
  @override
  Future<Map<String, Object>> getAll() => delegate.getAll();
  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) => delegate.getAllWithParameters(parameters);
}
