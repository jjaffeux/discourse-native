import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_inbox_header.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final (appScale, accessibility, height, textSize) in [
      (1.0, 1.0, 44.0, 16.0),
      (1.25, 2.0, 80.0, 40.0),
    ]) {
      testWidgets(
        'topic taxonomy excludes reading uplift on $platform at $appScale/$accessibility',
        (tester) async {
          tester.view.physicalSize = const Size(900, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final shell = ShellController(
            instanceStore: FakeInstanceStore([instance('forum.example')]),
            api: FakeDiscourseApi(),
            authenticator: FakeAuthenticator(),
            drafts: FakeDraftStore(),
            trackers: FakeSiteTracker.reset(),
            updater: FakeUpdater(),
            updateStore: FakeUpdateStore(),
            mobileNavigationEnabled: true,
          );
          addTearDown(shell.dispose);
          await shell.load();

          Future<void> pumpHeader({required bool loading}) async {
            await tester.pumpWidget(
              ShellScope(
                controller: shell,
                child: MaterialApp(
                  theme: AppTheme.dark.copyWith(platform: platform),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: AppTextScaler(
                        platformScaler: TextScaler.linear(accessibility),
                        appScale: appScale,
                        baselineScale: 17 / 14,
                      ),
                    ),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: TopicInboxHeader(
                      title: 'Topic title',
                      siteUrl: 'https://forum.example',
                      canReturnToSidebar: false,
                      keepTopicListOpen: false,
                      registry: PluginRegistry.empty,
                      loading: loading,
                      topic: loading
                          ? null
                          : const TopicDetail(
                              id: 1,
                              title: 'Topic title',
                              stream: [],
                              canEditTags: true,
                            ),
                    ),
                  ),
                ),
              ),
            );
            if (loading) {
              await tester.pump(const Duration(milliseconds: 300));
            } else {
              await tester.pumpAndSettle();
            }
          }

          await pumpHeader(loading: false);
          for (final label in ['+ Category', 'Add tag']) {
            final text = find.text(label);
            final button = find.ancestor(
              of: text,
              matching: find.byType(DButton),
            );
            expect(tester.getSize(button).height, height);
            final context = tester.element(text);
            final fontSize = DefaultTextStyle.of(context).style.fontSize!;
            expect(MediaQuery.textScalerOf(context).scale(fontSize), textSize);
          }
          final titleContext = tester.element(find.text('Topic title'));
          expect(
            MediaQuery.textScalerOf(titleContext).scale(14),
            17 * appScale * accessibility,
          );
          final loadedHeight = tester
              .getSize(find.byKey(const ValueKey('topic-header-taxonomy')))
              .height;
          expect(loadedHeight, height);
          await pumpHeader(loading: true);
          expect(
            tester
                .getSize(
                  find.byKey(
                    const ValueKey('topic-header-taxonomy-placeholder'),
                  ),
                )
                .height,
            loadedHeight,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
