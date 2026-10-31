import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/shared_appearance.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_data.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_module.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_plugin.dart';
import 'package:discourse_native/src/plugins/nested_replies/nested_replies_reader.dart';
import 'package:discourse_native/src/shell/composer/target.dart';
import 'package:discourse_native/src/shell/post_actions.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';
import '../../support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _title = 'A harbour conversation';
const _manifest = PluginManifest([nestedRepliesModule]);
const _registry = PluginRegistry([
  NestedRepliesPlugin(),
  NestedRepliesPostPlugin(),
]);
const _models = DiscourseModelCodec(extensions: _registry);
const _user = DiscourseUser(id: 9, username: 'reader', staff: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notificationChannel = MethodChannel(
    'org.discourse.native/notification_opens',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(notificationChannel, (_) async => null);
  });
  tearDown(() => messenger.setMockMethodCallHandler(notificationChannel, null));
  setUpAll(() async {
    await (FontLoader(
      'Open Sans',
    )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets('nested posts follow the live content width preference', (
    tester,
  ) async {
    final fixture = await _pump(tester, const Size(2000, 900));
    await fixture.shell.appSettings.setLimitContentSize(true);
    fixture.shell.openTopic(fixture.row);
    await _frames(tester);
    final op = find.byKey(const ValueKey('topic-post-highlight-101'));
    final reply = find.byKey(const ValueKey(103));
    expect(tester.getSize(op).width, 825);
    expect(tester.getSize(reply).width, 825);
    expect(tester.getTopLeft(op).dx, tester.getTopLeft(reply).dx);
    await _export(tester, 'desktop-limited');
    await fixture.shell.appSettings.setLimitContentSize(false);
    await _frames(tester);
    expect(tester.getSize(op).width, greaterThan(825));
    expect(tester.getSize(reply).width, tester.getSize(op).width);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [phone, desktop]) {
    testWidgets(
      'nested sort stays in the bottom corner at ${size.width}',
      (tester) async {
        final fixture = await _pump(tester, size);
        fixture
            .api
            .pluginResponses['GET /n/harbour/7.json?sort=new&page=0&track_visit=true'] = {
          ..._roots(),
          'sort': 'new',
          'effective_sort': 'new',
        };
        fixture.shell.openTopic(fixture.row);
        await _frames(tester);
        final reader = find.byType(NestedRepliesReader);
        final viewport = tester.getRect(reader);
        final sort = find.text('Top').hitTestable();
        final labelRect = tester.getRect(sort);
        expect(labelRect.center.dx, greaterThan(viewport.right - 130));
        expect(labelRect.center.dy, greaterThan(viewport.bottom - 130));
        final trigger = find
            .ancestor(of: sort, matching: find.byType(DButton))
            .first;
        final rect = tester.getRect(trigger);
        expect(rect.center.dx, greaterThan(viewport.right - 130));
        expect(rect.center.dy, greaterThan(viewport.bottom - 130));
        final button = tester.widget<DButton>(trigger);
        expect(button.shape, DButtonShape.pill);
        expect(
          button.size,
          size == phone ? DButtonSize.floating : DButtonSize.chip,
        );
        expect(
          find.descendant(
            of: reader,
            matching: find.widgetWithText(DButton, 'Reply'),
          ),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('topic-progress-button')),
          findsNothing,
        );
        await tester.scrollUntilVisible(
          renderedText('Leave room for the boat astern.').first,
          200,
          scrollable: find
              .descendant(of: reader, matching: find.byType(Scrollable))
              .first,
        );
        await _frames(tester);
        expect(
          tester.getRect(sort).center.dy,
          greaterThan(viewport.bottom - 130),
        );
        await _export(
          tester,
          size == phone ? 'phone-sort-corner' : 'desktop-sort-corner',
        );
        await tester.tap(sort);
        await _frames(tester);
        await tester.tap(find.text('Newest').hitTestable().last);
        await _frames(tester);
        expect(fixture.shell.currentContent!.topicQuery, 'sort=new');
        expect(find.text('Newest').hitTestable(), findsOneWidget);
        expect(
          fixture.api.pluginReadPaths,
          contains('/n/harbour/7.json?sort=new&page=0&track_visit=true'),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(
        size == phone ? TargetPlatform.iOS : TargetPlatform.macOS,
      ),
    );
  }

  for (final size in [phone, desktop]) {
    testWidgets(
      'registered plugin renders canonical posts and preserves flat membership at ${size.width}',
      (tester) async {
        final fixture = await _pump(tester, size);
        final shell = fixture.shell;
        shell.openTopic(fixture.row);
        await _frames(tester);
        expect(find.byType(NestedRepliesReader), findsOneWidget);
        expect(
          renderedText('Choose a sheltered berth before sunset.'),
          findsWidgets,
        );
        expect(renderedText('Start with the harbour entrance.'), findsWidgets);
        expect(shell.currentTopic!.stream, [101, 102, 103, 104]);
        expect(fixture.api.topicPostNumbersOpened.first, isNull);
        expect(
          fixture.api.pluginReadPaths.where((path) => path.startsWith('/n/')),
          ['/n/harbour/7.json?sort=top&page=0&track_visit=true'],
        );
        expect(find.byType(PostActions), findsWidgets);
        expect(
          shell.store.read<Post>(_site, 103)!.raw,
          'Choose a sheltered berth before sunset.',
        );
        expect(tester.takeException(), isNull);
        if (size == phone) {
          expect(find.text('Top').hitTestable(), findsOneWidget);
        }
        await _export(
          tester,
          size.width == phone.width ? 'phone-normal' : 'desktop-normal',
        );
        await tester.scrollUntilVisible(
          renderedText('Leave room for the boat astern.').first,
          200,
          scrollable: find
              .descendant(
                of: find.byType(NestedRepliesReader),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await _frames(tester);
        expect(renderedText('Leave room for the boat astern.'), findsWidgets);
        final rootTop = tester
            .getTopLeft(find.byKey(const ValueKey('topic-post-highlight-103')))
            .dy;
        final childTop = tester
            .getTopLeft(find.byKey(const ValueKey('topic-post-highlight-104')))
            .dy;
        final laterRootTop = tester
            .getTopLeft(find.byKey(const ValueKey('topic-post-highlight-102')))
            .dy;
        expect(rootTop, lessThan(childTop));
        expect(childTop, lessThan(laterRootTop));
        if (size == phone) {
          expect(find.text('Top').hitTestable(), findsOneWidget);
        }
        expect(
          shell.store
              .read<Post>(_site, 104)!
              .plugins
              .get(nestedRepliesPostKey)!
              .replyToPostNumber,
          3,
        );
        expect(tester.takeException(), isNull);
        await _export(
          tester,
          size.width == phone.width ? 'phone-thread' : 'desktop-thread',
        );
        final root = find.byKey(const ValueKey('nested-row-103'));
        final collapse = find.byKey(const ValueKey('nested-collapse-103'));
        final disclosureArtwork = find.descendant(
          of: collapse,
          matching: find.byType(AnimatedContainer),
        );
        final disclosureRect = tester.getRect(disclosureArtwork);
        expect(disclosureRect.size, const Size(14, 14));
        final avatar = find
            .descendant(of: root, matching: find.byType(AvatarImage))
            .first;
        final bodyRail = find
            .descendant(
              of: root,
              matching: find.byWidgetPredicate(
                (widget) => widget is DThreadRail && widget.onPressed != null,
              ),
            )
            .first;
        expect(tester.getRect(bodyRail).top - tester.getRect(avatar).bottom, 4);
        final rails = find
            .descendant(of: root, matching: find.byType(DThreadRail))
            .evaluate()
            .map(
              (element) => tester.getRect(
                find.byElementPredicate((candidate) => candidate == element),
              ),
            )
            .toList();
        final endsAbove = rails
            .where((rect) => rect.bottom <= disclosureRect.top)
            .map((rect) => rect.bottom)
            .reduce((a, b) => a > b ? a : b);
        final startsBelow = rails
            .where((rect) => rect.top >= disclosureRect.bottom)
            .map((rect) => rect.top)
            .reduce((a, b) => a < b ? a : b);
        expect(disclosureRect.top - endsAbove, 4);
        expect(startsBelow - disclosureRect.bottom, 4);
        expect(find.text('Collapse post'), findsNothing);
        expect(find.byType(DThreadConnector), findsWidgets);
        final rootX = tester
            .getTopLeft(find.byKey(const ValueKey('topic-post-highlight-103')))
            .dx;
        final childX = tester
            .getTopLeft(find.byKey(const ValueKey('topic-post-highlight-104')))
            .dx;
        expect(childX - rootX, size == phone ? 20 : 32);
        await tester.ensureVisible(collapse);
        await tester.tap(collapse);
        await _frames(tester);
        expect(
          find.descendant(of: root, matching: find.text('sailor')),
          findsOneWidget,
        );
        expect(
          renderedText('Choose a sheltered berth before sunset.'),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('nested-row-104')), findsNothing);
        expect(tester.widget<DToggle>(collapse).pressed, isTrue);
        expect(tester.getSize(disclosureArtwork), const Size(14, 14));
        await _export(
          tester,
          size == phone ? 'phone-collapsed' : 'desktop-collapsed',
        );
        await tester.tap(collapse);
        await _frames(tester);
        expect(
          renderedText('Choose a sheltered berth before sunset.'),
          findsWidgets,
        );
        expect(find.byKey(const ValueKey('nested-row-104')), findsOneWidget);
        final rail = find
            .descendant(
              of: root,
              matching: find.byWidgetPredicate(
                (widget) => widget is DThreadRail && widget.onPressed != null,
              ),
            )
            .first;
        await tester.ensureVisible(rail);
        await tester.tapAt(tester.getCenter(rail));
        await _frames(tester);
        expect(tester.widget<DToggle>(collapse).pressed, isTrue);
        expect(find.byKey(const ValueKey('nested-row-104')), findsNothing);
        expect(tester.widget<DToggle>(collapse).focusNode!.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _frames(tester);
        expect(tester.widget<DToggle>(collapse).pressed, isFalse);
        final branch = find.descendant(
          of: find.byKey(const ValueKey('nested-row-104')),
          matching: find.byType(DThreadConnector),
        );
        if (size != phone) {
          await tester.ensureVisible(branch);
          await tester.tapAt(tester.getTopRight(branch) + const Offset(-2, 24));
          await _frames(tester);
          expect(tester.widget<DToggle>(collapse).pressed, isTrue);
          expect(find.byKey(const ValueKey('nested-row-104')), findsNothing);
        } else {
          expect(tester.widget<DThreadConnector>(branch).onPressed, isNull);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
      variant: TargetPlatformVariant.only(
        size == phone ? TargetPlatform.iOS : TargetPlatform.linux,
      ),
    );
  }

  testWidgets('shared reading time follows the current site reading speed', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _pump(
      tester,
      desktop,
      configGate: gate,
      beforeSettle: (shell, api, row) async {
        shell.openTopic(row);
        await _frames(tester);
        expect(find.text('6 min'), findsOneWidget);
        expect(tester.takeException(), isNull);
        api.siteConfigs[_site] = SiteConfig(
          readTimeWordCount: 400,
          plugins: PluginData.none.withValue(
            nestedRepliesSettingsKey,
            const NestedRepliesSettings(enabled: true),
          ),
        );
        gate.complete();
      },
    );
    await _frames(tester);
    expect(find.byType(NestedRepliesReader), findsOneWidget);
    expect(find.text('3 min'), findsOneWidget);
    expect(find.text('6 min'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'a canonical post Reply action opens the ordinary composer for its exact parent',
    (tester) async {
      final fixture = await _pump(tester, desktop);
      fixture.shell.openTopic(fixture.row);
      await _frames(tester);
      final post = find.byKey(const ValueKey('topic-post-highlight-103'));
      expect(post, findsOneWidget);
      final reply = find.descendant(
        of: post,
        matching: find.byTooltip('Reply to this post'),
      );
      expect(reply, findsOneWidget);
      await tester.tap(reply);
      await _frames(tester);
      expect(fixture.shell.visibleComposer!.target, isA<ReplyComposerTarget>());
      expect(fixture.shell.visibleComposer!.target.replyToPostNumber, 3);
      expect(fixture.shell.currentContent!.topicId, 7);
      expect(find.byType(NestedRepliesReader), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  for (final enabled in [false, true]) {
    testWidgets(
      '${enabled ? 'absent module' : 'disabled site'} keeps ordinary reader and sends no tree request',
      (tester) async {
        final fixture = await _pump(
          tester,
          desktop,
          enabled: enabled,
          installed: !enabled,
        );
        fixture.shell.openTopic(fixture.row);
        await _frames(tester);
        expect(find.byType(NestedRepliesReader), findsNothing);
        expect(
          fixture.api.pluginReadPaths.where((path) => path.startsWith('/n/')),
          isEmpty,
        );
        final notification = DiscourseNotification(
          id: 10,
          typeId: const NotificationTypeId(2),
          topicId: 7,
          postNumber: 8,
          slug: 'harbour',
          data: const {'reply_to_post_number': 2, 'consolidated_count': 4},
        );
        expect(
          fixture.shell.pluginSession
              .resolveNotification(
                fixture.shell.plugins.registry,
                _site,
                notification,
              )
              .path,
          '/t/harbour/7/8',
        );
        expect(renderedText('Start with the harbour entrance.'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

  testWidgets(
    'fresh disabled settings retire an already active plugin and held policy',
    (tester) async {
      final gate = Completer<void>();
      var treeReads = 0;
      final fixture = await _pump(
        tester,
        desktop,
        configGate: gate,
        beforeSettle: (shell, api, row) async {
          await _frames(tester);
          shell.openTopic(row);
          await _frames(tester);
          expect(find.byType(NestedRepliesReader), findsOneWidget);
          expect(
            shell.currentTopic!.readingPolicy.allowsChronologicalResume,
            isFalse,
          );
          treeReads = api.pluginReadPaths
              .where((path) => path.startsWith('/n/'))
              .length;
          api.siteConfigs[_site] = SiteConfig(
            plugins: PluginData.none.withValue(
              nestedRepliesSettingsKey,
              const NestedRepliesSettings(enabled: false),
            ),
          );
          gate.complete();
        },
      );
      await _frames(tester);
      expect(find.byType(NestedRepliesReader), findsNothing);
      expect(
        fixture.shell.currentTopic!.readingPolicy.allowsChronologicalResume,
        isTrue,
      );
      expect(
        fixture.api.pluginReadPaths
            .where((path) => path.startsWith('/n/'))
            .length,
        treeReads,
      );
      expect(renderedText('Start with the harbour entrance.'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'the alternate reader preserves ordinary post footer extensions',
    (tester) async {
      final fixture = await _pump(tester, desktop, postExtension: true);
      fixture.shell.openTopic(fixture.row);
      await _frames(tester);
      expect(find.byType(NestedRepliesReader), findsOneWidget);
      expect(find.text('Plugin footer on post 1'), findsOneWidget);
      expect(find.text('Plugin footer on post 3'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Plugin footer on post 4'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(NestedRepliesReader),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Plugin footer on post 4'), findsOneWidget);
      fixture.shell.setTopicPostSelectionEnabled(_site, 7, true);
      fixture.shell.selectAllLoadedTopicPosts(_site, 7);
      expect(
        fixture.shell.selectedTopicPosts(_site, 7).map((post) => post.id),
        [101, 103, 104, 102],
      );
      expect(fixture.shell.currentTopic!.stream, [101, 102, 103, 104]);
      await _frames(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'an explicit context link retains query intent in the canonical route',
    (tester) async {
      final fixture = await _pump(tester, desktop);
      fixture
          .api
          .pluginResponses['GET /n/harbour/7/context/3.json?sort=new&context=0&track_visit=true'] = {
        'topic': _topic(),
        'op_post': _post(1),
        'target_post': _post(3),
        'ancestor_chain': <Object?>[],
        'ancestors_truncated': false,
        'siblings': <String, Object?>{},
        'effective_sort': 'new',
        'message_bus_last_id': 45,
      };
      expect(
        await fixture.shell.openInAppLink(
          '$_site/t/harbour/7/3?sort=new&context=0',
        ),
        isTrue,
      );
      await _frames(tester);
      expect(find.byType(NestedRepliesReader), findsOneWidget);
      expect(fixture.shell.currentContent!.postNumber, 3);
      expect(fixture.shell.currentContent!.topicQuery, 'sort=new&context=0');
      expect(
        renderedText('Choose a sheltered berth before sunset.'),
        findsWidgets,
      );
      expect(
        fixture.api.pluginReadPaths,
        contains(
          '/n/harbour/7/context/3.json?sort=new&context=0&track_visit=true',
        ),
      );
      expect(fixture.shell.currentTopic!.stream, [101, 102, 103, 104]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  for (final depth in [1, 999]) {
    testWidgets(
      'legacy nested context link safely retains supported query intent at depth $depth',
      (tester) async {
        final fixture = await _pump(tester, desktop);
        final contextQuery = depth == 1 ? '&context=1' : '';
        final path =
            '/n/harbour/7/context/4.json?sort=new$contextQuery&track_visit=true';
        fixture.api.pluginResponses['GET $path'] = {
          'topic': _topic(),
          'op_post': _post(1),
          'target_post': _post(4),
          'ancestor_chain': [_post(3)],
          'ancestors_truncated': false,
          'siblings': <String, Object?>{},
          'effective_sort': 'new',
          'message_bus_last_id': 45,
        };
        expect(
          await fixture.shell.openInAppLink(
            '$_site/n/harbour/7/context/4?sort=new&collapse_replies=true&context=$depth',
          ),
          isTrue,
        );
        await _frames(tester);
        expect(find.byType(NestedRepliesReader), findsOneWidget);
        expect(fixture.shell.currentContent!.postNumber, 4);
        expect(
          fixture.shell.currentContent!.topicQuery,
          'sort=new&collapse_replies=true$contextQuery',
        );
        expect(fixture.api.pluginReadPaths, contains(path));
        expect(renderedText('Leave room for the boat astern.'), findsWidgets);
        expect(fixture.shell.currentTopic!.stream, [101, 102, 103, 104]);
        expect(
          await fixture.shell.openInAppLink(
            '$_site/n/harbour/7/context/invalid',
          ),
          isFalse,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }

  testWidgets('fresh authoritative mode omission retires the plugin reader', (
    tester,
  ) async {
    final fixture = await _pump(tester, desktop);
    fixture.shell.openTopic(fixture.row);
    await _frames(tester);
    expect(find.byType(NestedRepliesReader), findsOneWidget);
    final ordinary = _topic()
      ..remove('is_nested_view')
      ..remove('has_new_replies');
    fixture.api.topics[7] = _models.topic({
      ...ordinary,
      'post_stream': {
        'stream': [101, 102, 103, 104],
        'posts': [_post(1), _post(2), _post(3), _post(4)],
      },
    }, _site);
    final treeReads = fixture.api.pluginReadPaths
        .where((path) => path.startsWith('/n/'))
        .length;
    await fixture.shell.refreshCurrentTab();
    await _frames(tester);
    expect(find.byType(NestedRepliesReader), findsNothing);
    expect(
      fixture.shell.currentTopic!.readingPolicy.allowsChronologicalResume,
      isTrue,
    );
    expect(
      fixture.api.pluginReadPaths
          .where((path) => path.startsWith('/n/'))
          .length,
      treeReads,
    );
    expect(renderedText('Start with the harbour entrance.'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets(
    'actual session preserves core ownership and supplies enabled nested reply destinations',
    (tester) async {
      final fixture = await _pump(tester, desktop);
      final notification = DiscourseNotification(
        id: 10,
        typeId: const NotificationTypeId(2),
        topicId: 7,
        postNumber: 8,
        slug: 'harbour',
        data: const {'reply_to_post_number': 2, 'consolidated_count': 4},
      );
      final resolved = fixture.shell.pluginSession.resolveNotification(
        fixture.shell.plugins.registry,
        _site,
        notification,
      );
      expect(resolved.path, '/t/harbour/7/2?sort=new&collapse_replies=true');
      expect(resolved.presentation.phrase, '4 new replies to your post');
      final ordinary = DiscourseNotification(
        id: 11,
        typeId: const NotificationTypeId(2),
        topicId: 7,
        postNumber: 8,
        slug: 'harbour',
        data: const {'consolidated_count': 1, 'reply_to_post_number': 2},
      );
      expect(
        fixture.shell.pluginSession
            .resolveNotification(
              fixture.shell.plugins.registry,
              _site,
              ordinary,
            )
            .path,
        '/t/harbour/7/8',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<({ShellController shell, FakeDiscourseApi api, Topic row})> _pump(
  WidgetTester tester,
  Size size, {
  bool enabled = true,
  bool installed = true,
  Completer<void>? configGate,
  bool postExtension = false,
  Future<void> Function(ShellController shell, FakeDiscourseApi api, Topic row)?
  beforeSettle,
}) async {
  final config = SiteConfig(
    readTimeWordCount: 200,
    plugins: PluginData.none.withValue(
      nestedRepliesSettingsKey,
      NestedRepliesSettings(enabled: enabled),
    ),
  );
  final row = _models.topicSummary(_topic(), _site);
  final api = FakeDiscourseApi(
    models: _models,
    user: _user,
    siteConfigs: {_site: config},
    siteConfigGate: configGate,
    feeds: {
      '/latest.json': [row],
    },
    topics: {
      7: _models.topic({
        ..._topic(),
        'post_stream': {
          'stream': [101, 102, 103, 104],
          'posts': [_post(1), _post(2), _post(3), _post(4)],
        },
      }, _site),
    },
    pluginResponses: {
      'GET /n/harbour/7.json?sort=top&page=0&track_visit=true': _roots(),
      'GET /n/harbour/7.json?sort=top&page=0': _roots(),
    },
  );
  await pumpShell(
    tester,
    size,
    instances: [
      instance('meta.discourse.org').copyWith(user: _user, config: config),
    ],
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    beforeSettle: beforeSettle == null
        ? null
        : () async {
            final shell = tester
                .widget<ShellScope>(find.byType(ShellScope))
                .notifier!;
            await beforeSettle(shell, api, row);
          },
    pluginManifest: !installed
        ? const PluginManifest([])
        : postExtension
        ? const PluginManifest([nestedRepliesModule, _FooterModule()])
        : _manifest,
  );
  final shell = ShellScope.read(tester.element(primaryMainContent));
  await shell.forumSettings.setShared(
    const SharedAppearance(
      font: ForumFont.openSans,
      interfaceFont: ForumFont.openSans,
    ),
  );
  await tester.pump();
  return (shell: shell, api: api, row: row);
}

Map<String, dynamic> _topic() => {
  'id': 7,
  'title': _title,
  'slug': 'harbour',
  'is_nested_view': true,
  'has_new_replies': true,
  'highest_post_number': 4,
  'last_read_post_number': 2,
  'posts_count': 4,
  'word_count': 1200,
  'views': 25,
  'like_count': 4,
  'details': {
    'can_create_post': true,
    'can_edit': true,
    'can_move_posts': true,
    'participants': <Object?>[],
  },
};
const _bodies = {
  1: 'Start with the harbour entrance.',
  2: 'Check the tide before coming alongside.',
  3: 'Choose a sheltered berth before sunset.',
  4: 'Leave room for the boat astern.',
};
Map<String, dynamic> _post(int number) => {
  'id': 100 + number,
  'topic_id': 7,
  'post_number': number,
  'user_id': number == 1 ? 10 : 20 + number,
  'username': switch (number) {
    1 => 'captain',
    2 => 'navigator',
    3 => 'sailor',
    _ => 'deckhand',
  },
  'cooked': '<p>${_bodies[number]}</p>',
  'raw': _bodies[number],
  'can_edit': true,
  'can_delete': true,
  'reply_to_post_number': number == 4 ? 3 : 1,
  'direct_reply_count': number == 3 ? 1 : 0,
  'total_descendant_count': number == 3 ? 1 : 0,
  'children': number == 3 ? [_post(4)] : <Object?>[],
  'actions_summary': [
    {'id': 2, 'count': number == 3 ? 4 : 1, 'can_act': true},
  ],
};
Map<String, dynamic> _roots() => {
  'topic': _topic(),
  'op_post': _post(1),
  'roots': [_post(3), _post(2)],
  'page': 0,
  'has_more_roots': false,
  'sort': 'top',
  'effective_sort': 'top',
  'message_bus_last_id': 44,
  'pinned_post_ids': <int>[],
};
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> _export(WidgetTester tester, String name) async {
  if (Platform.environment['NESTED_REPLIES_INTEGRATION_EXPORT'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byWidgetPredicate((widget) => widget is RepaintBoundary).first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(
        '/private/tmp/nested-replies-integration-previews',
      );
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

final class _FooterModule implements PluginModule {
  const _FooterModule();

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('integration-footer'));

  @override
  void register(PluginRegistrar registrar) =>
      registrar.addCapability(const _FooterPlugin());
}

final class _FooterPlugin implements SitePlugin, PostFooterPlugin {
  const _FooterPlugin();

  @override
  String get name => 'integration-footer';

  @override
  Widget postFooter(String siteUrl, Post post) =>
      Text('Plugin footer on post ${post.postNumber}');
}
