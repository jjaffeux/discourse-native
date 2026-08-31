import 'dart:async';

import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/app_settings_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Settings root navigation', () {
    test('restores Aggregate before sites have loaded', () async {
      final controller = _controller(
        instanceStore: FakeInstanceStore(),
        initialRootMode: ShellRootMode.aggregate,
      );
      addTearDown(controller.dispose);

      controller.selectSettings();
      expect(controller.handleBack(), isTrue);

      expect(controller.rootMode, ShellRootMode.aggregate);
      expect(controller.mobilePane, MobilePane.content);

      await controller.load();
      expect(controller.rootMode, ShellRootMode.aggregate);
    });

    test('alignment changes do not notify the shell controller', () async {
      final controller = _controller(instanceStore: FakeInstanceStore());
      addTearDown(controller.dispose);
      var shellNotifications = 0;
      controller.addListener(() => shellNotifications++);

      await controller.appSettings.setContentAlignment(ContentAlignment.right);

      expect(controller.appSettings.contentAlignment, ContentAlignment.right);
      expect(shellNotifications, 0);
    });

    test('restores the exact compact forum pane and workspace', () async {
      final controller = await _loadedController();
      addTearDown(controller.dispose);

      controller.pushContent(
        ContentRoute.topic(topicId: 42, slug: 'kept', title: 'Kept topic'),
      );
      controller.saveTopicScrollPost(42, 17, viewportOffset: 23);
      final workspace = controller.currentWorkspace;
      final activeTabId = controller.activeTabId;
      final routes = List<ContentRoute>.of(controller.contentStack);

      expect(controller.mobilePane, MobilePane.content);

      controller.selectSettings();
      controller.selectSettings();

      expect(controller.rootMode, ShellRootMode.settings);
      expect(controller.mobilePane, MobilePane.content);
      expect(controller.handleBack(), isTrue);
      expect(controller.rootMode, ShellRootMode.forum);
      expect(controller.mobilePane, MobilePane.content);
      expect(controller.currentWorkspace, same(workspace));
      expect(controller.activeTabId, activeTabId);
      expect(controller.contentStack, routes);
      expect(controller.topicScrollPostNumber(42), 17);
      expect(controller.topicScrollPostOffset(42), 23);

      controller.selectInstance(0);
      expect(controller.mobilePane, MobilePane.sidebar);

      controller.selectSettings();
      controller.selectSettings();
      expect(controller.handleBack(canReturnToSidebar: false), isTrue);

      expect(controller.rootMode, ShellRootMode.forum);
      expect(controller.mobilePane, MobilePane.sidebar);
      expect(controller.currentWorkspace, same(workspace));
      expect(controller.activeTabId, activeTabId);
      expect(controller.contentStack, routes);
    });

    test('restores Aggregate after repeated Settings activation', () async {
      final controller = await _loadedController();
      addTearDown(controller.dispose);
      final workspace = controller.currentWorkspace;

      controller.selectAggregate();
      expect(controller.rootMode, ShellRootMode.aggregate);

      controller.selectSettings();
      controller.selectSettings();
      expect(controller.rootMode, ShellRootMode.settings);
      expect(controller.handleBack(), isTrue);

      expect(controller.rootMode, ShellRootMode.aggregate);
      expect(controller.mobilePane, MobilePane.content);
      expect(controller.currentWorkspace, same(workspace));
    });

    test('explicit rail destinations and deep links exit Settings', () async {
      final controller = await _loadedController();
      addTearDown(controller.dispose);

      controller.selectSettings();
      controller.selectInstance(1);

      expect(controller.rootMode, ShellRootMode.forum);
      expect(controller.mobilePane, MobilePane.sidebar);
      expect(controller.currentInstance?.url, 'https://two.example');

      controller.selectSettings();
      controller.selectAggregate();

      expect(controller.rootMode, ShellRootMode.aggregate);
      expect(controller.mobilePane, MobilePane.content);

      controller.selectSettings();
      expect(
        controller.openTopicUrl('https://one.example/t/deep-link/42'),
        isTrue,
      );

      expect(controller.rootMode, ShellRootMode.forum);
      expect(controller.mobilePane, MobilePane.content);
      expect(controller.currentInstance?.url, 'https://one.example');

      controller.selectSettings();
      expect(
        controller.openTopicUrl('https://one.example/t/same-forum/43'),
        isTrue,
      );

      expect(controller.rootMode, ShellRootMode.forum);
      expect(controller.mobilePane, MobilePane.content);
      expect(controller.currentContent?.topicId, 43);
    });

    testWidgets('keeps the forum scroll subtree mounted behind Settings', (
      tester,
    ) async {
      final topics = [
        for (var id = 1; id <= 40; id++)
          Topic(id: id, title: 'Topic $id', slug: 'topic-$id'),
      ];
      final controller = _controller(
        instanceStore: FakeInstanceStore([_connected('one.example')]),
        api: FakeDiscourseApi(feeds: {'/latest.json': topics}),
      );
      addTearDown(controller.dispose);
      await controller.load();
      await controller.loadFeed('latest');
      await tester.binding.setSurfaceSize(const Size(1200, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const AdaptiveShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final visibleList = find.byType(SuperListView);
      final scroll = tester.widget<SuperListView>(visibleList).controller!;
      await tester.drag(visibleList, const Offset(0, -400));
      await tester.pumpAndSettle();
      final offset = scroll.offset;
      expect(offset, greaterThan(0));

      await tester.tap(find.byKey(const ValueKey('settings-rail-button')));
      await tester.pump();

      expect(find.byType(AppSettingsPage), findsOneWidget);
      final retainedList = find.byType(SuperListView, skipOffstage: false);
      expect(retainedList, findsOneWidget);
      expect(
        tester.widget<SuperListView>(retainedList).controller,
        same(scroll),
      );
      expect(scroll.offset, offset);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(
        scroll.offset,
        offset,
        reason: 'the hidden topic list must not consume boundary shortcuts',
      );

      await tester.tap(find.byKey(const ValueKey('app-settings-back')));
      await tester.pump();

      expect(find.byType(TopicListView), findsOneWidget);
      expect(
        tester.widget<SuperListView>(visibleList).controller,
        same(scroll),
      );
      expect(scroll.offset, offset);
    });

    testWidgets('hidden Settings controls cannot keep keyboard focus', (
      tester,
    ) async {
      final controller = _controller(
        instanceStore: FakeInstanceStore([_connected('one.example')]),
      );
      addTearDown(controller.dispose);
      await controller.load();
      controller.pushContent(
        ContentRoute.topic(topicId: 42, slug: 'kept', title: 'Kept topic'),
      );
      await tester.binding.setSurfaceSize(const Size(1200, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const AdaptiveShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('settings-rail-button')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('app-settings-back')));
      await tester.pump();

      final stack = List<ContentRoute>.of(controller.contentStack);
      final hiddenSettings = tester.element(
        find.byType(AppSettingsPage, skipOffstage: false),
      );
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      if (focusedContext != null) {
        expect(_isDescendantOf(focusedContext, hiddenSettings), isFalse);
      }

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.contentStack, stack);
    });

    testWidgets('Settings dismisses an open topic-filter overlay', (
      tester,
    ) async {
      final controller = _controller(
        instanceStore: FakeInstanceStore([_connected('one.example')]),
        api: FakeDiscourseApi(
          feeds: const {'/latest.json': [], '/filter.json': []},
          filterOptionsByPath: const {
            '/filter.json': [TopicFilterOption(name: 'status:', priority: 1)],
          },
        ),
      );
      addTearDown(controller.dispose);
      await controller.load();
      controller.pushContent(
        const ContentRoute(
          id: 'filter',
          title: 'Filter',
          icon: DIcons.filter,
          feedPath: '/filter.json',
        ),
      );
      await controller.loadFeed('filter');
      await tester.binding.setSurfaceSize(const Size(1200, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const AdaptiveShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('topic-filter-input')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('topic-filter-suggestion-0')),
        findsOneWidget,
      );

      controller.selectSettings();
      await tester.pumpAndSettle();

      expect(find.byType(AppSettingsPage), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('topic-filter-suggestion-0'),
          skipOffstage: false,
        ),
        findsNothing,
      );

      expect(controller.handleBack(), isTrue);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('topic-filter-suggestion-0')),
        findsNothing,
      );
    });
  });

  group('Settings shell availability', () {
    testWidgets('replaces the loading shell', (tester) async {
      final load = Completer<List<DiscourseInstance>>();
      final controller = _controller(instanceStore: _GatedInstanceStore(load));
      addTearDown(controller.dispose);
      unawaited(controller.load());

      expect(controller.loadStatus, InstanceLoadStatus.loading);
      await _openSettingsFromRail(tester, controller);

      load.complete(const []);
      await tester.pump();
    });

    testWidgets('replaces the empty ready shell', (tester) async {
      final controller = _controller(instanceStore: FakeInstanceStore());
      addTearDown(controller.dispose);
      await controller.load();

      expect(controller.loadStatus, InstanceLoadStatus.ready);
      expect(controller.hasInstances, isFalse);
      await _openSettingsFromRail(tester, controller);
    });

    testWidgets('replaces the failed shell', (tester) async {
      final controller = _controller(
        instanceStore: const _FailingInstanceStore(),
      );
      addTearDown(controller.dispose);
      await controller.load();

      expect(controller.loadStatus, InstanceLoadStatus.failed);
      await _openSettingsFromRail(tester, controller);
    });
  });
}

