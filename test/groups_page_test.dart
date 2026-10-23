import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/shell/groups_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/skeleton_expectations.dart';

const _support = Group(
  id: 1,
  name: 'support',
  fullName: 'Support Team',
  userCount: 12,
  canSeeMembers: true,
  bioCooked: '<p>People who help the community.</p>',
  isGroupUser: true,
);
const _moderators = Group(
  id: 2,
  name: 'moderators',
  userCount: 1,
  isGroupOwner: true,
);
const _members = [
  GroupMember(id: 1, username: 'sam'),
  GroupMember(id: 2, username: 'alex'),
  GroupMember(id: 3, username: 'chris'),
  GroupMember(id: 4, username: 'lee'),
];

void main() {
  setUpAll(() async {
    await (FontLoader(
      'PageHeaderReview',
    )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
  });
  for (final size in [const Size(390, 844), const Size(1100, 800)]) {
    testWidgets(
      'shared group header keeps controls while the title yields at $size',
      (tester) async {
        final capture = GlobalKey();
        await _pump(
          tester,
          RepaintBoundary(
            key: capture,
            child: ColoredBox(
              color: AppTheme.light.colorScheme.surface,
              child: GroupsPage(
                siteUrl: 'https://example.invalid',
                data: GroupsPageData(
                  loaded: true,
                  totalRows: 40,
                  groups: [
                    for (var i = 0; i < 40; i++)
                      Group(
                        id: i + 1,
                        name: 'sailing_$i',
                        fullName: 'Sailing community $i',
                        userCount: 12,
                      ),
                  ],
                ),
              ),
            ),
          ),
          fontFamily: 'PageHeaderReview',
          size: size,
          platform: size.width < 600
              ? TargetPlatform.iOS
              : TargetPlatform.macOS,
        );
        await tester.pumpAndSettle();
        final viewport = find.byKey(
          const PageStorageKey('groups-directory-scroll'),
        );
        final title = find.text('Groups');
        final filter = find.byKey(const ValueKey('groups-type-filter'));
        final position = tester
            .state<ScrollableState>(
              find
                  .descendant(of: viewport, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        final bounds = tester.getRect(viewport);
        Future<void> export(String state) async {
          final dir = Platform.environment['PAGE_HEADER_EXPORT_DIR'];
          if (dir == null) return;
          await tester.runAsync(() async {
            final image =
                await (capture.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(dir).create(recursive: true);
            await File(
              '$dir/groups-${size.width.toInt()}-$state.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        Future<void> wheel(double amount) async {
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: tester.getCenter(viewport),
              scrollDelta: Offset(0, amount),
            ),
          );
          await tester.pumpAndSettle();
        }

        await export('top');
        expect(title.hitTestable(), findsOneWidget);
        await wheel(400);
        expect(title.hitTestable(), findsNothing);
        expect(filter.hitTestable(), findsOneWidget);
        expect(tester.getRect(viewport), bounds);
        expect(position.pixels, 400);
        await export('down');
        await tester.pump(const Duration(milliseconds: 500));
        await wheel(-160);
        expect(title.hitTestable(), findsOneWidget);
        expect(filter.hitTestable(), findsOneWidget);
        await export('up');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [const Size(390, 844), const Size(1440, 1200)]) {
    testWidgets('group skeleton fills the page at $size', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        const GroupsPage(
          siteUrl: 'https://example.invalid',
          data: GroupsPageData(loading: true),
        ),
        size: size,
      );
      expectSkeletonFillsViewport(
        tester,
        label: 'Loading groups',
        bottom: size.height,
      );
      expect(find.bySemanticsLabel('Loading groups'), findsOneWidget);
      expect(find.byKey(const ValueKey('groups-show-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('groups-type-filter')), findsOneWidget);
      semantics.dispose();
    });
  }

  for (final size in [const Size(390, 844), const Size(1440, 1200)]) {
    testWidgets('loaded groups replace the skeleton in place at $size', (
      tester,
    ) async {
      const page = GroupsPage(
        siteUrl: 'https://example.invalid',
        data: GroupsPageData(loading: true),
      );
      // A real font, so the one-line bio stays one line at phone width.
      await _pump(
        tester,
        page,
        size: size,
        platform: TargetPlatform.iOS,
        fontFamily: 'PageHeaderReview',
      );
      final region = find.byType(DSkeletonRegion);
      final skeletonAvatar = tester.getRect(
        find.descendant(of: region, matching: find.byType(DSkeleton)).first,
      );
      final skeletonDivider = tester.getRect(
        find.descendant(of: region, matching: find.byType(DSeparator)).first,
      );

      final members = Completer<List<GroupMember>>();
      await _pump(
        tester,
        GroupsPage(
          siteUrl: 'https://example.invalid',
          data: const GroupsPageData(
            groups: [_support, _moderators],
            totalRows: 2,
            loaded: true,
          ),
          loadMemberPreview: (_) => members.future,
        ),
        size: size,
        platform: TargetPlatform.iOS,
        fontFamily: 'PageHeaderReview',
      );
      final row = find.byKey(const ValueKey('group-row-support'));
      final avatar = tester.getRect(
        find.descendant(of: row, matching: find.byType(DAvatar)).first,
      );
      final divider = tester.getRect(find.byType(DSeparator).first);
      expect(avatar, skeletonAvatar);
      expect(divider, skeletonDivider);

      // The member preview arrives after the rows: it must not push them.
      members.complete(_members);
      await tester.pumpAndSettle();
      expect(find.byType(DAvatarGroup), findsOneWidget);
      expect(tester.getRect(find.byType(DSeparator).first), divider);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (width, platform) in [
    (390.0, TargetPlatform.iOS),
    (700.0, TargetPlatform.android),
    (1400.0, TargetPlatform.macOS),
  ]) {
    testWidgets('directory is a divided list at $width on $platform', (
      tester,
    ) async {
      Group? opened;
      await _pump(
        tester,
        GroupsPage(
          siteUrl: 'https://example.invalid',
          data: const GroupsPageData(
            groups: [_support, _moderators],
            totalRows: 2,
            loaded: true,
          ),
          onOpenGroup: (group) => opened = group,
          loadMemberPreview: (_) async => _members,
        ),
        size: Size(width, 900),
        platform: platform,
      );
      await tester.pumpAndSettle();

      final first = tester.getRect(
        find.byKey(const ValueKey('group-row-support')),
      );
      final second = tester.getRect(
        find.byKey(const ValueKey('group-row-moderators')),
      );
      expect(first.left, second.left);
      expect(first.width, second.width);
      expect(first.bottom, lessThan(second.top));
      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('2 groups'), findsOneWidget);
      expect(find.text('@support'), findsOneWidget);
      expect(find.text('1 member'), findsOneWidget);
      expect(find.byType(DAvatarGroup), findsOneWidget);
      expect(
        tester.getRect(find.text('Member')).top,
        lessThan(
          tester.getRect(find.text('People who help the community.')).top,
        ),
      );
      expect(
        tester.getRect(find.text('12 members')).top,
        greaterThan(
          tester.getRect(find.text('People who help the community.')).bottom,
        ),
      );
      await tester.tap(find.text('Support Team'));
      expect(opened, same(_support));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'narrow RTL rows reflow badges and long identities at 200% text',
    (tester) async {
      await _pump(
        tester,
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: GroupsPage(
              siteUrl: 'https://example.invalid',
              data: GroupsPageData(
                loaded: true,
                totalRows: 1,
                groups: [
                  Group(
                    id: 1,
                    name: 'community-leads-with-long-names',
                    fullName: 'Community leadership team',
                    userCount: 123,
                    isGroupUser: true,
                  ),
                ],
              ),
            ),
          ),
        ),
        size: const Size(312, 1000),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final badge = tester.getRect(find.text('Member'));
      final name = tester.getRect(
        find.text('@community-leads-with-long-names'),
      );
      expect(badge.top, greaterThan(name.bottom));
      expect(badge.left, greaterThanOrEqualTo(16));
      expect(badge.right, lessThanOrEqualTo(296));
    },
  );

  testWidgets(
    'search, filter, creation, row keyboard navigation and pagination work',
    (tester) async {
      String? search;
      String? type;
      Group? opened;
      var created = 0;
      var more = 0;
      await _pump(
        tester,
        GroupsPage(
          siteUrl: 'https://example.invalid',
          data: const GroupsPageData(
            groups: [_support],
            typeFilters: ['my', 'public'],
            totalRows: 2,
            loaded: true,
            hasMore: true,
            canCreateGroup: true,
          ),
          onSearchChanged: (value) => search = value,
          onTypeChanged: (value) => type = value,
          onOpenGroup: (value) => opened = value,
          onCreateGroup: () => created++,
          onLoadMore: () => more++,
        ),
      );
      expect(find.byKey(const ValueKey('groups-search')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('groups-show-search')));
      await tester.pumpAndSettle();
      final input = tester.widget<DInput>(
        find.byKey(const ValueKey('groups-search')),
      );
      expect(input.focusNode?.hasFocus, isTrue);
      await tester.enterText(
        find.byKey(const ValueKey('groups-search')),
        '  support  ',
      );
      await tester.pump(const Duration(milliseconds: 301));
      expect(search, 'support');
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(search, '');
      await tester.tap(find.byKey(const ValueKey('groups-type-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My groups').last);
      await tester.pumpAndSettle();
      expect(type, 'my');
      await tester.tap(find.byKey(const ValueKey('create-group')));
      expect(created, 1);
      final rowFocus = tester
          .widget<FocusableActionDetector>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('group-row-support')),
                  matching: find.byType(FocusableActionDetector),
                )
                .first,
          )
          .focusNode!;
      rowFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened, same(_support));
      await tester.ensureVisible(
        find.byKey(const ValueKey('groups-load-more')),
      );
      await tester.tap(find.byKey(const ValueKey('groups-load-more')));
      expect(more, greaterThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
    },
  );

  for (final failed in [false, true]) {
    testWidgets(
      'scrolling to the end ${failed ? 'leaves a failed page to Try again' : 'requests the next page'}',
      (tester) async {
        var more = 0;
        await _pump(
          tester,
          GroupsPage(
            siteUrl: 'https://example.invalid',
            data: GroupsPageData(
              groups: [
                for (var id = 1; id <= 30; id++)
                  Group(id: id, name: 'group-$id'),
              ],
              totalRows: 60,
              loaded: true,
              hasMore: true,
              error: failed ? "Couldn't load more groups." : null,
              pageError: failed,
            ),
            onLoadMore: () => more++,
          ),
          size: const Size(390, 700),
        );

        final list = find.byType(CustomScrollView);
        await tester.fling(list, const Offset(0, -6000), 6000);
        await tester.pumpAndSettle();
        for (var drag = 0; drag < 5; drag++) {
          await tester.drag(list, const Offset(0, 40));
          await tester.drag(list, const Offset(0, -40));
          await tester.pumpAndSettle();
        }

        if (!failed) {
          expect(more, greaterThan(0));
          return;
        }
        expect(more, 0);
        await tester.tap(find.text('Try again'));
        await tester.pump();
        expect(more, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('filter clears to all groups on mobile', (tester) async {
    String? type = 'automatic';
    await _pump(
      tester,
      GroupsPage(
        siteUrl: 'https://example.invalid',
        data: const GroupsPageData(
          typeFilters: ['my', 'automatic'],
          type: 'automatic',
          loaded: true,
        ),
        onTypeChanged: (value) => type = value,
      ),
      size: const Size(390, 700),
      platform: TargetPlatform.iOS,
    );
    await tester.tap(find.byKey(const ValueKey('groups-type-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All groups').last);
    await tester.pumpAndSettle();
    expect(type, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search stays mounted while results load', (tester) async {
    var data = const GroupsPageData(groups: [_support], loaded: true);
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return GroupsPage(
            siteUrl: 'https://example.invalid',
            data: data,
            onSearchChanged: (_) {},
          );
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('groups-show-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('groups-search')),
      'moderators',
    );
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    update(
      () => data = const GroupsPageData(query: 'moderators', loading: true),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('groups-loading')), findsOneWidget);
    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(editable),
    );
    expect(editable.widget.controller.text, 'moderators');
    expect(editable.widget.focusNode.hasFocus, isTrue);
    update(
      () => data = const GroupsPageData(
        groups: [_moderators],
        query: 'moderators',
        loaded: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group-row-moderators')), findsOneWidget);
    expect(find.byType(DSkeletonRegion), findsNothing);
    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(editable),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('member previews are cached and hidden membership never loads', (
    tester,
  ) async {
    var calls = 0;
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return GroupsPage(
            siteUrl: 'https://example.invalid',
            data: const GroupsPageData(
              groups: [
                _support,
                _moderators,
                Group(id: 3, name: 'private'),
              ],
              loaded: true,
            ),
            loadMemberPreview: (_) async {
              calls++;
              return _members;
            },
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    update(() {});
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(DAvatarGroup), findsOneWidget);
    expect(find.text('Members hidden'), findsOneWidget);
  });

  testWidgets('late member previews do not leak into a different site', (
    tester,
  ) async {
    final pending = Completer<List<GroupMember>>();
    var siteUrl = 'https://one.example';
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return GroupsPage(
            siteUrl: siteUrl,
            data: const GroupsPageData(groups: [_support], loaded: true),
            loadMemberPreview: (_) =>
                siteUrl.contains('one') ? pending.future : Future.value([]),
          );
        },
      ),
    );
    update(() => siteUrl = 'https://two.example');
    await tester.pumpAndSettle();
    pending.complete(_members);
    await tester.pumpAndSettle();
    expect(find.byType(DAvatarGroup), findsNothing);
  });

  testWidgets('empty directory remains scrollable', (tester) async {
    await _pump(
      tester,
      const GroupsPage(
        siteUrl: 'https://example.invalid',
        data: GroupsPageData(loaded: true, query: 'missing'),
      ),
      size: const Size(390, 700),
    );
    expect(find.text('No groups match these filters.'), findsOneWidget);
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1000, 760),
  TargetPlatform platform = TargetPlatform.macOS,
  String? fontFamily,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(
        platform: platform,
        textTheme: fontFamily == null
            ? null
            : AppTheme.light.textTheme.apply(fontFamily: fontFamily),
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}
