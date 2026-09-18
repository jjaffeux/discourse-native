import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/mixed_topic_scroll_fixture.dart';
import 'support/topic_post_list.dart';
import 'support/topic_scroll_fixture.dart';

void main() {
  for (final inbox in [false, true]) {
    testWidgets(
      'topic animation visibility follows prepend headers (inbox: $inbox)',
      (tester) async {
        final gate = Completer<void>();
        final controller = await mixedTopicScrollController(
          api: FakeDiscourseApi(postGate: gate, topics: {}, postsById: {}),
          firstLoaded: 21,
          initialPostNumber: 31,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          TopicScrollFixture(controller: controller, inbox: inbox),
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final list = topicPostList(tester);
        void checkVisibility() {
          final range = list.listController!.visibleRange!;
          var visibleCount = 0;
          var hiddenCount = 0;
          for (final body in tester.elementList(
            find.byType(CookedHtml, skipOffstage: false),
          )) {
            RenderObject? row = body.renderObject;
            while (row != null &&
                row.parentData is! SliverMultiBoxAdaptorParentData) {
              row = row.parent;
            }
            if (row == null) continue;
            final data = row.parentData! as SliverMultiBoxAdaptorParentData;
            final visible =
                !data.keptAlive &&
                data.index! >= range.$1 &&
                data.index! <= range.$2;
            expect(
              TickerMode.valuesOf(body).enabled,
              visible,
              reason: 'raw sliver index ${data.index}, range $range',
            );
            if (visible) {
              visibleCount++;
            } else {
              hiddenCount++;
            }
          }
          expect(visibleCount, greaterThan(0));
          expect(hiddenCount, greaterThan(0));
        }

        checkVisibility();
        final loading = controller.loadEarlierPosts();
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        checkVisibility();
        gate.complete();
        await loading;
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(controller.currentPostIds.first, 1);
        checkVisibility();
        list.listController!.jumpToItem(
          index: 0,
          scrollController: list.controller!,
          alignment: 0,
        );
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        checkVisibility();
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('retained topic GIF stops listening offscreen (inbox: $inbox)', (
      tester,
    ) async {
      final site = instance('meta.example');
      final bytes = base64Decode(
        'R0lGODlhAQABAIAAAAAAAP///yH/C05FVFNDQVBFMi4wAwEAAAAh+QQACgAAACw'
        'AAAAAAQABAAACAkQBACH5BAAKAAAALAAAAAABAAEAAAICTAEAOw==',
      );
      final lifecycle = SiteLifecycle();
      final authenticator = FakeAuthenticator()..keys[site.url] = 'key';
      final siteImages = SiteImageRepository(
        credentials: authenticator,
        lifecycle: lifecycle,
        client: MockClient(
          (_) async => http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'image/gif'},
          ),
        ),
      );
      final controller = ShellController(
        instanceStore: FakeInstanceStore([site]),
        api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        lifecycle: lifecycle,
        siteImages: siteImages,
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      await siteImages.load(
        siteUrl: site.url,
        url: '${site.url}/uploads/test.gif',
      );
      controller.store
        ..put(
          site.url,
          TopicDetail(
            id: 1,
            title: 'One',
            stream: [for (var id = 1; id <= 35; id++) id],
            postsCount: 35,
          ),
        )
        ..putAll(site.url, [
          const Post(
            id: 1,
            postNumber: 1,
            username: 'sam',
            cooked:
                '<p>Animated post</p><img src="/uploads/test.gif" width="100" height="100">',
          ),
          for (var id = 2; id <= 35; id++)
            Post(
              id: id,
              postNumber: id,
              username: 'sam',
              cooked: List.filled(5, '<p>Post $id</p>').join(),
            ),
        ]);
      controller.pushContent(
        ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
      );
      Widget view({bool enabled = true}) => ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: TickerMode(
              enabled: enabled,
              child: TopicView(inbox: inbox),
            ),
          ),
        ),
      );
      await tester.pumpWidget(view());
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      final imageFinder = find.descendant(
        of: find.byType(SiteImage),
        matching: find.byType(Image),
      );
      final imageElement = tester.element(imageFinder);
      final imageWidget = imageElement.widget as Image;
      // Resolve the existing stream without adding a listener of our own.
      final stream = imageWidget.image
          .resolve(createLocalImageConfiguration(imageElement))
          .completer!;
      expect(stream, isA<MultiFrameImageStreamCompleter>());
      expect(stream.hasListeners, isTrue);
      final rawFinder = find.descendant(
        of: imageFinder,
        matching: find.byType(RawImage),
      );
      final rawElement = tester.element(rawFinder);
      final initial = (rawElement.widget as RawImage).image!.clone();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump();
      expect(
        initial.isCloneOf((rawElement.widget as RawImage).image!),
        isFalse,
      );
      initial.dispose();
      final list = topicPostList(tester);
      list.listController!.jumpToItem(
        index: 16,
        scrollController: list.controller!,
        alignment: 0,
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(imageElement.mounted, isTrue);
      RenderObject? row = imageElement.renderObject;
      while (row != null &&
          row.parentData is! SliverMultiBoxAdaptorParentData) {
        row = row.parent;
      }
      expect(
        (row!.parentData! as SliverMultiBoxAdaptorParentData).keptAlive,
        isTrue,
      );
      expect(
        stream.hasListeners,
        isFalse,
        reason:
            'a kept-alive offscreen GIF must release its animation listener',
      );
      controller.store.put(
        site.url,
        controller.store.read<Post>(site.url, 1)!.withLike(true),
      );
      await tester.pump();
      expect(imageElement.mounted, isTrue);
      expect(stream.hasListeners, isFalse);
      final paused = (rawElement.widget as RawImage).image!.clone();
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 110));
      }
      expect(paused.isCloneOf((rawElement.widget as RawImage).image!), isTrue);
      paused.dispose();
      list.listController!.jumpToItem(
        index: 0,
        scrollController: list.controller!,
        alignment: 0,
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(tester.element(imageFinder), same(imageElement));
      expect(stream.hasListeners, isTrue);
      // A partially visible post remains active, even when its GIF itself
      // has scrolled out; visibility is deliberately owned by the post.
      final viewportTop = tester.getTopLeft(topicPostListFinder()).dy;
      final postBottom = tester.getBottomLeft(find.byKey(const ValueKey(1))).dy;
      list.controller!.jumpTo(
        list.controller!.offset + postBottom - viewportTop - 5,
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(stream.hasListeners, isTrue);
      list.listController!.jumpToItem(
        index: 0,
        scrollController: list.controller!,
        alignment: 0,
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpWidget(view(enabled: false));
      await tester.pump();
      expect(stream.hasListeners, isFalse);
      await tester.pumpWidget(view());
      await tester.pump();
      expect(stream.hasListeners, isTrue);
      // Pausing is user state: reentry and tab suspension must not undo it.
      await tester.tap(find.byKey(const ValueKey('gif-playback-toggle')));
      await tester.pump();
      final userPaused = (rawElement.widget as RawImage).image!.clone();
      list.listController!.jumpToItem(
        index: 16,
        scrollController: list.controller!,
        alignment: 0,
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 110));
      }
      expect(stream.hasListeners, isFalse);
      list.listController!.jumpToItem(
        index: 0,
        scrollController: list.controller!,
        alignment: 0,
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 110));
      }
      expect(find.byTooltip('Play GIF'), findsOneWidget);
      expect(
        userPaused.isCloneOf((rawElement.widget as RawImage).image!),
        isTrue,
      );
      userPaused.dispose();
      await controller.appSettings.setDisableGifAnimations(true);
      await tester.pump();
      expect(find.byTooltip('Play GIF'), findsOneWidget);
      await controller.appSettings.setDisableGifAnimations(false);
      await tester.pump();
      expect(find.byTooltip('Pause GIF'), findsOneWidget);
      list.listController!.jumpToItem(
        index: 16,
        scrollController: list.controller!,
        alignment: 0,
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      controller.store.put(
        site.url,
        const Post(
          id: 1,
          postNumber: 1,
          username: 'sam',
          cooked:
              '<p>Live edit while offscreen</p><img src="/uploads/test.gif" width="100" height="100">',
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      final editedImage = tester.element(
        find.descendant(
          of: find.byType(SiteImage, skipOffstage: false),
          matching: find.byType(Image, skipOffstage: false),
        ),
      );
      expect(TickerMode.valuesOf(editedImage).enabled, isFalse);
      final editedStream = (editedImage.widget as Image).image
          .resolve(createLocalImageConfiguration(editedImage))
          .completer!;
      expect(editedStream.hasListeners, isFalse);
      list.listController!.jumpToItem(
        index: 0,
        scrollController: list.controller!,
        alignment: 0,
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        find.text('Live edit while offscreen', findRichText: true),
        findsOneWidget,
      );
      expect(editedStream.hasListeners, isTrue);
      for (var index = 8; index <= 64; index += 8) {
        list.listController!.jumpToItem(
          index: index,
          scrollController: list.controller!,
          alignment: 0,
        );
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
      }
      expect(
        editedImage.mounted,
        isFalse,
        reason: 'retention eviction still releases the post',
      );
      expect(stream.hasListeners, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(stream.hasListeners, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
