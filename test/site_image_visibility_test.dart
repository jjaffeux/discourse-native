import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/fakes.dart';

const _site = 'https://forum.example';
const _url = '$_site/image.png';

void main() {
  testWidgets('shared image ancestry is checked once per natural frame', (
    tester,
  ) async {
    final client = _Bodies();
    final repository = _repository(client);
    final probe = _TraversalCounts();
    await tester.pumpWidget(
      MaterialApp(
        home: _TraversalProbe(
          counts: probe,
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (var index = 0; index < 24; index++)
                  SizedBox(
                    height: 10,
                    child: SiteImage(
                      viewportAware: true,
                      url: '$_site/traversal-$index.png',
                      siteUrl: _site,
                      repository: repository,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await _drain(tester);
    expect(client.urls, hasLength(8));
    for (var frame = 0; frame < 5; frame++) {
      probe.paints = 0;
      probe.transforms = 0;
      tester.binding.scheduleFrame();
      await tester.pump();
      debugPrint(
        'image traversal frame=$frame images=24 paints=${probe.paints} transforms=${probe.transforms}',
      );
      expect(probe.paints, 1);
      expect(probe.transforms, 25);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await _drain(tester);
    expect(client.cancelled, 8);
  });

  testWidgets('a failed image check does not drop other pending checks', (
    tester,
  ) async {
    final client = _Bodies();
    final repository = _repository(client);
    final probe = _TraversalCounts();
    await tester.pumpWidget(
      MaterialApp(
        home: _TraversalProbe(
          counts: probe,
          child: Column(
            children: [
              for (var index = 0; index < 2; index++)
                SizedBox(
                  height: 20,
                  child: SiteImage(
                    viewportAware: true,
                    url: '$_site/isolated-$index.png',
                    siteUrl: _site,
                    repository: repository,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await _drain(tester);
    expect(client.urls, hasLength(2));
    probe.paints = 0;
    probe.throwNext = true;
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(tester.takeException(), isA<StateError>());
    expect(probe.paints, 2);
    probe.paints = 0;
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(probe.paints, 1);
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('shared ancestors retain child-specific paint decisions', (
    tester,
  ) async {
    final client = _Bodies();
    final repository = _repository(client);
    Widget frame(int selected) => MaterialApp(
      home: _SelectiveStack(
        selected: selected,
        children: [
          for (var index = 0; index < 2; index++)
            SiteImage(
              key: ValueKey(index),
              viewportAware: true,
              url: '$_site/selected-$index.png',
              siteUrl: _site,
              repository: repository,
            ),
        ],
      ),
    );
    await tester.pumpWidget(frame(1));
    await _drain(tester);
    expect(client.urls.map((url) => url.path), ['/selected-1.png']);
    await tester.pumpWidget(frame(0));
    await _drain(tester);
    expect(client.cancelled, 1);
    expect(client.urls.map((url) => url.path), [
      '/selected-1.png',
      '/selected-0.png',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ancestor transforms refresh shared nested viewport geometry', (
    tester,
  ) async {
    final client = _Bodies();
    final repository = _repository(client);
    final translation = ValueNotifier(Offset.zero);
    addTearDown(translation.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ValueListenableBuilder(
            valueListenable: translation,
            builder: (context, offset, child) =>
                Transform.translate(offset: offset, child: child),
            child: SizedBox(
              width: 200,
              height: 100,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var index = 0; index < 2; index++)
                      SizedBox(
                        height: 20,
                        child: SiteImage(
                          viewportAware: true,
                          url: '$_site/transformed-$index.png',
                          siteUrl: _site,
                          repository: repository,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _drain(tester);
    expect(client.urls, hasLength(2));
    final elements = tester.elementList(find.byType(SiteImage)).toList();
    translation.value = const Offset(2000, 0);
    await _drain(tester);
    expect(client.cancelled, 2);
    expect(tester.elementList(find.byType(SiteImage)), elements);
    translation.value = Offset.zero;
    await _drain(tester);
    expect(client.urls, hasLength(4));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retained scrolling images release and reacquire unfinished work',
    (tester) async {
      final client = _Bodies();
      final repository = _repository(client);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                SizedBox(height: 100, child: _image(repository)),
                const SizedBox(height: 3000),
              ],
            ),
          ),
        ),
      );
      await _drain(tester);
      expect(client.bodies, hasLength(1));
      final original = tester.element(find.byType(SiteImage));
      client.bodies[0].add([1, 2]);
      await tester.pump();

      scroll.jumpTo(2000);
      await _drain(tester);
      expect(client.cancelled, 1);
      expect(tester.element(find.byType(SiteImage)), same(original));
      expect(repository.isCached(siteUrl: _site, url: _url), isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);

      scroll.jumpTo(0);
      await _drain(tester);
      expect(client.bodies, hasLength(2));
      final bytes = await _png(tester);
      client.bodies[1].add(bytes);
      unawaited(client.bodies[1].close());
      await _waitFor(
        tester,
        () => tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null),
      );
      expect(find.byType(RawImage), findsOneWidget);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      scroll.jumpTo(2000);
      await tester.pump();
      scroll.jumpTo(0);
      await tester.pump();
      expect(client.bodies, hasLength(2), reason: 'completed bytes are reused');
      expect(tester.takeException(), isNull);
    },
  );

  for (final hiddenBy in ['offstage', 'ticker']) {
    testWidgets('an image releases pending work when hidden by $hiddenBy', (
      tester,
    ) async {
      final client = _Bodies();
      final repository = _repository(client);
      Widget frame(bool hidden) => MaterialApp(
        home: Offstage(
          offstage: hiddenBy == 'offstage' && hidden,
          child: TickerMode(
            enabled: hiddenBy != 'ticker' || !hidden,
            child: SizedBox(width: 100, height: 100, child: _image(repository)),
          ),
        ),
      );
      await tester.pumpWidget(frame(false));
      await _drain(tester);
      expect(client.bodies, hasLength(1));
      await tester.pumpWidget(frame(true));
      await _drain(tester);
      expect(client.cancelled, 1);
      await tester.pumpWidget(frame(false));
      await _drain(tester);
      expect(client.bodies, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
      await _drain(tester);
      expect(client.cancelled, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('visible zero-size placeholders can obtain natural dimensions', (
    tester,
  ) async {
    final client = _Bodies();
    final repository = _repository(client);
    final sizes = <Size>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SiteImage(
            viewportAware: true,
            url: _url,
            siteUrl: _site,
            repository: repository,
            onNaturalSize: sizes.add,
          ),
        ),
      ),
    );
    await _drain(tester);
    expect(client.bodies, hasLength(1));
    client.bodies[0].add(await _png(tester));
    unawaited(client.bodies[0].close());
    await _waitFor(tester, () => sizes.isNotEmpty);
    expect(sizes, [const Size(40, 20)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested viewport clips prevent offscreen delivery', (
    tester,
  ) async {
    final client = _Bodies();
    final repository = _repository(client);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  const SizedBox(height: 350),
                  SizedBox(height: 100, child: _image(repository)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await _drain(tester);
    expect(client.bodies, isEmpty);
    scroll.jumpTo(350);
    await _drain(tester);
    expect(client.bodies, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scrolling promotes visible images ahead of retained near images',
    (tester) async {
      final client = _Bodies();
      final repository = _repository(client);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: SingleChildScrollView(
                controller: scroll,
                child: Column(
                  children: [
                    for (var index = 0; index < 40; index++)
                      SizedBox(
                        height: 20,
                        child: SiteImage(
                          viewportAware: true,
                          url: '$_site/image-$index.png',
                          siteUrl: _site,
                          repository: repository,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await _drain(tester);
      expect(client.urls, hasLength(8));
      scroll.jumpTo(305);
      await _drain(tester);
      expect(client.urls.length, greaterThan(8));
      expect(
        client.urls[8].path,
        '/image-15.png',
        reason: 'visible demand overtakes the older near-viewport consumer',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('two mounted owners share until the last owner disappears', (
    tester,
  ) async {
    final client = _Bodies();
    final repository = _repository(client);
    Widget frame(int count) => MaterialApp(
      home: Column(
        children: [
          for (var index = 0; index < count; index++)
            SizedBox(
              key: ValueKey(index),
              height: 100,
              child: _image(repository),
            ),
        ],
      ),
    );
    await tester.pumpWidget(frame(2));
    await _drain(tester);
    expect(client.bodies, hasLength(1));
    await tester.pumpWidget(frame(1));
    await _drain(tester);
    expect(client.cancelled, 0);
    await tester.pumpWidget(frame(0));
    await _drain(tester);
    expect(client.cancelled, 1);
    expect(tester.takeException(), isNull);
  });
}

SiteImage _image(SiteImageRepository repository) => SiteImage(
  viewportAware: true,
  url: _url,
  siteUrl: _site,
  repository: repository,
);

SiteImageRepository _repository(http.Client client) {
  final repository = SiteImageRepository(
    credentials: FakeApiCredentialReader(),
    lifecycle: SiteLifecycle(),
    client: client,
  );
  addTearDown(repository.dispose);
  return repository;
}

Future<void> _drain(WidgetTester tester) async {
  for (var index = 0; index < 4; index++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

Future<void> _waitFor(WidgetTester tester, bool Function() complete) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (complete()) return;
  }
}

Future<Uint8List> _png(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final image = await createTestImage(width: 40, height: 20, cache: false);
      try {
        return (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    }))!;

final class _Bodies extends http.BaseClient {
  final bodies = <StreamController<List<int>>>[];
  final urls = <Uri>[];
  var cancelled = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    urls.add(request.url);
    final body = StreamController<List<int>>();
    var finished = false;
    body.onCancel = () {
      if (!finished) cancelled++;
    };
    bodies.add(body);
    return http.StreamedResponse(
      body.stream.map((chunk) {
        finished = body.isClosed;
        return chunk;
      }),
      200,
      request: request,
    );
  }
}

final class _TraversalCounts {
  var paints = 0;
  var transforms = 0;
  var throwNext = false;
}

final class _TraversalProbe extends SingleChildRenderObjectWidget {
  const _TraversalProbe({required this.counts, required super.child});
  final _TraversalCounts counts;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _TraversalRenderBox(counts);
}

final class _TraversalRenderBox extends RenderProxyBox {
  _TraversalRenderBox(this.counts);
  final _TraversalCounts counts;

  @override
  bool paintsChild(RenderObject child) {
    counts.paints++;
    if (counts.throwNext) {
      counts.throwNext = false;
      throw StateError('image visibility probe failed');
    }
    return super.paintsChild(child);
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    counts.transforms++;
    super.applyPaintTransform(child, transform);
  }
}

final class _SelectiveStack extends MultiChildRenderObjectWidget {
  const _SelectiveStack({required this.selected, required super.children});
  final int selected;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _SelectiveRenderStack(selected);

  @override
  void updateRenderObject(
    BuildContext context,
    _SelectiveRenderStack renderObject,
  ) {
    renderObject.selected = selected;
    renderObject.markNeedsPaint();
  }
}

final class _SelectiveRenderStack extends RenderStack {
  _SelectiveRenderStack(this.selected)
    : super(textDirection: TextDirection.ltr);
  int selected;

  RenderBox get selectedChild => selected == 0 ? firstChild! : lastChild!;

  @override
  bool paintsChild(RenderBox child) => identical(child, selectedChild);

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = selectedChild;
    final data = child.parentData! as StackParentData;
    context.paintChild(child, offset + data.offset);
  }
}