bool _isDescendantOf(BuildContext child, Element ancestor) {
  var descendant = false;
  child.visitAncestorElements((element) {
    if (identical(element, ancestor)) {
      descendant = true;
      return false;
    }
    return true;
  });
  return descendant;
}

Future<ShellController> _loadedController() async {
  final controller = _controller(
    instanceStore: FakeInstanceStore([
      _connected('one.example'),
      _connected('two.example'),
    ]),
  );
  await controller.load();
  return controller;
}

ShellController _controller({
  required InstanceStore instanceStore,
  ShellRootMode initialRootMode = ShellRootMode.forum,
  FakeDiscourseApi? api,
}) => ShellController(
  instanceStore: instanceStore,
  api: api ?? FakeDiscourseApi(feeds: const {'/latest.json': []}),
  authenticator: FakeAuthenticator(),
  drafts: FakeDraftStore(),
  forumTabs: FakeForumTabStore(),
  trackers: FakeSiteTracker.reset(),
  updateStore: FakeUpdateStore(),
  initialRootMode: initialRootMode,
  appSettingsStore: AppSettingsStore(
    persistence: MemoryAppSettingsPersistence(),
  ),
);

DiscourseInstance _connected(String host) => instance(
  host,
).copyWith(user: const DiscourseUser(id: 1, username: 'reader'));

