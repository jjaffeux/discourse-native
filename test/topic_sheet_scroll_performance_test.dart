import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/stream_day_separator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/topic_post_list.dart';
import 'support/topic_sheet_scroll_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  {
    testWidgets(
      'topic sheet scroll profile flat',
      (tester) async {
        final shell = await pumpTopicSheetScrollFixture(tester);
        await shell.forumSettings.setShared(
          shell.forumSettings.shared.copyWith(),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DSheetViewport), findsOneWidget);

        final scrollable = find.descendant(
          of: topicPostListFinder(),
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(position.maxScrollExtent, greaterThan(4000));
        // Warm the same replies in both directions before measuring.
        for (final offset in [1200.0, 1800.0, 1200.0]) {
          position.jumpTo(offset);
          await tester.pumpAndSettle();
        }
        final paints = <String, int>{};
        final builds = <String, int>{};
        final owners = <String, int>{};
        final buildOwners = <String, int>{};
        String owner(Element element) {
          var result = 'shell';
          element.visitAncestorElements((ancestor) {
            final name = ancestor.widget.runtimeType.toString();
            if ([
              'TopicView',
              'StreamDaySeparator',
              'TopicProgressPopover',
              'DMobileDock',
              'TopicInboxHeader',
              'DSheetContent',
              'PostActions',
              'CookedHtml',
            ].contains(name)) {
              result = name;
              return false;
            }
            return true;
          });
          return result;
        }

        var handlePaints = 0;
        final handleFinder = find.byKey(
          const ValueKey('sheet-drag-handle'),
          skipOffstage: false,
        );
        final handle = tester.renderObject(handleFinder);
        final grabber = find
            .ancestor(
              of: handleFinder,
              matching: find.byType(Visibility, skipOffstage: false),
            )
            .first;
        bool grabberShown() => tester.widget<Visibility>(grabber).visible;
        // Frames in which the frame had a reason to repaint: the condensed
        // head covered or uncovered the grabber, or the shell changed.
        var frame = 0;
        final changes = <int>{};
        void shellChanged() => changes.add(frame);
        final handleFrames = <int>[];
        final previousPaint = debugOnProfilePaint;
        final previousBuild = debugOnRebuildDirtyWidget;
        final dateArtwork = find
            .descendant(
              of: find.byWidgetPredicate(
                (widget) => widget is StreamDaySeparator && widget.floating,
              ),
              matching: find.byType(RichText),
            )
            .evaluate()
            .map((element) => element.findRenderObject())
            .toSet();
        final progressArtwork = find
            .descendant(
              of: find.byKey(const ValueKey('topic-progress-button')),
              matching: find.byType(RichText),
            )
            .evaluate()
            .map((element) => element.findRenderObject())
            .toSet();
        expect(dateArtwork, isNotEmpty);
        expect(progressArtwork, isNotEmpty);
        var datePaints = 0;
        var progressPaints = 0;
        debugOnProfilePaint = (object) {
          previousPaint?.call(object);
          if (!object.isRepaintBoundary) {
            paints.update(
              object.runtimeType.toString(),
              (v) => v + 1,
              ifAbsent: () => 1,
            );
            if (object.debugCreator case final DebugCreator creator) {
              owners.update(
                owner(creator.element),
                (v) => v + 1,
                ifAbsent: () => 1,
              );
            }
          }
          if (identical(object, handle)) {
            handlePaints++;
            handleFrames.add(frame);
          }
          if (dateArtwork.contains(object)) datePaints++;
          if (progressArtwork.contains(object)) progressPaints++;
        };
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          previousBuild?.call(element, builtOnce);
          builds.update(
            element.widget.runtimeType.toString(),
            (v) => v + 1,
            ifAbsent: () => 1,
          );
          buildOwners.update(owner(element), (v) => v + 1, ifAbsent: () => 1);
        };
        shell.addListener(shellChanged);
        try {
          var shown = grabberShown();
          for (frame = 0; frame < 80; frame++) {
            position.pointerScroll(frame < 40 ? 6 : -6);
            await tester.pump(const Duration(milliseconds: 16));
            if (grabberShown() != shown) {
              shown = !shown;
              // The head reports during one frame and applies after it.
              changes.addAll([frame, frame + 1]);
            }
          }
        } finally {
          shell.removeListener(shellChanged);
          debugOnProfilePaint = previousPaint;
          debugOnRebuildDirtyWidget = previousBuild;
        }
        List<MapEntry<String, int>> ranked(Map<String, int> values) =>
            values.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        debugPrint(
          'TOPIC_SHEET_PAINT_PROFILE ${jsonEncode({'platform': defaultTargetPlatform.name, 'totalPaints': paints.values.fold(0, (a, b) => a + b), 'handlePaints': handlePaints, 'owners': owners, 'buildOwners': buildOwners, 'paints': Map.fromEntries(ranked(paints).take(16)), 'builds': Map.fromEntries(ranked(builds).take(12))})}',
          wrapWidth: 2048,
        );
        expect(position.pixels, closeTo(1200, 1));
        expect(
          handleFrames.where((frame) => !changes.contains(frame)),
          isEmpty,
          reason: 'Header motion must not repaint the sheet frame each tick',
        );
        expect(
          datePaints,
          0,
          reason: 'The pinned date must retain its artwork',
        );
        expect(
          progressPaints,
          0,
          reason: 'Scrolling within one post must retain its progress label',
        );
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }
}
