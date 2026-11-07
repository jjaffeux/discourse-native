import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

Set<RenderObject> _artwork(Finder finder) {
  final objects = <RenderObject>{};
  void collect(RenderObject object) {
    if (!object.isRepaintBoundary) objects.add(object);
    object.visitChildren(collect);
  }

  for (final element in finder.evaluate()) {
    collect(element.findRenderObject()!);
  }
  return objects;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifications = MethodChannel(
    'org.discourse.native/notification_opens',
  );
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, null);
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    testWidgets('sidebar scrolling isolates fixed artwork on $platform', (
      tester,
    ) async {
      const header = ValueKey('fixed-header');
      const footer = ValueKey('fixed-footer');
      const page = ValueKey('reading-page');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: Row(
              children: [
                DSidebarProvider(
                  mobileBreakpoint: 0,
                  child: DSidebar(
                    collapsible: DSidebarCollapsible.none,
                    header: DSidebarHeader(
                      child: DButton(
                        key: header,
                        label: const Text('Community'),
                        onPressed: () {},
                      ),
                    ),
                    footer: DSidebarFooter(
                      child: DButton(
                        key: footer,
                        label: const Text('Account'),
                        onPressed: () {},
                      ),
                    ),
                    child: DSidebarContent.slivers(
                      slivers: [
                        for (final section in ['Categories', 'Tags'])
                          DSidebarGroup.sliver(
                            header: DSidebarGroupLabel(child: Text(section)),
                            sliver: DSidebarMenu.sliverBuilder(
                              itemCount: 100,
                              itemBuilder: (context, index) =>
                                  DSidebarMenuButton(
                                    onPressed: () {},
                                    child: Text('$section $index'),
                                  ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Expanded(child: Text('Reading a discussion', key: page)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fixed = _artwork(
        find.byWidgetPredicate(
          (widget) => [header, footer, page].contains(widget.key),
        ),
      );
      expect(fixed, isNotEmpty);
      final controller = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      // Settle the heading's initial pinned state before sampling scrolls.
      controller.jumpTo(80);
      await tester.pumpAndSettle();
      final previous = debugOnProfilePaint;
      var paints = 0;
      debugOnProfilePaint = (object) {
        previous?.call(object);
        if (fixed.contains(object)) paints++;
      };
      try {
        for (var frame = 1; frame <= 8; frame++) {
          controller.jumpTo(80 + frame * 8);
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(controller.offset, 144);
        expect(paints, 0, reason: 'Only the scrolling body needs repainting');
        expect(tester.takeException(), isNull);
      } finally {
        debugOnProfilePaint = previous;
      }
    });

    testWidgets(
      'sidebar toggles retain rows and scroll position on $platform',
      (tester) async {
        final desktop = platform == TargetPlatform.macOS;
        final user = DiscourseUser(
          id: 7,
          username: 'reader',
          sidebarCategoryIds: [for (var id = 1; id <= 60; id++) id],
        );
        final categories = [
          for (var id = 1; id <= 60; id++)
            TopicCategory(
              id: id,
              name: 'Category $id',
              slug: 'category-$id',
              color: '0088cc',
            ),
        ];
        if (desktop) {
          await pumpShell(
            tester,
            const Size(1440, 844),
            instances: [instance('meta.discourse.org').copyWith(user: user)],
            authenticator: FakeAuthenticator()
              ..keys['https://meta.discourse.org'] = 'key',
            api: FakeDiscourseApi(
              user: user,
              feeds: const {'/latest.json': []},
              feedCategoriesByPath: {'/latest.json': categories},
            ),
          );
        } else {
          await pumpMobileShellFixture(
            tester,
            user: user,
            sidebarCategories: categories,
          );
        }
        final shell = ShellScope.read(
          tester.element(find.byType(AdaptiveShell)),
        );
        Future<void> toggle() async {
          if (desktop) {
            await tester.tap(find.byKey(const ValueKey('rail-sidebar-toggle')));
          } else {
            shell.toggleMobileSidebar();
          }
          await tester.pumpAndSettle();
        }

        if (!desktop) await toggle();
        final viewport = find
            .descendant(
              of: find.byType(InstanceSidebar),
              matching: find.byType(CustomScrollView),
            )
            .first;
        final controller = tester
            .widget<CustomScrollView>(viewport)
            .controller!;
        controller.jumpTo(200);
        await tester.pumpAndSettle();
        final previous = debugOnRebuildDirtyWidget;
        var rowBuilds = 0;
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          previous?.call(element, builtOnce);
          if (element.widget is SidebarDestinationTile) rowBuilds++;
        };
        try {
          await toggle();
          await toggle();
          expect(
            tester.widget<CustomScrollView>(viewport).controller,
            same(controller),
          );
          expect(controller.offset, 200);
          expect(
            rowBuilds,
            0,
            reason: 'Visibility does not change destinations',
          );
          expect(tester.takeException(), isNull);
        } finally {
          debugOnRebuildDirtyWidget = previous;
        }
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
