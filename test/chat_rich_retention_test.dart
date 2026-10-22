import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';

import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_stream.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_scroll_fixture.dart';

String giantChatHtml(int id, {bool dense = false}) => dense
    ? '<p>Message $id</p>${List.generate(6, (p) => '<p>Rich body $p ${List.filled(80, "<strong><em>x</em></strong> ").join()}</p>').join()}'
    : '<p>Message $id</p>${List.generate(8, (p) => '<p>${List.generate(40, (s) => '<strong>Rich <em>body $p $s</em></strong> ').join()}</p>').join()}';

void main() {
  for (final workload in ['tall', 'dense', 'ordinary']) {
    final giant = workload != 'ordinary';
    final dense = workload == 'dense';
    testWidgets('retention workload $workload', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = await chatScrollController(
        count: 72,
        configureApi: (api) {
          final page = api.chatMessagesByKey['9']!;
          api.chatMessagesByKey['9'] = (
            messages: [
              for (final message in page.messages)
                if (giant && message.id % 3 == 0)
                  ChatMessage(
                    id: message.id,
                    channelId: 9,
                    cooked: giantChatHtml(message.id, dense: dense),
                    author: message.author,
                    createdAt: message.createdAt,
                  )
                else
                  message,
            ],
            canLoadMorePast: false,
            canLoadMoreFuture: false,
            targetMessageId: null,
          );
        },
      );
      addTearDown(controller.dispose);

      try {
        await tester.pumpWidget(ChatScrollFixture(controller: controller));
        await _settleBodies(tester);
        final scroller = tester.widget<DMessageScrollerViewport>(
          find.byType(DMessageScrollerViewport),
        );
        final position = scroller.scrollController!.position;
        position.jumpTo(0);
        await _settleBodies(tester);
        final visited = <int>{};
        final renderedLarge = <int>{};
        final mounts = <int, Set<Element>>{};
        final samples = <Map<String, int>>[];
        void sample() {
          var offscreenBodies = 0;
          var offscreenCharacters = 0;
          var offscreenLarge = 0;
          var retainedElements = 0;
          var retainedSpans = 0;
          for (final element
              in find.byType(ChatMessageTile, skipOffstage: false).evaluate()) {
            final tile = element.widget as ChatMessageTile;
            mounts.putIfAbsent(tile.messageId, () => {}).add(element);
            visited.add(tile.messageId);
          }
          for (final body
              in find.byType(CookedHtml, skipOffstage: false).evaluate()) {
            Element? tile;
            body.visitAncestorElements((ancestor) {
              if (ancestor.widget is ChatMessageTile) {
                tile = ancestor;
                return false;
              }
              return true;
            });
            if (tile == null) continue;
            final html = (body.widget as CookedHtml).html;
            final id = (tile!.widget as ChatMessageTile).messageId;
            if (CookedHtml.buildsAsynchronously(html) &&
                !renderedLarge.contains(id)) {
              final text = find.descendant(
                of: find.byElementPredicate(
                  (e) => identical(e, body),
                  skipOffstage: false,
                ),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is RichText &&
                      w.text.toPlainText().contains('Rich body'),
                  skipOffstage: false,
                ),
              );
              if (text.evaluate().isNotEmpty) renderedLarge.add(id);
            }
            RenderObject? render = tile!.findRenderObject();
            while (render != null &&
                render.parentData is! SliverMultiBoxAdaptorParentData) {
              render = render.parent;
            }
            final parentData = render?.parentData;
            final retained =
                parentData is SliverMultiBoxAdaptorParentData &&
                parentData.keptAlive;
            if (retained && html.isNotEmpty) {
              offscreenBodies++;
              offscreenCharacters += html.length;
              if (CookedHtml.buildsAsynchronously(html)) offscreenLarge++;
              void count(Element element) {
                retainedElements++;
                if (element.widget case RichText(:final text)) {
                  retainedSpans++;
                  text.visitChildren((span) {
                    retainedSpans++;
                    return true;
                  });
                }
                element.visitChildren(count);
              }

              count(body);
            }
          }
          samples.add({
            'bodies': offscreenBodies,
            'characters': offscreenCharacters,
            'large': offscreenLarge,
            'elements': retainedElements,
            'spans': retainedSpans,
          });
        }

        sample();
        for (var step = 0; step < (giant ? 420 : 100); step++) {
          position.pointerScroll(120);
          await _settleBodies(tester);
          sample();
          if (visited.length == 72) break;
        }
        await _settleBodies(tester);
        sample();
        final beforeReverse = {
          for (final e
              in find.byType(ChatMessageTile, skipOffstage: false).evaluate())
            e,
        };
        final offset = position.pixels;
        for (var step = 0; step < 4; step++) {
          position.pointerScroll(-100);
          await _settleBodies(tester);
        }
        sample();
        expect(position.pixels, closeTo(offset - 400, .5));
        final reverseRemounts = find
            .byType(ChatMessageTile, skipOffstage: false)
            .evaluate()
            .where((e) => !beforeReverse.contains(e))
            .length;
        position.jumpTo(0);
        await _settleBodies(tester);
        sample();
        position.jumpTo(offset);
        await _settleBodies(tester);
        sample();
        for (var id = 1; id <= 72; id++) {
          bool complete() =>
              visited.contains(id) &&
              (!giant || id % 3 != 0 || renderedLarge.contains(id));
          for (var attempt = 0; attempt < 3 && !complete(); attempt++) {
            final stream = tester.widget<ChatMessageStream>(
              find.byType(ChatMessageStream),
            );
            final index = stream.items.indexWhere(
              (item) => item is ChatStreamMessage && item.id == id,
            );
            expect(index, greaterThanOrEqualTo(0));
            scroller.listController!.jumpToItem(
              index: stream.items.length - 1 - index,
              scrollController: scroller.scrollController!,
              alignment: .5,
            );
            await _settleBodies(tester);
            sample();
          }
        }
        Future<double> jumpToMessage(int id) async {
          for (var attempt = 0; attempt < 3; attempt++) {
            final stream = tester.widget<ChatMessageStream>(
              find.byType(ChatMessageStream),
            );
            final index = stream.items.indexWhere(
              (item) => item is ChatStreamMessage && item.id == id,
            );
            expect(index, greaterThanOrEqualTo(0));
            scroller.listController!.jumpToItem(
              index: stream.items.length - 1 - index,
              scrollController: scroller.scrollController!,
              alignment: .5,
            );
            await _settleBodies(tester);
          }
          return tester
              .getTopLeft(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is ChatMessageTile && widget.messageId == id,
                  skipOffstage: false,
                ),
              )
              .dy;
        }

        final anchor = await jumpToMessage(39);
        await jumpToMessage(63);
        expect(await jumpToMessage(39), closeTo(anchor, .5));
        int peak(String field) => samples
            .map((sample) => sample[field]!)
            .reduce((a, b) => a > b ? a : b);
        final metrics = {
          'workload': workload,
          'giant': giant,
          'visited': visited.length,
          'missingIds': [
            for (var id = 1; id <= 72; id++)
              if (!visited.contains(id)) id,
          ],
          'unrenderedLargeIds': [
            for (var id = 3; giant && id <= 72; id += 3)
              if (!renderedLarge.contains(id)) id,
          ],
          'renderedLarge': renderedLarge.length,
          'uniqueMounts': mounts.values.fold<int>(
            0,
            (n, elements) => n + elements.length,
          ),
          'reverseRemounts': reverseRemounts,
          'maxOffscreenBodies': peak('bodies'),
          'maxOffscreenCharacters': peak('characters'),
          'maxOffscreenLarge': peak('large'),
          'maxRetainedElements': peak('elements'),
          'maxRetainedSpans': peak('spans'),
          'giantCharacters': giantChatHtml(72, dense: dense).length,
        };
        debugPrint('RICH_RETENTION ${jsonEncode(metrics)}');
        for (final sample in samples) {
          expect(sample['large'], lessThanOrEqualTo(3));
          expect(sample['characters'], lessThanOrEqualTo(256 * 1024));
          expect(sample['bodies'], lessThanOrEqualTo(24));
        }
        if (!giant) expect(reverseRemounts, 0);
        expect(visited.length, 72);
        expect(renderedLarge.length, giant ? 24 : 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }
}

Future<void> _settleBodies(WidgetTester tester) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final loading = find
        .byType(CircularProgressIndicator, skipOffstage: false)
        .evaluate();
    if (loading.isEmpty && !tester.binding.hasScheduledFrame) return;
  }
  throw StateError('Chat bodies did not finish rendering');
}
