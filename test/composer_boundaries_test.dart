import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/composer_placement.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_presentation.dart';
import 'package:discourse_native/src/shell/composer_presentation_controller.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _topic = Topic(id: 1, title: 'A topic to read', slug: 'a-topic');
const _captureKey = ValueKey('composer-boundary-capture');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final messages in [false, true]) {
    for (final (theme, direction) in [
      (AppTheme.light, TextDirection.ltr),
      (AppTheme.dark, TextDirection.ltr),
      (AppTheme.dark, TextDirection.rtl),
    ]) {
      testWidgets(
        '${messages ? 'messages' : 'topics'} paint one composer boundary in ${theme.brightness.name} ${direction.name}',
        (tester) async {
          final (shell, presentation) = await _pump(
            tester,
            theme: theme,
            direction: direction,
            messages: messages,
          );
          for (final placement in ComposerPlacement.values) {
            presentation.dock(placement);
            await tester.pumpAndSettle();
            await _expectComposerBoundary(tester, theme, placement);
          }

          if (!messages) {
            presentation.dock(ComposerPlacement.right);
            shell.openTopicFromList(_topic);
            await tester.pumpAndSettle();
            final list = tester.getRect(
              find.byKey(const ValueKey('inbox-topic-list-pane')),
            );
            await _expectLine(
              tester,
              theme,
              axis: Axis.vertical,
              position: direction == TextDirection.ltr
                  ? list.right - 1
                  : list.left,
              samples: [list.top + 8, list.top + 180, list.bottom - 80],
            );
            await _expectComposerBoundary(
              tester,
              theme,
              ComposerPlacement.right,
            );

            // The list's divider disappears when only the topic reader fits.
            tester.view.physicalSize = const Size(1100, 800);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('inbox-list-resize-handle')),
              findsNothing,
            );
            await _expectComposerBoundary(
              tester,
              theme,
              ComposerPlacement.right,
            );
          }
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }
  }
}

Future<void> _expectComposerBoundary(
  WidgetTester tester,
  ThemeData theme,
  ComposerPlacement placement,
) async {
  final panel = tester.getRect(find.byType(ComposerPanel));
  final handle = find.byWidgetPredicate(
    (widget) =>
        widget is DResizableHandle && widget.semanticLabel == 'Resize composer',
  );
  final divider = tester.getCenter(handle);
  await _expectLine(
    tester,
    theme,
    axis: placement.isSide ? Axis.vertical : Axis.horizontal,
    position: (placement.isSide ? divider.dx : divider.dy).floorToDouble(),
    samples: placement.isSide
        ? [panel.top + 8, panel.top + 100, panel.top + 240, panel.bottom - 80]
        : [panel.left + 8, panel.center.dx, panel.right - 8],
  );
}

// Inspect the painted seam, including its neighbors: checking only the
// composer's decoration misses borders painted by the reader underneath it.
Future<void> _expectLine(
  WidgetTester tester,
  ThemeData theme, {
  required Axis axis,
  required double position,
  required List<double> samples,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final pixels = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      return (
        image.width,
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
      );
    } finally {
      image.dispose();
    }
  });
  final (width, data) = pixels!;
  for (final sample in samples) {
    final colors = <Color>[];
    for (var delta = -2; delta <= 2; delta++) {
      final x = (axis == Axis.vertical ? position + delta : sample).floor();
      final y = (axis == Axis.vertical ? sample : position + delta).floor();
      final offset = (y * width + x) * 4;
      colors.add(
        Color.fromARGB(
          data.getUint8(offset + 3),
          data.getUint8(offset),
          data.getUint8(offset + 1),
          data.getUint8(offset + 2),
        ),
      );
    }
    expect(
      colors[2],
      theme.shell.divider,
      reason: 'Missing divider at $position, $sample',
    );
    expect(
      colors.where((color) => color == theme.shell.divider),
      hasLength(1),
      reason:
          'Extra border beside the $axis divider at $position, $sample: $colors',
    );
  }
}

Future<(ShellController, ComposerPresentationController)> _pump(
  WidgetTester tester, {
  required ThemeData theme,
  required TextDirection direction,
  required bool messages,
}) async {
  tester.view.physicalSize = const Size(1500, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const user = DiscourseUser(
    id: 7,
    username: 'sam',
    canCreateTopic: true,
    canSendPrivateMessages: true,
  );
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('composer-review.invalid').copyWith(user: user),
    ]),
    api: FakeDiscourseApi(
      user: user,
      feeds: const {
        '/latest.json': [_topic],
        '/topics/private-messages/sam.json': [_topic],
      },
      creatableFeedPaths: const {'/latest.json'},
      topics: const {
        1: (
          detail: TopicDetail(
            id: 1,
            title: 'A topic to read',
            stream: [1],
            postsCount: 1,
          ),
          posts: [
            Post(
              id: 1,
              postNumber: 1,
              username: 'sam',
              cooked: '<p>A post to read.</p>',
            ),
          ],
        ),
      },
    ),
    authenticator: FakeAuthenticator()
      ..keys['https://composer-review.invalid'] = 'local',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  final presentation = ComposerPresentationController();
  addTearDown(shell.dispose);
  addTearDown(presentation.dispose);
  await shell.load();
  await shell.openNewTopicFromSidebar();
  if (messages) {
    shell.selectDestination(
      const SidebarDestination(
        id: 'messages',
        label: 'Messages',
        icon: DIcons.inbox,
      ),
    );
  }
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: MaterialApp(
        theme: theme.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: DDirection(
            textDirection: direction,
            child: RepaintBoundary(
              key: _captureKey,
              child: ComposerPresentationHost(
                controller: presentation,
                child: const ComposerDock(
                  child: MainContent(layout: ShellLayout.expanded),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (shell, presentation);
}
