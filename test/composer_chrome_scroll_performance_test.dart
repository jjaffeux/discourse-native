import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer/header.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  for (final (mobile, keyboard) in [(false, 0.0), (true, 0.0), (true, 336.0)]) {
    testWidgets(
      '${mobile ? 'mobile' : 'desktop'} scrolling at keyboard $keyboard retains composer chrome paint',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        const user = DiscourseUser(
          id: 7,
          username: 'sam',
          canCreateTopic: true,
        );
        final shell = ShellController(
          mobileNavigationEnabled: mobile,
          forumTabsEnabled: false,
          instanceStore: FakeInstanceStore([
            instance('meta.discourse.org').copyWith(user: user),
          ]),
          api: FakeDiscourseApi(
            user: user,
            feeds: const {'/latest.json': []},
            creatableFeedPaths: const {'/latest.json'},
          ),
          authenticator: FakeAuthenticator()
            ..keys['https://meta.discourse.org'] = 'key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
        );
        addTearDown(shell.dispose);
        await shell.load();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = mobile
            ? const Size(390, 844)
            : const Size(1280, 850);
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ShellScope(
            controller: shell,
            child: MaterialApp(
              theme: AppTheme.light.copyWith(
                platform: mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
              ),
              home: const AdaptiveShell(),
            ),
          ),
        );
        await shell.openNewTopicFromSidebar();
        await tester.pumpAndSettle();
        final composer = shell.visibleComposer!;
        composer.title.text = 'A long topic';
        final source = List.generate(
          120,
          (i) => 'Paragraph $i with enough text to wrap in the editor.',
        ).join('\n\n');
        composer.text.value = TextEditingValue(
          text: source,
          selection: const TextSelection.collapsed(offset: 0),
        );
        composer.focus.unfocus();
        await tester.pumpAndSettle();
        final scroll = mobile
            ? tester
                  .widget<CustomScrollView>(
                    find.byKey(const ValueKey('composer-mobile-scroll')),
                  )
                  .controller!
            : composer.text.imageScrollController!;
        scroll.jumpTo(100);
        await tester.pumpAndSettle();
        final controls = <RenderObject>{};
        void collect(RenderObject object) {
          controls.add(object);
          object.visitChildren(collect);
        }

        for (final element
            in find
                .descendant(
                  of: find.byType(ComposerPanel),
                  matching: find.byType(DButton),
                )
                .evaluate()) {
          collect(element.findRenderObject()!);
        }
        expect(find.byType(ComposerHeader), findsOneWidget);
        expect(controls, isNotEmpty);
        final painted = <RenderObject>[];
        final previous = debugOnProfilePaint;
        debugOnProfilePaint = (object) {
          previous?.call(object);
          if (controls.contains(object)) painted.add(object);
        };
        try {
          for (final delta in [24.0, 24.0, -24.0, -24.0]) {
            final before = scroll.offset;
            scroll.position.pointerScroll(delta);
            await tester.pump();
            await tester.pump();
            expect(scroll.offset, closeTo(before + delta, .01));
          }
        } finally {
          debugOnProfilePaint = previous;
        }
        expect(composer.raw, source);
        expect(
          painted,
          isEmpty,
          reason: '${painted.length} control paints during scrolling',
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(composer.flushDraft);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
