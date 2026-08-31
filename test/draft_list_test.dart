import 'dart:async';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/app_shortcuts.dart';
import 'package:discourse_native/src/data/emoji_cache.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/draft_list.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/topic_create_button.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:discourse_native/src/theme/d_tooltip.dart';
import 'package:flutter/material.dart'
    show
        ConstrainedBox,
        FilledButton,
        Focus,
        InkWell,
        MaterialApp,
        MouseRegion,
        Row,
        Size,
        Theme,
        ValueKey,
        WidgetState;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';
const _draft = UserDraft(
  key: 'new_topic',
  sequence: 4,
  data: ComposerDraft(
    reply: 'A draft :smiley: from another device',
    action: ComposerDraft.createTopicAction,
    title: 'Native :sparkles: drafts page',
    categoryId: 5,
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('topic creation controls', () {
    testWidgets('show the core label, icon, colors, and shortcut when wide', (
      tester,
    ) async {
      await _pump(tester);

      final button = tester.widget<FilledButton>(
        find.byKey(TopicCreateButton.buttonKey),
      );
      final theme = Theme.of(
        tester.element(find.byKey(TopicCreateButton.buttonKey)),
      );
      expect(find.text('New topic'), findsOneWidget);
      expect(
        button.style?.backgroundColor?.resolve(<WidgetState>{}),
        theme.colorScheme.primary,
      );
      expect(
        button.style?.foregroundColor?.resolve(<WidgetState>{}),
        theme.colorScheme.onPrimary,
      );
      expect(
        tester
            .widget<DTooltip>(
              find.ancestor(
                of: find.byKey(TopicCreateButton.buttonKey),
                matching: find.byType(DTooltip),
              ),
            )
            .shortcut,
        const DShortcut(newTopicShortcut),
      );
      expect(
        find.descendant(
          of: find.byKey(TopicCreateButton.buttonKey),
          matching: find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon == DIcons.farPenToSquare,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('hide only the label below the small breakpoint', (
      tester,
    ) async {
      await _pump(tester, size: const Size(390, 844));
      await tester.tap(find.byKey(const ValueKey('latest')));
      await tester.pumpAndSettle();

      expect(find.byKey(TopicCreateButton.buttonKey), findsOneWidget);
      expect(find.text('New topic'), findsNothing);
      expect(
        find.ancestor(
          of: find.byKey(TopicCreateButton.buttonKey),
          matching: find.byType(DTooltip),
        ),
        findsOneWidget,
      );
    });
  });

  group('recent-draft menu', () {
    testWidgets('loads and resumes a recent draft', (tester) async {
      final fixture = await _pump(tester);

      expect(fixture.api.userDraftRequests, isEmpty);
      await tester.tap(find.byKey(TopicCreateButton.draftsButtonKey));
      await tester.pumpAndSettle();

      expect(fixture.api.userDraftRequests, [
        (siteUrl: _siteUrl, offset: 0, limit: 30),
      ]);
      final row = find.byKey(const ValueKey('recent-draft-new_topic'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(
          of: row,
          matching: find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon == DIcons.layerGroup,
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      final shell = ShellScope.read(tester.element(find.byType(ComposerPanel)));
      expect(
        shell.visibleComposer?.title.text,
        'Native :sparkles: drafts page',
      );
      expect(shell.visibleComposer?.draftSequence, 4);
    });

    testWidgets('closes when its chevron is pressed again', (tester) async {
      final fixture = await _pump(tester);
      final button = find.byKey(TopicCreateButton.draftsButtonKey);
      final row = find.byKey(const ValueKey('recent-draft-new_topic'));

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(row, findsOneWidget);
      expect(fixture.api.userDraftRequests, hasLength(1));

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(row, findsNothing);
      expect(fixture.api.userDraftRequests, hasLength(1));
    });

    testWidgets('matches core draft icons and the four-row limit', (
      tester,
    ) async {
      final drafts = [
        _draft,
        const UserDraft(
          key: 'new_private_message_1',
          sequence: 5,
          data: ComposerDraft(reply: 'Private draft', title: 'A message'),
        ),
        for (var index = 1; index <= 4; index++)
          UserDraft(
            key: 'topic_$index',
            sequence: index,
            data: ComposerDraft(reply: 'Reply $index'),
            topicId: index,
            title: 'Reply draft $index',
            slug: 'reply-draft-$index',
          ),
      ];
      await _pump(tester, draftCount: drafts.length, userDrafts: drafts);

      await tester.tap(find.byKey(TopicCreateButton.draftsButtonKey));
      await tester.pumpAndSettle();

      final privateRow = find.byKey(
        const ValueKey('recent-draft-new_private_message_1'),
      );
      final replyRow = find.byKey(const ValueKey('recent-draft-topic_1'));
      expect(privateRow, findsOneWidget);
      expect(replyRow, findsOneWidget);
      expect(
        find.descendant(
          of: privateRow,
          matching: find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon == DIcons.envelope,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: replyRow,
          matching: find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon == DIcons.reply,
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('recent-draft-topic_3')), findsNothing);
      expect(find.text('+2 other drafts'), findsOneWidget);
      expect(find.text('view all drafts'), findsOneWidget);

      await tester.tap(find.text('view all drafts'));
      await tester.pumpAndSettle();

      expect(find.byType(DraftListView), findsOneWidget);
    });
  });

  group('draft-list entry points', () {
    testWidgets('show the count as plain sidebar trailing text', (
      tester,
    ) async {
      await _pump(tester);

      final count = find.descendant(
        of: find.byType(InstanceSidebar),
        matching: find.text('1'),
      );

      expect(count, findsOneWidget);
      Object? parent;
      tester.element(count).visitAncestorElements((element) {
        parent = element.widget;
        return false;
      });
      expect(parent, isA<Row>());
    });

    testWidgets('open the account-backed page from the sidebar', (
      tester,
    ) async {
      final fixture = await _pump(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(InstanceSidebar),
          matching: find.text('Drafts'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DraftListView), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TopicTitle &&
              widget.title == 'Native :sparkles: drafts page',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(DraftListView),
          matching: find.text('Support'),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TopicTitle &&
              widget.title == 'A draft :smiley: from another device',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<SiteEmojiImage>(find.byType(SiteEmojiImage))
            .map((emoji) => emoji.name),
        ['sparkles', 'smiley'],
      );
      expect(find.byTooltip('Edit draft'), findsOneWidget);
      expect(find.byTooltip('Remove draft'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DraftListView),
          matching: find.byType(UserMenuAvatar),
        ),
        findsNothing,
      );
      expect(fixture.api.userDraftRequests, [
        (siteUrl: _siteUrl, offset: 0, limit: 30),
      ]);
    });

    testWidgets('open the same page from the profile row', (tester) async {
      await _pump(tester);

      await tester.tap(find.byKey(UserMenuButton.avatarKey));
      await tester.pumpAndSettle();
      final profileTab = find.byTooltip('Profile');
      await tester.tap(
        profileTab.evaluate().isEmpty ? find.text('Profile').last : profileTab,
      );
      await tester.pumpAndSettle();
      final panelDrafts = find.descendant(
        of: find.byType(UserMenuPanel),
        matching: find.text('Drafts'),
      );
      await tester.tap(
        panelDrafts.evaluate().isEmpty ? find.text('Drafts').last : panelDrafts,
      );
      await tester.pumpAndSettle();

      expect(find.byType(UserMenuPanel), findsNothing);
      expect(find.byType(DraftListView), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TopicTitle &&
              widget.title == 'Native :sparkles: drafts page',
        ),
        findsOneWidget,
      );
    });
  });

  group('draft-list presentation', () {
    testWidgets('uses wide draft-row skeletons while loading', (tester) async {
      final gate = Completer<void>();
      await _pump(tester, userDraftGate: gate);
      final semantics = tester.ensureSemantics();

      try {
        await tester.tap(
          find.descendant(
            of: find.byType(InstanceSidebar),
            matching: find.text('Drafts'),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('draft-list-loading-skeleton')),
          findsOneWidget,
        );
        expect(
          tester
              .getSize(
                find.byKey(
                  const ValueKey('draft-list-loading-skeleton-content'),
                ),
              )
              .height,
          greaterThanOrEqualTo(
            tester
                    .getSize(
                      find.byKey(const ValueKey('draft-list-loading-skeleton')),
                    )
                    .height -
                36,
          ),
        );
        final skeletonRows = find.descendant(
          of: find.byKey(const ValueKey('draft-list-loading-skeleton')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ConstrainedBox &&
                widget.constraints.minHeight ==
                    DraftListView.wideRowMinimumHeight,
          ),
        );
        final skeletonRowCount = skeletonRows.evaluate().length;
        expect(skeletonRowCount, greaterThan(0));
        for (var index = 0; index < skeletonRowCount; index += 1) {
          expect(
            tester.getSize(skeletonRows.at(index)).height,
            greaterThanOrEqualTo(DraftListView.wideRowMinimumHeight),
          );
        }
        expect(find.bySemanticsLabel('Loading drafts'), findsOneWidget);

        gate.complete();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('draft-list-loading-skeleton')),
          findsNothing,
        );
        expect(find.byTooltip('Edit draft'), findsOneWidget);
        final draftRow = find.ancestor(
          of: find.byTooltip('Edit draft'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ConstrainedBox &&
                widget.constraints.minHeight ==
                    DraftListView.wideRowMinimumHeight,
          ),
        );
        expect(
          tester.getSize(draftRow.first).height,
          greaterThanOrEqualTo(DraftListView.wideRowMinimumHeight),
        );
      } finally {
        try {
          if (!gate.isCompleted) {
            gate.complete();
            await tester.pumpAndSettle();
          }
        } finally {
          semantics.dispose();
        }
      }
    });

    testWidgets('exposes 44-pixel compact actions to the keyboard', (
      tester,
    ) async {
      await _pump(tester, size: const Size(390, 844));
      final controller = ShellScope.read(
        tester.element(find.byType(MaterialApp)),
      );
      controller.openDrafts(_siteUrl);
      await tester.pumpAndSettle();

      final edit = find.byTooltip('Edit draft');
      final remove = find.byTooltip('Remove draft');
      expect(tester.getSize(edit), const Size.square(44));
      expect(tester.getSize(remove), const Size.square(44));
      final row = find.ancestor(
        of: edit,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ConstrainedBox &&
              widget.constraints.minHeight ==
                  DraftListView.compactRowMinimumHeight,
        ),
      );
      expect(
        tester.getSize(row.first).height,
        greaterThanOrEqualTo(DraftListView.compactRowMinimumHeight),
      );

      await _focusDraftAction(tester, remove);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(find.text('Remove draft?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await _focusDraftAction(tester, edit);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
    });

    testWidgets('keeps compact skeletons at the compact row minimum', (
      tester,
    ) async {
      final gate = Completer<void>();
      await _pump(tester, size: const Size(390, 844), userDraftGate: gate);

      try {
        await tester.tap(
          find.descendant(
            of: find.byType(InstanceSidebar),
            matching: find.text('Drafts'),
          ),
        );
        await tester.pump();

        final skeletonRows = find.descendant(
          of: find.byKey(const ValueKey('draft-list-loading-skeleton')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ConstrainedBox &&
                widget.constraints.minHeight ==
                    DraftListView.compactRowMinimumHeight,
          ),
        );
        final skeletonRowCount = skeletonRows.evaluate().length;
        expect(skeletonRowCount, greaterThan(0));
        for (var index = 0; index < skeletonRowCount; index += 1) {
          expect(
            tester.getSize(skeletonRows.at(index)).height,
            greaterThanOrEqualTo(DraftListView.compactRowMinimumHeight),
          );
        }

        gate.complete();
        await tester.pumpAndSettle();
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
          await tester.pumpAndSettle();
        }
      }
    });
  });

  group('draft lifecycle', () {
    testWidgets('resumes a supported draft in the composer', (tester) async {
      await _pump(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(InstanceSidebar),
          matching: find.text('Drafts'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit draft'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      final shell = ShellScope.read(tester.element(find.byType(ComposerPanel)));
      expect(
        shell.visibleComposer?.title.text,
        'Native :sparkles: drafts page',
      );
      expect(
        shell.visibleComposer?.text.text,
        'A draft :smiley: from another device',
      );
      expect(shell.visibleComposer?.draftSequence, 4);
    });

    testWidgets('removes a draft from the page and server count', (
      tester,
    ) async {
      final fixture = await _pump(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(InstanceSidebar),
          matching: find.text('Drafts'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('No drafts yet'), findsOneWidget);
      expect(fixture.api.userDraftsDeleted, [
        (siteUrl: _siteUrl, draftKey: 'new_topic', sequence: 4),
      ]);
    });
  });
}

typedef _Fixture = ({FakeDiscourseApi api});

Future<_Fixture> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  int draftCount = 1,
  List<UserDraft> userDrafts = const [_draft],
  Completer<void>? userDraftGate,
}) async {
  final previousEmojiCache = EmojiCache.instance;
  final emojiCache = EmojiCache(
    client: MockClient((_) async => http.Response('', 404)),
  );
  EmojiCache.instance = emojiCache;
  addTearDown(() {
    emojiCache.clear();
    EmojiCache.instance = previousEmojiCache;
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final site = instance('meta.discourse.org').copyWith(
    user: DiscourseUser(id: 7, username: 'reader', draftCount: draftCount),
  );
  final api = FakeDiscourseApi(
    user: site.user,
    totals: const NotificationTotals(),
    userDraftList: userDrafts,
    userDraftGate: userDraftGate,
    categoryList: const [
      TopicCategory(id: 5, name: 'Support', color: '0088CC'),
    ],
    feeds: const {'/latest.json': []},
    creatableFeedPaths: const {'/latest.json'},
    // Only registered shortcodes may be drawn, so the names the draft
    // fixtures carry must exist in the site's catalog.
    emojisBySite: {
      _siteUrl: const [
        SiteEmoji(name: 'sparkles', url: '/images/emoji/sparkles.png'),
        SiteEmoji(name: 'smiley', url: '/images/emoji/smiley.png'),
      ],
    },
  );
  final authenticator = FakeAuthenticator()..keys[_siteUrl] = 'api-key';
  await tester.pumpWidget(
    DiscourseApp(
      store: FakeInstanceStore([site]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
    ),
  );
  await tester.pumpAndSettle();
  return (api: api);
}

Future<void> _focusDraftAction(WidgetTester tester, Finder action) async {
  final inkWell = find.descendant(of: action, matching: find.byType(InkWell));
  expect(inkWell, findsOneWidget);
  final focusChild = find
      .descendant(of: inkWell, matching: find.byType(MouseRegion))
      .first;
  final focus = Focus.of(tester.element(focusChild));
  focus.requestFocus();
  await tester.pumpAndSettle();
  expect(focus.hasPrimaryFocus, isTrue);
}
