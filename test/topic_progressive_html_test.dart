import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/progressive_html_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/topic_post_list.dart';
import 'support/topic_scroll_capture.dart';
import 'support/topic_scroll_fixture.dart';

void main() {
  for (final (inbox, oversized) in [
    (true, false),
    (false, false),
    (true, true),
  ]) {
    testWidgets(
      'jump survives an unfinished long post above it (inbox=$inbox, oversized=$oversized)',
      (tester) async {
        final controller = await topicScrollController();
        final diagnostics = DiagnosticsController.start(
          persistence: MemoryDiagnosticsPersistence(),
          topicScrollCapture: topicScrollCaptureWithoutVm(),
        );
        addTearDown(controller.dispose);
        addTearDown(diagnostics.close);
        final site = controller.currentInstance!.url;
        controller.store.update<Post>(
          site,
          20,
          (post) => Post(
            id: post.id,
            postNumber: post.postNumber,
            username: post.username,
            createdAt: post.createdAt,
            cooked:
                List.generate(
                  450,
                  (i) =>
                      '<p>Variable $i: '
                      '${List.filled((i < 40) == oversized ? 15 : 1, 'long paragraph content ').join()}</p>',
                ).join() +
                (oversized ? '<!--${List.filled(300000, 'x').join()}-->' : ''),
          ),
        );
        await tester.pumpWidget(
          TopicScrollFixture(
            controller: controller,
            diagnostics: diagnostics,
            inbox: inbox,
          ),
        );
        await _until(
          tester,
          () => _paragraphs('Post 1:').evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        final list = topicPostList(tester);
        list.listController!.jumpToItem(
          index: 38,
          scrollController: list.controller!,
          alignment: 0,
        );
        await _until(
          tester,
          () => _paragraphs('Variable').evaluate().isNotEmpty,
        );
        expect(_paragraphs('Variable').evaluate().length, lessThan(450));
        final body = tester.widget<CookedHtml>(
          find.byWidgetPredicate(
            (widget) => widget is CookedHtml && widget.post?.id == 20,
          ),
        );
        expect(body.renderMode, isA<ProgressiveHtmlMode>());
        list.listController!.jumpToItem(
          index: 80,
          scrollController: list.controller!,
          alignment: 0,
        );
        await tester.pump();
        final target = find.byKey(const ValueKey(41));
        expect(target, findsOneWidget);
        final before = tester.getTopLeft(target).dy;
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(target).dy, closeTo(before, 1));
        expect(tester.takeException(), isNull);
        // The completed retained body is still reused when returning to it.
        list.listController!.jumpToItem(
          index: 38,
          scrollController: list.controller!,
          alignment: 0,
        );
        await _until(
          tester,
          () => _paragraphs('Variable').evaluate().isNotEmpty,
        );
        await tester.pumpAndSettle();
        expect(_paragraphs('Variable'), findsNWidgets(450));
        final cooked = find.byWidgetPredicate(
          (widget) => widget is CookedHtml && widget.post?.id == 20,
        );
        // An unfinished estimate must not become a permanent minimum height
        // when an oversized body is recycled before its last batch is mounted.
        expect(
          tester.getSize(find.byKey(const ValueKey(20))).height -
              tester.getSize(cooked).height,
          lessThan(250),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await diagnostics.close();
      },
    );
  }
}

Finder _paragraphs(String prefix) => find.byWidgetPredicate(
  (widget) =>
      widget is RichText && widget.text.toPlainText().startsWith(prefix),
);

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue);
}
