import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:discourse_native/discourse_ui.dart';

import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/media_pipeline.dart';

void _replaceEmojiCache(http.Client client) =>
    installTestMediaPipeline(client: client);

void main() {
  testWidgets('keeps an ordinary title on the plain Text path', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _TestTitle(controller: controller, title: 'An ordinary topic'),
    );

    expect(find.text('An ordinary topic'), findsOneWidget);
    expect(find.byType(SiteEmojiImage), findsNothing);
  });

  for (final (platform, width) in [
    (TargetPlatform.iOS, 390.0),
    (TargetPlatform.android, 390.0),
    (TargetPlatform.macOS, 1200.0),
  ]) {
    for (final scale in [1.0, 1.25, 2.0]) {
      testWidgets('unread title text scales once on $platform at $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final (title, tail) in [
          ('Deal: LEGO Bricklink', 'Bricklink'),
          ("Kudzai's Weekly Updates - 2026", '2026'),
          ('A community guide to', 'guide to'),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark.copyWith(platform: platform),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: TopicListRow(
                    siteUrl: 'https://meta.example',
                    topic: Topic(
                      id: 1,
                      title: title,
                      slug: 'title',
                      unreadPosts: 7,
                    ),
                    onTap: () {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final headParagraph = tester.renderObject<RenderParagraph>(
            find
                .descendant(
                  of: find.byType(TopicTitle),
                  matching: find.byType(RichText),
                )
                .first,
          );
          final tailParagraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.text(tail),
              matching: find.byType(RichText),
            ),
          );
          final headGlyph = _paintedFirstGlyph(headParagraph);
          final tailGlyph = _paintedFirstGlyph(tailParagraph);
          expect(
            tailGlyph.height,
            closeTo(headGlyph.height, .01),
            reason: 'The badge-adjacent words must match the title text size.',
          );
          final badge = tester.renderObject<RenderBox>(
            find.byKey(const ValueKey('inbox-row-unread-1')),
          );
          final badgeBounds = MatrixUtils.transformRect(
            badge.getTransformTo(null),
            Offset.zero & badge.size,
          );
          expect(
            badgeBounds.center.dy,
            closeTo(tailGlyph.center.dy, 2),
            reason: 'The unread badge stays beside the final title words.',
          );
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('draws shortcodes using the site emoji artwork', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    _replaceEmojiCache(
      MockClient((_) async => http.Response.bytes(_emojiPng, 200)),
    );

    await tester.pumpWidget(
      _TestTitle(
        controller: controller,
        title: 'Lightning :high_voltage: talks',
      ),
    );
    await tester.pumpAndSettle();

    final emoji = tester.widget<SiteEmojiImage>(find.byType(SiteEmojiImage));
    expect(emoji.name, 'high_voltage');
    expect(
      tester.widget<EmojiImage>(find.byType(EmojiImage)).url,
      'https://meta.example/images/emoji/twitter/high_voltage.png',
    );
    expect(find.byType(Image), findsOneWidget);
    expect(
      find.bySemanticsLabel('Lightning :high_voltage: talks'),
      findsOneWidget,
    );
  });

  for (final inTopicList in [false, true]) {
    testWidgets(
      'renders the calendar alias in a topic ${inTopicList ? 'row' : 'header'}',
      (tester) async {
        final controller = _controller();
        addTearDown(controller.dispose);
        final artworkRequests = <Uri>[];
        _replaceEmojiCache(
          MockClient((request) async {
            artworkRequests.add(request.url);
            return http.Response.bytes(_emojiPng, 200);
          }),
        );
        const title = 'Team Availability :calendar:';

        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: inTopicList
                    ? TopicListRow(
                        siteUrl: 'https://meta.example',
                        topic: const Topic(id: 1, title: title, slug: 'team'),
                        onTap: () {},
                      )
                    : const TopicTitle(title, siteUrl: 'https://meta.example'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final emoji = tester.widget<SiteEmojiImage>(
          find.byType(SiteEmojiImage),
        );
        expect(emoji.name, 'date');
        expect(emoji.alt, ':calendar:');
        expect(artworkRequests, [
          Uri.parse('https://meta.example/images/emoji/twitter/date.png'),
        ]);
        expect(
          find.descendant(
            of: find.byType(SiteEmojiImage),
            matching: find.byType(Image),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('sizes inline emoji to the topic title text', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    _replaceEmojiCache(MockClient((_) async => http.Response('', 404)));

    await tester.pumpWidget(
      _TestTitle(
        controller: controller,
        title: 'Announcements :high_voltage:',
        style: const TextStyle(fontSize: 20),
      ),
    );
    await tester.pumpAndSettle();

    final emoji = tester.widget<SiteEmojiImage>(find.byType(SiteEmojiImage));
    expect(emoji.size, 20);
  });

  testWidgets('recognizes adjacent emoji and skin tones', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    _replaceEmojiCache(MockClient((_) async => http.Response('', 404)));

    await tester.pumpWidget(
      _TestTitle(controller: controller, title: ':wave:t3::sparkles:'),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<SiteEmojiImage>(find.byType(SiteEmojiImage))
          .map((emoji) => emoji.name),
      ['wave:t3', 'sparkles'],
    );
  });

  testWidgets(
    'inline editor keeps its presentation and places the first caret by click',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final saved = <String>[];
      const style = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);

      await tester.pumpWidget(
        _TestEditor(
          controller: controller,
          title: 'An ordinary topic with a deliberately long title',
          width: 180,
          style: style,
          onSave: (title) async {
            saved.add(title);
            return null;
          },
        ),
      );

      final editor = find.byType(InlineTopicTitleEditor);
      final field = find.byKey(const ValueKey('topic-header-title-field'));
      final pointer = tester.widget<MouseRegion>(
        find.byKey(const ValueKey('topic-header-title-pointer')),
      );
      final textField = tester.widget<TextField>(
        find.descendant(of: field, matching: find.byType(TextField)),
      );
      final displayTitle = tester.widget<TopicTitle>(
        find.descendant(of: editor, matching: find.byType(TopicTitle)),
      );
      final idleSize = tester.getSize(editor);
      expect(pointer.cursor, SystemMouseCursors.text);
      expect(tester.widget<DInput>(field).borderless, isTrue);
      expect(
        tester
            .widget<DTooltip>(
              find.descendant(of: editor, matching: find.byType(DTooltip)),
            )
            .message,
        'Edit topic title',
      );
      expect(textField.style, style);
      expect(textField.decoration?.isCollapsed, isTrue);
      expect(textField.decoration?.border, InputBorder.none);
      expect(displayTitle.maxLines, 1);
      expect(displayTitle.overflow, TextOverflow.ellipsis);
      expect(idleSize.width, 180);

      final editorRect = tester.getRect(editor);
      await tester.tapAt(Offset(editorRect.left + 1, editorRect.center.dy));
      await tester.pump();

      expect(textField.focusNode?.hasFocus, isTrue);
      expect(textField.controller?.selection.isCollapsed, isTrue);
      expect(textField.controller?.selection.baseOffset, 0);
      expect(tester.getSize(editor), idleSize);

      await tester.enterText(field, 'A clearer topic title');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(saved, ['A clearer topic title']);
      expect(textField.focusNode?.hasFocus, isFalse);
      expect(
        tester
            .widget<TopicTitle>(
              find.descendant(of: editor, matching: find.byType(TopicTitle)),
            )
            .title,
        'A clearer topic title',
      );
    },
  );

  testWidgets(
    'an explicit edit request takes focus once on an existing editor',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      Future<void> pumpEditor(bool autofocus) async {
        await tester.pumpWidget(
          _TestEditor(
            controller: controller,
            title: 'Original title',
            autofocus: autofocus,
            showEditingFrame: true,
            onSave: (_) async => null,
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpEditor(false);
      await pumpEditor(true);
      final editor = find.byType(DInput);
      expect(tester.widget<DInput>(editor).focusNode!.hasPrimaryFocus, isTrue);
      final outsideFocus = Focus.of(tester.element(find.text('Outside')));
      outsideFocus.requestFocus();
      await tester.pumpAndSettle();
      await pumpEditor(true);
      expect(editor, findsNothing);
      expect(outsideFocus.hasPrimaryFocus, isTrue);
      expect(find.text('Save'), findsNothing);
    },
  );

  for (final framed in [false, true]) {
    testWidgets(
      'a ${framed ? 'framed' : 'borderless'} editor draws a translated title '
      'and edits the stored one',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final controller = _controller();
        addTearDown(controller.dispose);
        final saved = <String>[];
        final baselines = <String>[];
        await tester.pumpWidget(
          _TestEditor(
            controller: controller,
            title: 'Original title',
            localizedTitle: 'Un titre traduit',
            baselines: baselines,
            showEditingFrame: framed,
            onSave: (value) async {
              saved.add(value);
              return null;
            },
          ),
        );
        final shown = find.byType(TopicTitle);
        expect(tester.widget<TopicTitle>(shown).title, 'Un titre traduit');
        if (!framed) {
          expect(find.bySemanticsLabel('Un titre traduit'), findsOneWidget);
        }

        await tester.tap(
          find.byKey(const ValueKey('topic-header-title-field')),
        );
        await tester.pumpAndSettle();
        final field = find.byType(DInput);
        expect(tester.widget<DInput>(field).controller!.text, 'Original title');
        await tester.enterText(field, 'Renamed title');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(saved, ['Renamed title']);
        expect(baselines, ['Original title']);
        expect(tester.widget<TopicTitle>(shown).title, 'Un titre traduit');
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'inline title saves on blur and preserves a failed edit for retry or Escape',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final attempted = <String>[];
      var fail = true;
      await tester.pumpWidget(
        _TestEditor(
          controller: controller,
          title: 'Original title',
          showEditingFrame: true,
          onSave: (value) async {
            attempted.add(value);
            return fail ? 'The title could not be saved.' : null;
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('topic-header-title-field')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(DInput), 'Retained edit');
      await tester.tap(find.byKey(const ValueKey('outside-title-editor')));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsNothing);
      expect(attempted, ['Retained edit']);
      final field = tester.widget<DInput>(find.byType(DInput));
      expect(field.controller!.text, 'Retained edit');
      expect(field.focusNode!.hasFocus, isTrue);
      expect(find.text('The title could not be saved.'), findsOneWidget);
      fail = false;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(attempted, ['Retained edit', 'Retained edit']);
      expect(find.byType(DInput), findsNothing);
      expect(
        tester.widget<TopicTitle>(find.byType(TopicTitle)).title,
        'Retained edit',
      );
      await tester.tap(find.byKey(const ValueKey('topic-header-title-field')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(DInput), 'Discard this');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(attempted.length, 2);
      expect(
        tester.widget<TopicTitle>(find.byType(TopicTitle)).title,
        'Retained edit',
      );
      expect(find.byType(DInput), findsNothing);
      await tester.tap(find.byKey(const ValueKey('topic-header-title-field')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(DInput), 'Saved after cancellation');
      await tester.tap(find.byKey(const ValueKey('outside-title-editor')));
      await tester.pumpAndSettle();
      expect(attempted.last, 'Saved after cancellation');
      expect(find.byType(DInput), findsNothing);
    },
  );

  testWidgets(
    'saving on blur preserves focus on the next control while the request completes',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final saved = <String>[];
      final pending = Completer<String?>();
      Future<void> pumpTitle(String title) => tester.pumpWidget(
        _TestEditor(
          controller: controller,
          title: title,
          showEditingFrame: true,
          onSave: (value) async {
            saved.add(value);
            return pending.future;
          },
        ),
      );
      await pumpTitle('Original title');
      await tester.tap(find.byKey(const ValueKey('topic-header-title-field')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(DInput), 'My draft');
      final outsideFocus = Focus.of(tester.element(find.text('Outside')));
      outsideFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(
        tester.widget<DInput>(find.byType(DInput)).focusNode!.hasFocus,
        isFalse,
      );
      await pumpTitle('Updated on the server');
      expect(
        tester.widget<DInput>(find.byType(DInput)).controller!.text,
        'My draft',
      );
      expect(saved, ['My draft']);
      expect(outsideFocus.hasPrimaryFocus, isTrue);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('My draft'), findsOneWidget);
      expect(outsideFocus.hasPrimaryFocus, isTrue);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'inline ${brightness.name} title supports Enter and Escape at large text without buttons',
      (tester) async {
        final controller = _controller();
        addTearDown(controller.dispose);
        final saved = <String>[];
        await tester.pumpWidget(
          _TestEditor(
            controller: controller,
            title: 'Making the first week feel more welcoming',
            width: 360,
            maxLines: 3,
            showEditingFrame: true,
            theme: brightness == Brightness.dark
                ? AppTheme.dark
                : AppTheme.light,
            textScaler: const TextScaler.linear(2),
            onSave: (value) async {
              saved.add(value);
              return null;
            },
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey('topic-header-title-field')),
        );
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(DButton, 'Save').hitTestable(),
          findsNothing,
        );
        expect(
          find.widgetWithText(DButton, 'Cancel').hitTestable(),
          findsNothing,
        );
        await tester.enterText(
          find.byType(DInput),
          'A more welcoming first week',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(saved, ['A more welcoming first week']);
        expect(find.byType(DInput), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('topic-header-title-field')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(DInput), 'Do not save');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(saved.length, 1);
        expect(find.byType(DInput), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('inline editor preserves registered site emoji artwork', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    _replaceEmojiCache(
      MockClient((_) async => http.Response.bytes(_emojiPng, 200)),
    );

    await tester.pumpWidget(
      _TestEditor(
        controller: controller,
        title: 'Lightning :high_voltage: talks',
        onSave: (_) async => null,
      ),
    );
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('topic-header-title-field'));
    await tester.tap(field);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: field, matching: find.byType(SiteEmojiImage)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: field, matching: find.byType(TextField)),
          )
          .controller
          ?.text,
      'Lightning :high_voltage: talks',
    );
  });
}

Rect _paintedFirstGlyph(RenderParagraph paragraph) {
  final box = paragraph
      .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1))
      .first;
  return MatrixUtils.transformRect(
    paragraph.getTransformTo(null),
    box.toRect(),
  );
}

ShellController _controller() => ShellController(
  instanceStore: FakeInstanceStore([instance('meta.example')]),
  api: FakeDiscourseApi(
    emojisBySite: {
      'https://meta.example': const [
        SiteEmoji(
          name: 'high_voltage',
          url: '/images/emoji/twitter/high_voltage.png',
        ),
        SiteEmoji(name: 'wave', url: '/images/emoji/wave.png', tonable: true),
        SiteEmoji(name: 'sparkles', url: '/images/emoji/sparkles.png'),
        SiteEmoji(name: 'date', url: '/images/emoji/twitter/date.png'),
      ],
    },
  ),
  authenticator: FakeAuthenticator(),
  drafts: FakeDraftStore(),
  trackers: FakeSiteTracker.reset(),
);

class _TestTitle extends StatelessWidget {
  const _TestTitle({required this.controller, required this.title, this.style});

  final ShellController controller;
  final String title;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: TopicTitle(title, siteUrl: 'https://meta.example', style: style),
      ),
    ),
  );
}

class _TestEditor extends StatelessWidget {
  const _TestEditor({
    required this.controller,
    required this.title,
    this.localizedTitle,
    this.baselines,
    required this.onSave,
    this.style,
    this.width,
    this.maxLines = 1,
    this.showEditingFrame = false,
    this.autofocus = false,
    this.theme,
    this.textScaler = TextScaler.noScaling,
  });

  final ShellController controller;
  final String title;
  final String? localizedTitle;

  /// Collects the conflict baseline each save is checked against.
  final List<String>? baselines;
  final Future<String?> Function(String title) onSave;
  final TextStyle? style;
  final double? width;
  final int maxLines;
  final bool showEditingFrame;
  final bool autofocus;
  final ThemeData? theme;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: MaterialApp(
      theme: theme ?? AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: DToaster(child: child!),
      ),
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: width,
              child: InlineTopicTitleEditor(
                title: title,
                localizedTitle: localizedTitle,
                siteUrl: 'https://meta.example',
                style: style,
                onSave: (title, {required originalTitle}) {
                  baselines?.add(originalTitle);
                  return onSave(title);
                },
                maxLines: maxLines,
                showEditingFrame: showEditingFrame,
                autofocus: autofocus,
              ),
            ),
            TextButton(
              key: const ValueKey('outside-title-editor'),
              onPressed: () {},
              child: const Text('Outside'),
            ),
          ],
        ),
      ),
    ),
  );
}

final Uint8List _emojiPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
