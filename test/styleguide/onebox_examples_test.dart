import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_card.dart';
import 'package:discourse_native/src/plugins/discourse_github/oneboxes/commit/block.dart';
import 'package:discourse_native/src/plugins/discourse_github/oneboxes/github.dart';
import 'package:discourse_native/src/plugins/discourse_github/oneboxes/issue/block.dart';
import 'package:discourse_native/src/plugins/discourse_github/oneboxes/pr/block.dart';
import 'package:discourse_native/src/shell/code_block.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/inline_video.dart';
import 'package:discourse_native/src/shell/oneboxes/discourse/category/block.dart';
import 'package:discourse_native/src/shell/oneboxes/discourse/topic/block.dart';
import 'package:discourse_native/src/shell/oneboxes/discourse/user/block.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/shell/quote.dart';
import 'package:discourse_native/src/shell/youtube_video.dart';
import 'package:discourse_native/src/styleguide/examples/onebox_examples.dart';
import 'package:discourse_native/src/styleguide/examples/onebox_samples.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all/webview_all.dart';

import '../support/fake_media_webview.dart';

const _renderers = <String, Type>{
  'generic': OneboxCard,
  'discourse-topic': DiscourseTopicOnebox,
  'discourse-local-topic': QuoteBlock,
  'discourse-user': DiscourseUserOnebox,
  'discourse-category': DiscourseCategoryOnebox,
  'github-pr': GithubPullRequestOnebox,
  'github-issue': GithubIssueOnebox,
  'github-commit': GithubCommitOnebox,
  'github-file': CodeBlock,
  'reddit': DEmbed,
  'twitter': OneboxCard,
  'inline': CookedHtml,
  'github-pr-inline': CookedHtml,
  'youtube': YoutubeVideo,
  'video': InlineVideo,
  'event': EventCard,
};

