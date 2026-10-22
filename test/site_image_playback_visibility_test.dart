import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

class _FrameBinding extends AutomatedTestWidgetsFlutterBinding {
  int requests = 0;

  @override
  void scheduleFrame() {
    requests++;
    super.scheduleFrame();
  }
}

void main() {
  final binding = _FrameBinding();
  final results = <Map<String, Object>>[];
  final baseline = Platform.environment['GIF_PLAYBACK_BASELINE'] == '1';
  for (final nested in [false, true]) {
    testWidgets('retained CookedHtml GIF playback, nested viewport $nested', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scroll = ScrollController();
      final enabled = ValueNotifier(true);
      final reducedMotion = ValueNotifier(false);
      addTearDown(scroll.dispose);
      addTearDown(enabled.dispose);
      addTearDown(reducedMotion.dispose);
      final bytes = base64Decode(
        'R0lGODlhAQABAIAAAAAAAP///yH/C05FVFNDQVBFMi4wAwEAAAAh+QQACgAAACw'
        'AAAAAAQABAAACAkQBACH5BAAKAAAALAAAAAABAAEAAAICTAEAOw==',
      );
      const site = 'https://forum.example';
      var requests = 0;
      final repository = SiteImageRepository(
        credentials: FakeApiCredentialReader(),
        lifecycle: SiteLifecycle(),
        client: MockClient((request) async {
          requests++;
          return http.Response.bytes([
            ...bytes,
            int.parse(request.url.query),
          ], 200);
        }),
      );
      final shell = ShellController(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        siteImages: repository,
      );
      addTearDown(shell.dispose);
      var decoded = 0;
      final decodedImages = <ui.Image>[];
      var recording = false;
      final previousOnCreate = ui.Image.onCreate;
      ui.Image.onCreate = (image) {
        previousOnCreate?.call(image);
        if (recording || decodedImages.any(image.isCloneOf)) return;
        recording = true;
        decodedImages.add(image.clone());
        recording = false;
        decoded++;
      };
      addTearDown(() {
        ui.Image.onCreate = previousOnCreate;
        for (final image in decodedImages) {
          image.dispose();
        }
      });
      final reader = ValueListenableBuilder(
        valueListenable: enabled,
        builder: (context, enabled, child) => TickerMode(
          enabled: enabled,
          child: ValueListenableBuilder(
            valueListenable: reducedMotion,
            builder: (context, reducedMotion, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reducedMotion),
              child: child!,
            ),
            child: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  CookedHtml(
                    siteUrl: site,
                    html: [
                      for (var i = 0; i < 3; i++)
                        '<p><img src="$site/image.gif?$i" width="60" height="60"></p>',
                      for (var i = 0; i < 100; i++)
                        '<p>Reader body remains visible below these images.</p>',
                    ].join(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ShellScope(
            controller: shell,
            child: nested
                ? SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 100),
                        SizedBox(height: 300, child: reader),
                      ],
                    ),
                  )
                : reader,
          ),
        ),
      );
      for (var i = 0; i < 100; i++) {
        await _tick(tester);
        final raw = tester.widgetList<RawImage>(find.byType(RawImage));
        if (raw.length == 3 && raw.every((image) => image.image != null)) break;
      }
      expect(find.byType(SiteImage), findsNWidgets(3));
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .every((image) => image.image != null),
        isTrue,
      );
      final elements = tester.elementList(find.byType(SiteImage)).toList();
      final sizes = [
        for (final e in elements) tester.getSize(find.byWidget(e.widget)),
      ];

      Future<void> sample(String state, {required bool playing}) async {
        for (var i = 0; i < 4; i++) {
          await _tick(tester);
        }
        final displayed = [
          for (final raw in tester.widgetList<RawImage>(find.byType(RawImage)))
            raw.image!.clone(),
        ];
        final startDecoded = decoded;
        final startRequests = binding.requests;
        for (var i = 0; i < 10; i++) {
          await _tick(tester);
        }
        final count = decoded - startDecoded;
        results.add({
          'nested': nested,
          'state': state,
          'decodedFrames': count,
          'requestedAppFrames': binding.requests - startRequests,
          'windowFakeMs': 1100,
          'mountedImages': elements.length,
        });
        if (playing || (baseline && state == 'offscreen')) {
          expect(count, greaterThan(0), reason: state);
        } else {
          expect(count, 0, reason: state);
          expect(binding.requests - startRequests, 0, reason: state);
        }
        final current = tester
            .widgetList<RawImage>(find.byType(RawImage))
            .toList();
        for (var i = 0; i < displayed.length; i++) {
          expect(
            displayed[i].isCloneOf(current[i].image!),
            !(playing || (baseline && state == 'offscreen')),
            reason: '$state image $i',
          );
          displayed[i].dispose();
        }
        expect(tester.takeException(), isNull, reason: state);
      }

      await sample('visible', playing: true);
      final hiddenOffset = nested
          ? tester.getRect(find.byType(SiteImage).last).bottom - 100 + 10
          : 1000.0;
      scroll.jumpTo(hiddenOffset);
      await sample('offscreen', playing: false);
      final viewport = nested
          ? const Rect.fromLTWH(0, 100, 800, 300)
          : const Rect.fromLTWH(0, 0, 800, 600);
      expect(
        tester.getRect(find.byType(CookedHtml)).overlaps(viewport),
        isTrue,
      );
      for (final element in elements) {
        expect(TickerMode.valuesOf(element).enabled, isTrue);
        expect(
          tester.getRect(find.byWidget(element.widget)).overlaps(viewport),
          isFalse,
        );
      }
      if (nested) {
        expect(
          tester
              .getRect(find.byType(SiteImage).last)
              .overlaps(const Rect.fromLTWH(0, 0, 800, 600)),
          isTrue,
        );
      }
      expect(tester.elementList(find.byType(SiteImage)), elements);
      expect([
        for (final e in elements) tester.getSize(find.byWidget(e.widget)),
      ], sizes);
      scroll.jumpTo(0);
      await sample('reentry', playing: true);
      enabled.value = false;
      await tester.pump();
      await sample('tickerDisabled', playing: false);
      enabled.value = true;
      await tester.pump();
      await sample('tickerReentry', playing: true);
      for (final toggle
          in find
              .byKey(const ValueKey('gif-playback-toggle'))
              .evaluate()
              .toList()) {
        await tester.tap(find.byWidget(toggle.widget));
      }
      await sample('manualPause', playing: false);
      scroll.jumpTo(hiddenOffset);
      await _tick(tester);
      scroll.jumpTo(0);
      await sample('manualPauseReentry', playing: false);
      for (final toggle
          in find
              .byKey(const ValueKey('gif-playback-toggle'))
              .evaluate()
              .toList()) {
        await tester.tap(find.byWidget(toggle.widget));
      }
      reducedMotion.value = true;
      await tester.pump();
      await sample('reducedMotion', playing: true);
      expect(requests, 3, reason: 'scrolling reuses resolved encoded bytes');
      await tester.pumpWidget(const SizedBox.shrink());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
  }
  for (final sharedVisible in [false, true]) {
    testWidgets(
      'cached animation metadata gates playback without request gating, shared visible $sharedVisible',
      (tester) async {
        const site = 'https://forum.example';
        const url = '$site/animation.png';
        final bytes = base64Decode(
          'R0lGODlhAQABAIAAAAAAAP///yH/C05FVFNDQVBFMi4wAwEAAAAh+QQACgAAACw'
          'AAAAAAQABAAACAkQBACH5BAAKAAAALAAAAAABAAEAAAICTAEAOw==',
        );
        final repository = SiteImageRepository(
          credentials: FakeApiCredentialReader(),
          lifecycle: SiteLifecycle(),
          client: MockClient((_) async => http.Response.bytes(bytes, 200)),
        );
        addTearDown(repository.dispose);
        await repository.load(siteUrl: site, url: url);
        final motion = ValueNotifier(false);
        addTearDown(motion.dispose);
        final sizes = <Size>[];
        SiteImage image(Key key) => SiteImage(
          key: key,
          url: url,
          siteUrl: site,
          repository: repository,
          width: 60,
          height: 60,
          onNaturalSize: sizes.add,
        );
        const hiddenKey = ValueKey('hidden');
        const visibleKey = ValueKey('visible');
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => ValueListenableBuilder(
              valueListenable: motion,
              builder: (context, disabled, _) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: disabled),
                child: child!,
              ),
            ),
            home: SingleChildScrollView(
              child: Column(
                children: [
                  if (sharedVisible) image(visibleKey),
                  const SizedBox(height: 1000),
                  image(hiddenKey),
                ],
              ),
            ),
          ),
        );
        Finder raw(Key key) => find.descendant(
          of: find.byKey(key),
          matching: find.byType(RawImage),
        );
        for (var i = 0; i < 100; i++) {
          await _tick(tester);
          if (raw(hiddenKey).evaluate().isNotEmpty &&
              tester.widget<RawImage>(raw(hiddenKey)).image != null) {
            break;
          }
        }
        for (var i = 0; i < 4; i++) {
          await _tick(tester);
        }
        final hidden = tester.widget<RawImage>(raw(hiddenKey)).image!.clone();
        final visible = sharedVisible
            ? tester.widget<RawImage>(raw(visibleKey)).image!.clone()
            : null;
        addTearDown(hidden.dispose);
        if (visible != null) addTearDown(visible.dispose);
        for (var i = 0; i < 10; i++) {
          await _tick(tester);
        }
        expect(
          hidden.isCloneOf(tester.widget<RawImage>(raw(hiddenKey)).image!),
          !baseline,
        );
        if (visible != null) {
          expect(
            visible.isCloneOf(tester.widget<RawImage>(raw(visibleKey)).image!),
            isFalse,
          );
        }
        if (sharedVisible) {
          motion.value = true;
          for (var i = 0; i < 4; i++) {
            await _tick(tester);
          }
          final reduced = tester
              .widget<RawImage>(raw(visibleKey))
              .image!
              .clone();
          for (var i = 0; i < 10; i++) {
            await _tick(tester);
          }
          expect(
            reduced.isCloneOf(tester.widget<RawImage>(raw(visibleKey)).image!),
            isTrue,
          );
          reduced.dispose();
        }
        expect(sizes, everyElement(const Size(1, 1)));
        expect(sizes.length, sharedVisible ? 2 : 1);
        expect(tester.getSize(find.byKey(hiddenKey)), const Size(60, 60));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      },
    );
  }
  tearDownAll(() {
    final output = Platform.environment['GIF_PLAYBACK_OUTPUT'];
    if (output != null) {
      File(
        output,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
    }
  });
}

Future<void> _tick(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump(const Duration(milliseconds: 110));
  await tester.pump();
}
