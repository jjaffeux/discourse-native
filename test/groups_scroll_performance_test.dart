import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/shell/groups_page.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

Set<RenderObject> _artwork(Finder root) => find
    .descendant(
      of: root,
      matching: find.byWidgetPredicate(
        (widget) => widget is RenderObjectWidget,
      ),
    )
    .evaluate()
    .map((element) => (element as RenderObjectElement).renderObject)
    // PaintingContext reports compositing retained boundaries too. Count only
    // artwork painted inside them, not reuse of an existing layer.
    .where((object) => !object.isRepaintBoundary)
    .toSet();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifications = MethodChannel(
    'org.discourse.native/notification_opens',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(notifications, (_) async => null);
  });
  tearDown(() => messenger.setMockMethodCallHandler(notifications, null));

  {
    testWidgets(
      'groups cache artwork during scrolling (flat)',
      (tester) async {
        final api = _GroupsApi();
        await pumpShell(
          tester,
          defaultTargetPlatform == TargetPlatform.macOS ? laptop : phone,
          instances: [instance('meta.discourse.org')],
          api: api,
        );
        final shell = ShellScope.read(tester.element(primaryMainContent));
        await shell.forumSettings.setShared(
          shell.forumSettings.shared.copyWith(),
        );
        shell.selectDestination(
          const SidebarDestination(
            id: 'groups',
            label: 'Groups',
            icon: DIcons.users,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(GroupsPage), findsOneWidget);
        expect(find.byType(DAvatarGroup), findsWidgets);
        expect(
          api.previews.length,
          lessThan(20),
          reason: 'The directory must stay lazy.',
        );
        final scrollable = find
            .descendant(
              of: find.byType(GroupsPage),
              matching: find.byType(Scrollable),
            )
            .first;
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(position.maxScrollExtent, greaterThan(2000));
        // Paint and resolve the same rows before recording retained artwork.
        for (final offset in [1000.0, 1200.0, 1000.0]) {
          position.jumpTo(offset);
          await tester.pumpAndSettle();
        }
        final viewport = tester.getRect(scrollable);
        final filter = find.byKey(const ValueKey('groups-type-filter'));
        final controls = _artwork(filter);
        final rowFinder = find.descendant(
          of: find.byType(GroupsPage),
          matching: find.byType(DItem),
        );
        final rows = _artwork(rowFinder);
        final retained = find
            .descendant(
              of: rowFinder,
              matching: find.byWidgetPredicate((_) => true),
            )
            .evaluate()
            .toSet();
        var controlPaints = 0;
        var rowPaints = 0;
        var builds = 0;
        var totalPaints = 0;
        final oldPaint = debugOnProfilePaint;
        final oldBuild = debugOnRebuildDirtyWidget;
        debugOnProfilePaint = (object) {
          oldPaint?.call(object);
          totalPaints++;
          if (controls.contains(object)) controlPaints++;
          if (rows.contains(object)) rowPaints++;
        };
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          oldBuild?.call(element, builtOnce);
          if (retained.contains(element)) builds++;
        };
        try {
          for (final direction in [-1.0, 1.0]) {
            await tester.pump(const Duration(milliseconds: 500));
            final before = position.pixels;
            final gesture = await tester.startGesture(
              tester.getCenter(scrollable),
            );
            await gesture.moveBy(Offset(0, 30 * direction));
            await tester.pump();
            for (var frame = 0; frame < 30; frame++) {
              await gesture.moveBy(Offset(0, 4 * direction));
              await tester.pump(const Duration(milliseconds: 16));
            }
            await gesture.cancel();
            await tester.pumpAndSettle();
            expect(
              position.pixels,
              direction < 0
                  ? greaterThan(before + 100)
                  : lessThan(before - 100),
            );
            expect(tester.getRect(scrollable), viewport);
            expect(filter.hitTestable(), findsOneWidget);
            if (defaultTargetPlatform != TargetPlatform.macOS) {
              expect(
                tester.widget<DMobileDock>(find.byType(DMobileDock)).collapsed,
                direction < 0,
              );
            }
          }
        } finally {
          debugOnProfilePaint = oldPaint;
          debugOnRebuildDirtyWidget = oldBuild;
        }
        debugPrint(
          'GROUPS_SCROLL_PROFILE ${jsonEncode({'platform': defaultTargetPlatform.name, 'controlPaints': controlPaints, 'rowPaints': rowPaints, 'retainedBuilds': builds, 'totalPaints': totalPaints, 'previewRequests': api.previews.length})}',
        );
        expect(totalPaints, greaterThan(0));
        expect(
          controlPaints,
          0,
          reason: 'Scrolling must reuse the controls artwork.',
        );
        expect(api.previews.values, everyElement(1));
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      }),
    );
  }
}

class _GroupsApi extends FakeDiscourseApi {
  _GroupsApi() : super(feeds: const {'/latest.json': []});
  final previews = <String, int>{};

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final uri = Uri.parse(path);
    if (uri.path == '/groups.json') {
      return {
        'groups': [
          for (var id = 0; id < 100; id++)
            {
              'id': id + 1,
              'name': 'sailing_$id',
              'full_name': 'Sailing community $id',
              'bio_cooked':
                  '<p>Meet other sailors, share your adventures and help the community.</p>',
              'user_count': 12,
              'can_see_members': true,
              'is_group_user': id.isEven,
            },
        ],
        'total_rows_groups': 100,
      };
    }
    if (uri.path.endsWith('/members.json')) {
      previews.update(uri.path, (count) => count + 1, ifAbsent: () => 1);
      return {
        'members': [
          for (final (id, name) in ['sam', 'alex', 'chris', 'lee'].indexed)
            {'id': id + 1, 'username': name},
        ],
        'meta': {'total': 12, 'limit': 4, 'offset': 0},
      };
    }
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }
}
