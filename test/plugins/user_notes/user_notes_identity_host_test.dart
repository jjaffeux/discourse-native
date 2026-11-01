import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_controller.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_data.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_module.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_plugin.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/shell/user_card_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';
import 'user_notes_fixture.dart';

const _site = notesSite;

Future<List<Rect>> _geometry(
  WidgetTester tester, {
  required bool installedNotes,
  required bool enabled,
  required bool staff,
  required int count,
  required bool mobile,
  required TopicPostLayout layout,
  NotesFixture? live,
  Future<void> Function(List<Rect> baseline)? exercise,
}) async {
  final installed = PluginInstaller.install(
    PluginManifest([
      if (installedNotes)
        live == null ? userNotesModule : _LiveModule(live.controller),
    ]),
  );
  final config = installed.models.siteConfig({
    'user_notes_enabled': enabled,
    'enable_emoji': false,
  }, _site);
  final user = DiscourseUser(id: 1, username: 'reader', staff: staff);
  final api = FakeDiscourseApi(
    models: installed.models,
    user: user,
    feeds: const {'/latest.json': []},
    siteConfigs: {_site: config},
  );
  final instances = [
    instance('forum.example/community', user: user).copyWith(config: config),
  ];
  final shell = ShellController(
    plugins: installed,
    instanceStore: FakeInstanceStore(instances),
    api: api,
    authenticator: FakeAuthenticator.signedIn(instances, site: api),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await tester.runAsync(shell.load);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 350)),
  );
  expect(shell.freshCurrentUserFor(_site)?.staff, staff);
  if (installedNotes && live == null) {
    expect(
      shell.pluginSession.require(userNotesControllerService).canOpen(_site),
      enabled && staff,
    );
  }
  final post = installed.models.post({
    'id': 1,
    'post_number': 1,
    'user_id': 7,
    'username': 'author',
    'cooked': '<p>Post body</p>',
    'user_custom_fields': {'user_notes_count': count},
  }, _site);
  final card = installed.models.userCard({
    'id': 7,
    'username': 'author',
    'name': 'Member',
    'custom_fields': {'user_notes_count': count},
  }, _site);
  shell.store.put(
    _site,
    const TopicDetail(id: 55, title: 'Topic', stream: [1]),
  );
  shell.store.put(_site, post);
  shell.pushContent(
    ContentRoute.topic(topicId: 55, slug: 'topic', title: 'Topic'),
  );
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(
          platform: mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                UserCardHeader(siteUrl: _site, card: card, mobileSheet: mobile),
                TopicPostPresentation(
                  siteUrl: _site,
                  topicId: 55,
                  postId: 1,
                  layout: layout,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final geometry = [
    tester.getRect(find.text('Member')),
    tester.getRect(find.text('author').last),
    tester.getRect(find.text('Post body', findRichText: true)),
    for (final element in find.byType(DAvatar).evaluate())
      tester.getRect(find.byWidget(element.widget)),
  ];
  expect(find.byTooltip('User notes ($count)'), findsNothing);
  await exercise?.call(geometry);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  shell.dispose();
  await tester.runAsync(() async {
    await shell.pluginTeardown;
    await installed.close();
  });
  return geometry;
}

final class _LiveModule implements PluginModule {
  _LiveModule(this.controller);
  final UserNotesController controller;
  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: userNotesPluginId);
  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(const UserNotesPlugin());
    registrar.addSession(
      (bindings, _) => PluginSessionContribution(
        lifecycle: _Lifecycle(),
        services: [
          PluginService<Object>(userNotesControllerService, controller),
        ],
      ),
    );
  }
}

final class _Lifecycle extends PluginSessionLifecycle {}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'real identity hosts react to count and setting changes without replacing records',
    (tester) async {
      final f = NotesFixture();
      addTearDown(() => tester.runAsync(f.dispose));
      await _geometry(
        tester,
        installedNotes: true,
        enabled: true,
        staff: true,
        count: 0,
        mobile: false,
        layout: TopicPostLayout.compact,
        live: f,
        exercise: (baseline) async {
          final session = f.controller.open(siteUrl: notesSite, userId: 7);
          await session.refresh();
          await tester.pumpAndSettle();
          expect(find.byTooltip('User notes (1)'), findsNWidgets(2));
          final postIcon = find.descendant(
            of: find.byType(TopicPostPresentation),
            matching: find.byTooltip('User notes (1)'),
          );
          expect(
            tester.getRect(postIcon).left,
            greaterThan(tester.getRect(find.text('author').last).right),
          );
          f.settings(enabled: true, placement: UserNotesPlacement.avatar);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(postIcon).top,
            greaterThanOrEqualTo(
              tester.getRect(find.byType(DAvatar).last).bottom,
            ),
          );
          f.transport.responders['GET /user_notes?user_id=7'] = (_) =>
              notesPage([]);
          await session.refresh();
          await tester.pumpAndSettle();
          expect(find.byTooltip('User notes (1)'), findsNothing);
          expect(tester.getRect(find.text('author').last), baseline[1]);
          expect(
            tester.getRect(find.text('Post body', findRichText: true)),
            baseline[2],
          );
          f.transport.responders['GET /user_notes?user_id=7'] = (_) =>
              notesPage([noteWire()]);
          await session.refresh();
          await tester.pumpAndSettle();
          expect(find.byTooltip('User notes (1)'), findsNWidgets(2));
          f.settings(enabled: false);
          await tester.pumpAndSettle();
          expect(find.byTooltip('User notes (1)'), findsNothing);
          expect(tester.getRect(find.text('Member')), baseline[0]);
          expect(tester.getRect(find.text('author').last), baseline[1]);
        },
      );
    },
  );
  for (final mobile in [false, true]) {
    for (final layout in [TopicPostLayout.standard, TopicPostLayout.compact]) {
      testWidgets(
        'installed hidden notes leave real post/card geometry unchanged mobile=$mobile layout=$layout',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = mobile
              ? const Size(430, 932)
              : const Size(1000, 900);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final absent = await _geometry(
            tester,
            installedNotes: false,
            enabled: true,
            staff: true,
            count: 2,
            mobile: mobile,
            layout: layout,
          );
          for (final state in [
            (false, true, 2),
            (true, false, 2),
            (true, true, 0),
          ]) {
            final hidden = await _geometry(
              tester,
              installedNotes: true,
              enabled: state.$1,
              staff: state.$2,
              count: state.$3,
              mobile: mobile,
              layout: layout,
            );
            expect(
              hidden,
              absent,
              reason:
                  'enabled=${state.$1}, staff=${state.$2}, count=${state.$3}',
            );
          }
        },
      );
    }
  }
}
