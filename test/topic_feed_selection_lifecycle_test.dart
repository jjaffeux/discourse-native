import 'dart:async';

import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  for (final action in [
    'visible',
    'hidden',
    'hidden then shown',
    'selection moved then restored',
    'route changed',
    'unmounted',
  ]) {
    testWidgets('pending keyboard selection respects $action', (tester) async {
      final site = instance('one.example');
      final api = _GatedSelectionApi();
      final controller = ShellController(
        instanceStore: FakeInstanceStore([site]),
        api: api,
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light,
            home: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (context, enabled, _) => TickerMode(
                enabled: enabled,
                child: Scaffold(
                  body: ListenableBuilder(
                    listenable: controller.topicFeeds,
                    builder: (context, _) => controller.currentFeed == null
                        ? const SizedBox.shrink()
                        : TopicListView(feed: controller.currentFeed!),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();
      controller.store.remove<Topic>(site.url, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(api.restoreStarted, isTrue);

      switch (action) {
        case 'hidden' || 'hidden then shown':
          visible.value = false;
          await tester.pump();
          expect(
            TickerMode.valuesOf(
              tester.element(find.byType(TopicListView)),
            ).enabled,
            isFalse,
          );
          if (action == 'hidden then shown') {
            visible.value = true;
            await tester.pump();
          }
        case 'selection moved then restored':
          controller.store.put(site.url, _topic(1));
          await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
          await tester.pumpAndSettle();
        case 'route changed':
          controller.openTopic(_topic(2));
          await tester.pump();
        case 'unmounted':
          await tester.pumpWidget(const SizedBox.shrink());
        case 'visible':
          break;
      }

      api.restore.complete(_topic(1));
      await tester.pump();
      await tester.pump();
      expect(
        controller.currentContent?.topicId,
        action == 'visible'
            ? 1
            : action == 'route changed'
            ? 2
            : isNull,
      );
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  }
}

Topic _topic(int id) => Topic(id: id, title: 'Topic $id', slug: 'topic-$id');

final class _GatedSelectionApi extends FakeDiscourseApi {
  final restore = Completer<Topic>();
  bool restoreStarted = false;

  @override
  Future<Topic> topicSummary({
    required String siteUrl,
    required int id,
    String? apiKey,
    String? clientId,
  }) {
    restoreStarted = true;
    return restore.future;
  }

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async => TopicList(topics: [for (var id = 1; id <= 30; id++) _topic(id)]);
}