void main() {
  late FakeMediaWebViewPlatform platform;
  late WebViewPlatform previousPlatform;

  setUp(() {
    previousPlatform = WebViewPlatform.instance ?? FakeMediaWebViewPlatform();
    platform = FakeMediaWebViewPlatform();
    WebViewPlatform.instance = platform;
  });
  tearDown(() => WebViewPlatform.instance = previousPlatform);

  testWidgets('Onebox is discoverable in the styleguide navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(const ComponentStyleguidePage(), scroll: false),
    );
    await tester.pumpAndSettle();
    final search = find.descendant(
      of: find.byKey(const ValueKey('styleguide-search')),
      matching: find.byType(TextField),
    );
    await tester.enterText(search, 'onebox');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Onebox'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onebox-picker')), findsOneWidget);
    expect(find.byType(OneboxCard), findsOneWidget);
    final picker = find.byKey(const ValueKey('onebox-picker'));
    final pickerPosition = tester.getTopLeft(picker);
    await tester.tap(find.byKey(const ValueKey('onebox-state-generic-2')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(picker), pickerPosition);
  });

  testWidgets(
    'search, keyboard selection and state changes use real renderers',
    (tester) async {
      await tester.pumpWidget(
        _host(Builder(builder: oneboxExamples.topLevelExample.builder)),
      );
      await tester.pumpAndSettle();
      final input = find.descendant(
        of: find.byKey(const ValueKey('onebox-picker')),
        matching: find.byType(TextField),
      );

      await tester.enterText(input, 'no-such-provider');
      await tester.pumpAndSettle();
      expect(find.text('No oneboxes found.'), findsOneWidget);
      expect(find.byType(OneboxCard), findsOneWidget);

      await tester.enterText(input, 'github pull request');
      await tester.pumpAndSettle();
      expect(find.byType(DComboboxItem<OneboxSample>), findsNWidgets(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(GithubPullRequestOnebox), findsOneWidget);
      expect(
        tester
            .widget<GithubPullRequestOnebox>(
              find.byType(GithubPullRequestOnebox),
            )
            .data
            .status,
        GithubPrStatus.draft,
      );

      for (final status in GithubPrStatus.values) {
        await tester.tap(
          find.byKey(ValueKey('onebox-state-github-pr-${status.index}')),
        );
        await tester.pump();
        expect(
          tester
              .widget<GithubPullRequestOnebox>(
                find.byType(GithubPullRequestOnebox),
              )
              .data
              .status,
          status,
        );
      }

      await tester.enterText(input, 'discourse user');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(GithubPullRequestOnebox), findsNothing);
      expect(find.byType(DiscourseUserOnebox), findsOneWidget);
      expect(
        tester
            .widget<DToggle>(
              find.byKey(const ValueKey('onebox-state-discourse-user-0')),
            )
            .pressed,
        isTrue,
      );
      await tester.tap(
        find.byKey(const ValueKey('onebox-state-discourse-user-0')),
      );
      await tester.pump();
      expect(
        tester
            .widget<DToggle>(
              find.byKey(const ValueKey('onebox-state-discourse-user-0')),
            )
            .pressed,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Reddit states replace and retire the live embed', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(Builder(builder: oneboxExamples.topLevelExample.builder)),
    );
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: find.byKey(const ValueKey('onebox-picker')),
      matching: find.byType(TextField),
    );
    await tester.enterText(input, 'reddit');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<DEmbed>(find.byType(DEmbed)).title,
      'Reddit post · r/FlutterDev',
    );
    final postController = platform.controllers.single;
    expect(find.byType(DSpinner), findsOneWidget);
    postController.channels['NativeEmbed']!.onMessageReceived(
      const JavaScriptMessage(message: 'loaded'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('onebox-state-reddit-1')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(postController.channels, isEmpty);
    expect(
      tester.widget<DEmbed>(find.byType(DEmbed)).title,
      'Reddit comment · r/FlutterDev',
    );
    final commentController = platform.controllers.last;
    expect(commentController, isNot(same(postController)));
    expect(commentController.documents.single.html, contains('/ihrafxr/'));
    commentController.channels['NativeEmbed']!.onMessageReceived(
      const JavaScriptMessage(message: 'loaded'),
    );
    await tester.pumpAndSettle();

    await tester.enterText(input, 'generic link');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(DEmbed), findsNothing);
    expect(find.byType(OneboxCard), findsOneWidget);
    expect(commentController.channels, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final configuration in [
    (name: 'light desktop', width: 640.0, theme: AppTheme.light, scale: 1.0),
    (
      name: 'dark narrow large text',
      width: 320.0,
      theme: AppTheme.dark,
      scale: 2.0,
    ),
  ]) {
    testWidgets(
      'all sample states mount their production renderer: ${configuration.name}',
      (tester) async {
        tester.view.physicalSize = Size(configuration.width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        expect(
          oneboxSamples.map((sample) => sample.id).toSet(),
          _renderers.keys.toSet(),
        );
        final errors = <String>[];
        for (final sample in oneboxSamples) {
          for (final state in sample.states) {
            await tester.pumpWidget(
              _host(
                KeyedSubtree(
                  key: ValueKey((sample.id, state.label)),
                  child: Builder(builder: state.builder),
                ),
                theme: configuration.theme,
                scale: configuration.scale,
              ),
            );
            await tester.pump(const Duration(milliseconds: 100));
            expect(
              find.byType(_renderers[sample.id]!),
              findsWidgets,
              reason: '${sample.name}/${state.label}',
            );
            if (tester.takeException() case final error?) {
              errors.add('${sample.name}/${state.label}: $error');
            }
          }
        }
        await tester.pumpWidget(const SizedBox());
        expect(errors, isEmpty);
      },
    );
  }

  testWidgets('narrow state buttons wrap and event retry updates locally', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(Builder(builder: oneboxExamples.topLevelExample.builder), scale: 2),
    );
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: find.byKey(const ValueKey('onebox-picker')),
      matching: find.byType(TextField),
    );
    await tester.enterText(input, 'github pull request');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final firstState = find.byKey(const ValueKey('onebox-state-github-pr-0'));
    final lastState = find.byKey(const ValueKey('onebox-state-github-pr-8'));
    expect(
      tester.getTopLeft(lastState).dy,
      greaterThan(tester.getTopLeft(firstState).dy),
    );

    await tester.enterText(input, 'event');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final going = find.descendant(
      of: find.byType(EventCard),
      matching: find.text('Going'),
    );
    await tester.ensureVisible(going);
    await tester.tap(going);
    await tester.pumpAndSettle();
    expect(
      tester.widget<EventCard>(find.byType(EventCard)).event.watching?.status,
      'going',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('onebox-state-event-4')),
    );
    await tester.tap(find.byKey(const ValueKey('onebox-state-event-4')));
    await tester.pumpAndSettle();
    expect(tester.widget<EventCard>(find.byType(EventCard)).error, isNotNull);
    final retry = find.text('Refresh event');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(tester.widget<EventCard>(find.byType(EventCard)).error, isNull);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(
  Widget child, {
  ThemeData? theme,
  double scale = 1,
  bool scroll = true,
}) => MaterialApp(
  theme: (theme ?? AppTheme.light).copyWith(platform: TargetPlatform.macOS),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: DFocusHighlight(child: child!),
  ),
  home: Scaffold(
    body: scroll
        ? SingleChildScrollView(padding: const EdgeInsets.all(24), child: child)
        : child,
  ),
);
