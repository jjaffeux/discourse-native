import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

import '../test/support/fakes.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final mobile =
      Platform.environment['COMPOSER_MOBILE'] == '1' ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
  final diagnostic = Platform.environment['PROFILE_COMPOSER_WIDGETS'] == '1';
  final profileCpu = Platform.environment['PROFILE_COMPOSER_CPU'] == '1';
  String setting(String name, String defined, String fallback) =>
      defined.isNotEmpty ? defined : Platform.environment[name] ?? fallback;
  final iterations = int.parse(
    setting(
      'COMPOSER_ITERATIONS',
      const String.fromEnvironment('COMPOSER_ITERATIONS'),
      '6',
    ),
  );
  final retainedDrafts = int.parse(
    setting(
      'COMPOSER_RETAINED_DRAFTS',
      const String.fromEnvironment('COMPOSER_RETAINED_DRAFTS'),
      '0',
    ),
  );
  final closeInactive =
      setting(
        'COMPOSER_CLOSE_INACTIVE',
        const String.fromEnvironment('COMPOSER_CLOSE_INACTIVE'),
        '0',
      ) ==
      '1';
  final resumeDraft =
      setting(
        'COMPOSER_RESUME_DRAFT',
        const String.fromEnvironment('COMPOSER_RESUME_DRAFT'),
        '0',
      ) ==
      '1';
  const description = 'profiles topic composer opening scrolling and closing';
  Future<void> profileComposer() async {
    binding.reset();
    final tester = LiveWidgetController(binding);
    final view = binding.platformDispatcher.implicitView!;
    final initialSemanticsEnabled = binding.semanticsEnabled;
    final initialSemanticsHandles = binding.debugOutstandingSemanticsHandles;
    Future<void> pumpWidget(Widget widget) async {
      runApp(widget);
      await tester.pump();
    }

    Future<void> settle() async {
      await tester.pumpAndSettle().timeout(const Duration(seconds: 10));
    }

    SharedPreferences.setMockInitialValues({});
    expect(iterations, greaterThan(0));
    if (closeInactive) expect(retainedDrafts, greaterThan(0));
    debugProfileBuildsEnabled = diagnostic;
    debugProfileLayoutsEnabled = diagnostic;
    debugProfilePaintsEnabled = diagnostic;
    expect(binding.testTextInput.isRegistered, isFalse);
    const user = DiscourseUser(id: 7, username: 'sam', canCreateTopic: true);
    final source = List.generate(
      120,
      (i) =>
          'Paragraph $i with **emphasis** and enough text to wrap across '
          'the composer viewport while scrolling a long topic draft.',
    ).join('\n\n');
    final fixtureDraft = ComposerDraft(
      reply: source,
      title: 'Composer performance fixture',
      action: ComposerDraft.createTopicAction,
    );
    final shell = ShellController(
      mobileNavigationEnabled: mobile,
      forumTabsEnabled: false,
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: user),
      ]),
      api: FakeDiscourseApi(
        user: user,
        draftToRestore: (draft: fixtureDraft, sequence: 1),
        categoryList: List.generate(
          250,
          (i) => TopicCategory(
            id: i + 1,
            name: 'Category $i',
            slug: 'cat-$i',
            color: '3188CC',
          ),
        ),
        composerCapabilities: const TopicComposerCapabilities(
          canTagTopics: true,
        ),
        feeds: const {'/latest.json': []},
        creatableFeedPaths: const {'/latest.json'},
      ),
      authenticator: FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'key',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    late final Map<String, Object?> capture;
    try {
      await shell.load();
      final size = view.physicalSize / view.devicePixelRatio;
      await pumpWidget(
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
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        await const MethodChannel(
          'org.discourse.native/window',
        ).invokeMethod<void>('dismissLaunchScreen');
        final app = File(Platform.resolvedExecutable).parent.parent.parent.path;
        final activation = await Process.run('/usr/bin/open', ['-a', app]);
        expect(activation.exitCode, 0);
      }
      await settle();
      for (var draft = 0; draft < retainedDrafts; draft++) {
        await shell.openNewTopicFromSidebar();
        shell.visibleComposer!.text.text = source;
        await settle();
      }
      final reports = <Map<String, Object?>>[];
      Future<void> settleKeyboard({required bool visible}) async {
        final deadline = Stopwatch()..start();
        var previousInset = -1.0;
        var stablePumps = 0;
        while (deadline.elapsed < const Duration(seconds: 5)) {
          await tester.pump(const Duration(milliseconds: 50));
          final inset = view.viewInsets.bottom;
          if ((inset > 0) == visible &&
              inset == previousInset &&
              !binding.hasScheduledFrame) {
            stablePumps++;
            if (stablePumps == 4) return;
          } else {
            stablePumps = 0;
          }
          previousInset = inset;
        }
        fail(
          'Native keyboard did not settle with visible=$visible; '
          'inset=${view.viewInsets.bottom}',
        );
      }

      final vm.VmService? cpuService;
      final isolateId = developer.Service.getIsolateId(Isolate.current);
      if (profileCpu) {
        final uri = (await developer.Service.getInfo()).serverWebSocketUri!;
        cpuService = await vmServiceConnectUri(uri.toString());
        await cpuService.setFlag('profiler', 'true');
        await cpuService.setFlag('profile_period', '250');
        addTearDown(cpuService.dispose);
      } else {
        cpuService = null;
      }

      Future<void> measure(
        String phase,
        int iteration,
        Future<void> Function() action,
      ) async {
        await cpuService?.clearCpuSamples(isolateId!);
        final frames = <ui.FrameTiming>[];
        void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
        binding.addTimingsCallback(collect);
        final start = developer.Timeline.now;
        final keyboardBefore = view.viewInsets.bottom;
        final task = developer.TimelineTask()..start('composer_$phase');
        late final int end;
        late final double keyboardAfter;
        try {
          await action();
          end = developer.Timeline.now;
          keyboardAfter = view.viewInsets.bottom;
          task.finish();
          await Future<void>.delayed(const Duration(milliseconds: 1100));
        } finally {
          binding.removeTimingsCallback(collect);
        }
        frames.removeWhere((frame) {
          final timestamp = frame.timestampInMicroseconds(
            ui.FramePhase.buildStart,
          );
          return timestamp < start || timestamp > end;
        });
        expect(frames, isNotEmpty, reason: phase);
        expect(
          frames.any((frame) => frame.rasterDuration.inMicroseconds > 1),
          isTrue,
          reason:
              '$phase has no valid raster work; verify native view dimensions and visibility.',
        );
        expect(binding.takeException(), isNull);
        final report = <String, Object?>{
          'phase': phase,
          'iteration': iteration,
          'elapsedMs': (end - start) / 1000,
          'startMicros': start,
          'endMicros': end,
          'keyboardBefore': keyboardBefore,
          'keyboardAfter': keyboardAfter,
          'frames': [
            for (final frame in frames)
              {
                'buildMs': frame.buildDuration.inMicroseconds / 1000,
                'rasterMs': frame.rasterDuration.inMicroseconds / 1000,
                'totalMs': frame.totalSpan.inMicroseconds / 1000,
                'frameNumber': frame.frameNumber,
                'buildStartMicros': frame.timestampInMicroseconds(
                  ui.FramePhase.buildStart,
                ),
              },
          ],
        };
        if (cpuService != null) {
          final samples = await cpuService.getCpuSamples(
            isolateId!,
            start,
            end - start,
          );
          binding.reportData ??= {};
          final functions = samples.functions!;
          final usedFunctions = {
            for (final sample in samples.samples!) ...?sample.stack,
          };
          binding.reportData!['cpu_${phase}_$iteration'] = {
            'sampleCount': samples.sampleCount,
            'samplePeriod': samples.samplePeriod,
            'timeOriginMicros': samples.timeOriginMicros,
            'timeExtentMicros': samples.timeExtentMicros,
            'functions': [
              for (var index = 0; index < functions.length; index++)
                if (usedFunctions.contains(index))
                  {'index': index, ...functions[index].toJson()},
            ],
            'samples': [for (final sample in samples.samples!) sample.toJson()],
          };
        }
        reports.add(report);
        debugPrint('COMPOSER_LIFECYCLE_PROFILE ${jsonEncode(report)}');
      }

      Future<void> run() async {
        for (var iteration = 0; iteration < iterations; iteration++) {
          await measure('opening', iteration, () async {
            if (resumeDraft) {
              await shell.resumeDraft(
                'https://meta.discourse.org',
                UserDraft(
                  key: 'new_topic_performance_$iteration',
                  sequence: 1,
                  data: fixtureDraft,
                ),
              );
            } else {
              await shell.openNewTopicFromSidebar();
            }
            await settle();
            expect(find.byType(ComposerPanel), findsOneWidget);
            if (resumeDraft) {
              expect(shell.visibleComposer!.raw, source);
            } else {
              expect(shell.visibleComposer!.raw, isEmpty);
            }
            if (mobile) await settleKeyboard(visible: true);
          });
          final composer = shell.visibleComposer!;
          composer.title.text = 'Composer performance fixture';
          composer.text.value = TextEditingValue(
            text: source,
            selection: const TextSelection.collapsed(offset: 0),
          );
          if (mobile) {
            composer.focus.requestFocus();
          } else {
            composer.focus.unfocus();
          }
          await settle();
          if (mobile) await settleKeyboard(visible: true);
          final scroll = mobile
              ? tester
                    .widget<CustomScrollView>(
                      find.byKey(const ValueKey('composer-mobile-scroll')),
                    )
                    .controller!
              : composer.text.imageScrollController!;
          expect(scroll.position.maxScrollExtent, greaterThan(1800));
          scroll.jumpTo(100);
          await settle();
          await measure('scrolling', iteration, () async {
            await scroll.animateTo(
              1900,
              duration: const Duration(seconds: 1),
              curve: Curves.linear,
            );
            await scroll.animateTo(
              100,
              duration: const Duration(seconds: 1),
              curve: Curves.linear,
            );
            expect(scroll.offset, closeTo(100, .1));
            expect(composer.raw, source);
          });
          await measure('closing', iteration, () async {
            final closingComposer = closeInactive
                ? shell.liveComposers.first
                : composer;
            final closing = shell.saveComposerAndClose(
              closingComposer,
              afterHide: () => binding.endOfFrame,
            );
            await settle();
            expect(await closing, isA<ComposerClosed>());
            await settle();
            if (mobile) {
              final remaining = shell.visibleComposer;
              await settleKeyboard(
                visible:
                    remaining != null &&
                    (remaining.focus.hasFocus || remaining.titleFocus.hasFocus),
              );
            }
            expect(shell.liveComposers, isNot(contains(closingComposer)));
            if (closeInactive) {
              expect(shell.visibleComposer, same(composer));
            }
            if (retainedDrafts == 0) {
              expect(shell.visibleComposer, isNull);
              expect(find.byType(ComposerPanel), findsNothing);
            }
          });
        }
      }

      if (diagnostic || profileCpu) {
        await binding.traceAction(run, reportKey: 'composerTimeline');
      } else {
        await run();
      }
      capture = {
        'label': setting(
          'PROFILE_LABEL',
          const String.fromEnvironment('PROFILE_LABEL'),
          'current',
        ),
        'openingDraft': resumeDraft ? 'resumed' : 'empty',
        'controller': 'native',
        'mobile': mobile,
        'debug': kDebugMode,
        'instrumented': diagnostic || profileCpu,
        'retainedDrafts': retainedDrafts,
        'closeInactive': closeInactive,
        'hostPlatform': defaultTargetPlatform.name,
        'width': size.width,
        'height': size.height,
        'pixelRatio': view.devicePixelRatio,
        'refreshRate': view.display.refreshRate,
        'semanticsEnabled': binding.semanticsEnabled,
        'platformSemanticsEnabled': binding.platformDispatcher.semanticsEnabled,
        'nativeTextInput': !binding.testTextInput.isRegistered,
        'initialSemanticsEnabled': initialSemanticsEnabled,
        'initialSemanticsHandles': initialSemanticsHandles,
        'finalSemanticsHandles': binding.debugOutstandingSemanticsHandles,
        'errors': 0,
        'paragraphs': 120,
        'reports': reports,
      };
    } finally {
      try {
        await pumpWidget(const SizedBox.shrink());
      } finally {
        try {
          shell.dispose();
        } finally {
          debugProfileBuildsEnabled = false;
          debugProfileLayoutsEnabled = false;
          debugProfilePaintsEnabled = false;
        }
      }
    }
    binding.reportData ??= {};
    binding.reportData!['composerLifecycle'] = capture;
  }

  test(description, () async {
    addTearDown(() {
      try {
        binding.postTest();
      } catch (error, stack) {
        reportTestException(
          FlutterErrorDetails(exception: error, stack: stack),
          description,
        );
        rethrow;
      }
    });
    final nonNativeHandles =
        binding.debugOutstandingSemanticsHandles -
        (binding.platformDispatcher.semanticsEnabled ? 1 : 0);
    await binding.runTest(profileComposer, () {
      expect(binding.takeException(), isNull);
      expect(
        binding.debugOutstandingSemanticsHandles -
            (binding.platformDispatcher.semanticsEnabled ? 1 : 0),
        nonNativeHandles,
        reason: 'Application-owned semantics handles must be disposed',
      );
    }, description: description);
    binding.reportData ??= {};
    binding.reportData!['composerLifecycleComplete'] = true;
  }, timeout: const Timeout(Duration(minutes: 3)));
}
