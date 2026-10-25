import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' as fixture;
import 'support/chat_shell.dart';

/// Work counts, not frame-time estimates: layout logging changes execution cost.
final transitionReports = <Map<String, Object?>>[];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final chat in [false, true]) {
      testWidgets(
        'profiles ${chat ? 'chat' : 'topics'} chrome transitions (flat)',
        (tester) async {
          final shell = await fixture.pumpMobileShellFixture(
            tester,
            topics: [
              for (var id = 1; id <= 100; id++)
                Topic(
                  id: id,
                  title: 'Topic $id with a wrapping title',
                  slug: 'topic-$id',
                ),
            ],
            conversations: const ChatChannels(
              public: [
                ChatChannel(
                  id: 10,
                  title: 'Transition profiling',
                  kind: ChatChannelKind.category,
                  membership: ChatMembership(following: true),
                ),
              ],
              direct: [],
            ),
            chatMessages: [
              for (var id = 1; id <= 120; id++)
                ChatMessage(
                  id: id,
                  channelId: 10,
                  cooked:
                      '<p>Message $id with <strong>formatted text</strong> '
                      'and a longer paragraph that wraps across the phone.</p>'
                      '<ul><li>First point</li><li>Second point</li></ul>',
                  author: ChatMessageAuthor(id: id % 2 + 1, username: 'reader'),
                  createdAt: DateTime(2026, 10, 1).add(Duration(minutes: id)),
                ),
            ],
          );
          await shell.forumSettings.setShared(
            shell.forumSettings.shared.copyWith(),
          );
          if (chat) {
            await shell.openChat();
            shell.openChatChannel(10);
          }
          await tester.pumpAndSettle();
          final composer = chat
              ? tester
                    .widget<ComposerEditor>(find.byType(ComposerEditor))
                    .composer
              : null;
          composer?.focus.unfocus();
          await tester.pumpAndSettle();
          final body = find.byType(chat ? ChatMessageStream : TopicListView);
          final scrollable = find.descendant(
            of: body,
            matching: find.byWidgetPredicate(
              (widget) => widget is Scrollable && widget.axis == Axis.vertical,
            ),
          );
          expect(scrollable, findsOneWidget);
          final position = tester.state<ScrollableState>(scrollable).position;
          expect(position.maxScrollExtent, greaterThan(3000));
          position.jumpTo(1600);
          await tester.pumpAndSettle();
          final chrome = DScrollChrome.maybeOf(tester.element(body))!;
          final dock = find.byType(DMobileDock);

          final surface = find.byKey(const ValueKey('mobile-dock-surface'));
          final scopes = <String, Finder>{
            'body': body,
            'header': find.byKey(const ValueKey('mobile-header')),
            'dock': dock,
            if (chat) 'composer': find.byType(DComposerDock),
            if (chat) 'html': find.byType(CookedHtml),
          };

          Future<void> record(
            String phase,
            VoidCallback trigger, {
            double scrollPerFrame = 0,
            void Function(int frame)? onFrame,
          }) async {
            await tester.pump(const Duration(milliseconds: 450));
            final probe = _WorkProbe(scopes)..start();
            final widths = <double>{};
            final rooms = <double>{};
            final composerRects = <Rect>{};
            final viewportHeights = <double>{};
            final before = position.pixels;
            try {
              trigger();
              for (var frame = 0; frame < 40; frame++) {
                onFrame?.call(frame);
                if (scrollPerFrame != 0) position.pointerScroll(scrollPerFrame);
                await tester.pump(const Duration(milliseconds: 16));
                widths.add(tester.getSize(surface).width);
                viewportHeights.add(position.viewportDimension);
                // Read the existing notifier without subscribing a new element.
                final room = tester
                    .widget<InheritedNotifier<ValueNotifier<double>>>(
                      find.byWidgetPredicate(
                        (w) => w.runtimeType.toString() == '_DockRoom',
                      ),
                    );
                rooms.add(room.notifier!.value);
                if (chat) {
                  composerRects.add(
                    tester.getRect(find.byKey(const ValueKey('chat-composer'))),
                  );
                }
              }
            } finally {
              probe.stop();
            }
            final report = <String, Object?>{
              'surface': chat ? 'chat' : 'topics',
              'platform': platform.name,
              'mode': 'work-counts',
              'devicePixelRatio': tester.view.devicePixelRatio,
              'phase': phase,
              'frames': 40,
              'scrollDelta': position.pixels - before,
              'dockWidths': widths.length,
              'clearanceValues': rooms.length,
              'clearanceRange': [
                rooms.reduce((a, b) => a < b ? a : b),
                rooms.reduce((a, b) => a > b ? a : b),
              ],
              'composerRects': composerRects.length,
              'viewportHeights': viewportHeights.length,
              'collapsed': tester.widget<DMobileDock>(dock).collapsed,
              if (composer != null) 'composerFocused': composer.focus.hasFocus,
              ...probe.report(),
            };
            transitionReports.add(report);
            debugPrint(
              'MOBILE_TRANSITION_PROFILE ${jsonEncode(report)}',
              wrapWidth: 4096,
            );
            expect(tester.takeException(), isNull);
          }

          // Trigger the same physical downward/upward intent on reversed chat.
          final down = chat ? -1.0 : 1.0;
          await record('idle', () {});
          await record('hide', () => position.pointerScroll(180 * down));
          expect(tester.widget<DMobileDock>(dock).collapsed, isTrue);
          await record('settled-scroll', () {}, scrollPerFrame: 3 * down);
          await record('show', chrome.reveal);
          expect(tester.widget<DMobileDock>(dock).collapsed, isFalse);
          await record(
            'hide-while-scrolling',
            () => position.pointerScroll(180 * down),
            scrollPerFrame: 3 * down,
          );
          await record(
            'show-while-scrolling',
            () => position.pointerScroll(-180 * down),
            scrollPerFrame: -3 * down,
          );
          expect(tester.widget<DMobileDock>(dock).collapsed, isFalse);
          if (composer != null) {
            await record('focus-reposition', composer.focus.requestFocus);
            await record(
              'keyboard-show-while-scrolling',
              () {},
              scrollPerFrame: 3 * down,
              onFrame: (frame) => tester.view.viewInsets = FakeViewPadding(
                bottom:
                    320 *
                    tester.view.devicePixelRatio *
                    (frame / 20).clamp(0.0, 1.0),
              ),
            );
            await record('grow-while-scrolling', () {
              composer.text.text = List.filled(
                5,
                'A line in the chat draft.',
              ).join('\n');
            }, scrollPerFrame: 3 * down);
            await record(
              'shrink-while-scrolling',
              () => composer.text.clear(),
              scrollPerFrame: -3 * down,
            );
            await record(
              'keyboard-hide-while-scrolling',
              () {},
              scrollPerFrame: -3 * down,
              onFrame: (frame) => tester.view.viewInsets = FakeViewPadding(
                bottom:
                    320 *
                    tester.view.devicePixelRatio *
                    (1 - frame / 20).clamp(0.0, 1.0),
              ),
            );
            await record('unfocus-reposition', composer.focus.unfocus);
          }
          await tester.pumpAndSettle();
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }
}

class _WorkProbe {
  _WorkProbe(Map<String, Finder> scopes) {
    for (final scope in scopes.entries) {
      final elements = <Element>{...scope.value.evaluate()};
      elements.addAll(
        find
            .descendant(
              of: scope.value,
              matching: find.byWidgetPredicate((_) => true),
            )
            .evaluate(),
      );
      _elements[scope.key] = elements;
      _objects[scope.key] = {
        for (final element in elements.whereType<RenderObjectElement>())
          element.renderObject,
      };
      _ids[scope.key] = _objects[scope.key]!
          .map((o) => o.toStringShort())
          .toSet();
    }
  }

  final _elements = <String, Set<Element>>{};
  final _objects = <String, Set<RenderObject>>{};
  final _ids = <String, Set<String>>{};
  final _builds = <String, int>{};
  final _paints = <String, int>{};
  final _layouts = <String, int>{};
  final _types = <String, int>{};
  DebugPrintCallback? _print;
  RebuildDirtyWidgetCallback? _build;
  ProfilePaintCallback? _paint;
  bool _printLayouts = false;

  void start() {
    _print = debugPrint;
    _build = debugOnRebuildDirtyWidget;
    _paint = debugOnProfilePaint;
    _printLayouts = debugPrintLayouts;
    debugPrintLayouts = true;
    debugPrint = (message, {wrapWidth}) {
      final match = RegExp(
        r'^Laying out \([^)]*\) (\S+)',
      ).firstMatch(message ?? '');
      if (match != null) {
        for (final scope in _ids.entries) {
          if (scope.value.contains(match[1])) _increment(_layouts, scope.key);
        }
      } else {
        _print!(message, wrapWidth: wrapWidth);
      }
    };
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      _build?.call(element, builtOnce);
      _increment(_types, element.widget.runtimeType.toString());
      for (final scope in _elements.entries) {
        if (scope.value.contains(element)) _increment(_builds, scope.key);
      }
    };
    debugOnProfilePaint = (object) {
      _paint?.call(object);
      if (object.isRepaintBoundary) return;
      for (final scope in _objects.entries) {
        if (scope.value.contains(object)) _increment(_paints, scope.key);
      }
    };
  }

  void stop() {
    debugPrintLayouts = _printLayouts;
    debugPrint = _print!;
    debugOnRebuildDirtyWidget = _build;
    debugOnProfilePaint = _paint;
  }

  Map<String, Object?> report() {
    final types = _types.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {
      'retainedBuilds': _builds,
      'retainedPaints': _paints,
      'retainedLayouts': _layouts,
      'topBuilds': Map.fromEntries(types.take(8)),
      'targetBuilds': {
        for (final name in [
          'DComposerDock',
          'ComposerEditor',
          'CookedHtml',
          'DMessageScrollerViewport',
          'DMobileDock',
          'TopicListView',
          'LayoutBuilder',
        ])
          name: _types[name] ?? 0,
      },
      'retainedElements': {
        for (final scope in _elements.entries)
          scope.key: scope.value.where((e) => e.mounted).length,
      },
    };
  }
}

void _increment(Map<String, int> counts, String key) =>
    counts.update(key, (v) => v + 1, ifAbsent: () => 1);