Future<void> _openSettingsFromRail(
  WidgetTester tester,
  ShellController controller,
) async {
  await tester.binding.setSurfaceSize(const Size(700, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(theme: AppTheme.light, home: const AdaptiveShell()),
    ),
  );
  await tester.pump();

  final settingsButton = find.byKey(const ValueKey('settings-rail-button'));
  expect(settingsButton, findsOneWidget);

  await tester.tap(settingsButton);
  // The loading rail intentionally contains an indefinitely animated
  // activity indicator, so settling the entire shell can never complete.
  // A finite pump is enough to finish the Settings transition while keeping
  // this test independent of the load state.
  await tester.pump(const Duration(milliseconds: 300));

  expect(controller.rootMode, ShellRootMode.settings);
  expect(find.byType(AppSettingsPage), findsOneWidget);
  expect(find.text('Content alignment'), findsOneWidget);
}

final class _GatedInstanceStore implements InstanceStore {
  const _GatedInstanceStore(this.loadCompleter);

  final Completer<List<DiscourseInstance>> loadCompleter;

  @override
  Future<List<DiscourseInstance>> load() => loadCompleter.future;

  @override
  Future<void> save(List<DiscourseInstance> instances) async {}
}

final class _FailingInstanceStore implements InstanceStore {
  const _FailingInstanceStore();

  @override
  Future<List<DiscourseInstance>> load() =>
      Future<List<DiscourseInstance>>.error(StateError('load failed'));

  @override
  Future<void> save(List<DiscourseInstance> instances) async {}
}
