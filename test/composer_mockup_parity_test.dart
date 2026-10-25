import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/composer_placement.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/shell/composer/panel.dart';
import 'package:discourse_native/src/shell/composer/placement_icon.dart';
import 'package:discourse_native/src/shell/composer/presentation.dart';
import 'package:discourse_native/src/shell/composer/presentation_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _capture = ValueKey('composer-parity-capture');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    if (Platform.environment['COMPOSER_PARITY_RENDER_DIR'] == null) return;
    for (final (family, path) in [
      ('Lato', 'assets/fonts/Lato-Regular.ttf'),
      ('Open Sans', 'assets/fonts/OpenSans.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
  });

  testWidgets(
    'title and body align, Enter enters body and boundary keys return to title',
    (tester) async {
      final h = await _Harness.create(tester);
      final composer = h.shell.visibleComposer!;
      composer.title.text = 'The topic title';
      composer.text.value = const TextEditingValue(
        text: 'First paragraph\nSecond line',
        selection: TextSelection.collapsed(offset: 0),
      );
      await tester.pump();
      final title = find.descendant(
        of: find.byKey(const ValueKey('composer-topic-title')),
        matching: find.byType(EditableText),
      );
      final body = find.descendant(
        of: find.byType(ComposerEditor),
        matching: find.byType(EditableText),
      );
      expect(
        tester.getTopLeft(title).dx,
        closeTo(tester.getTopLeft(body).dx, .1),
      );
      composer.titleFocus.requestFocus();
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(composer.focus.hasPrimaryFocus, isTrue);
      expect(composer.text.selection.baseOffset, 0);
      for (final key in [
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.backspace,
      ]) {
        composer.text.selection = const TextSelection.collapsed(offset: 0);
        composer.focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(key);
        await tester.pump();
        expect(composer.titleFocus.hasPrimaryFocus, isTrue);
        expect(composer.title.selection.baseOffset, composer.title.text.length);
        expect(composer.text.text, 'First paragraph\nSecond line');
      }
      composer.text.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(composer.focus.hasPrimaryFocus, isTrue);
      expect(composer.text.text, ' paragraph\nSecond line');
      await tester.runAsync(composer.finishDraftSaves);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'draft tabs retain editors and undo, closing tabs saves and closes the last',
    (tester) async {
      final h = await _Harness.create(tester);
      final first = h.shell.visibleComposer!;
      first.title.text = 'First draft';
      first.text.value = const TextEditingValue(
        text: 'First source',
        selection: TextSelection.collapsed(offset: 5),
      );
      final firstEditor = tester.state(find.byType(ComposerEditor));
      await h.shell.openNewTopicFromSidebar();
      final second = h.shell.visibleComposer!;
      second.title.text = 'Second draft';
      second.text.text = 'Second source';
      await tester.pumpAndSettle();
      expect(h.shell.liveComposers, [first, second]);
      expect(find.byType(DDocumentTab), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('composer-all-drafts')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('First draft').hitTestable().last);
      await tester.pumpAndSettle();
      expect(h.shell.visibleComposer, same(first));
      expect(
        tester.state(find.byType(ComposerEditor).hitTestable()),
        same(firstEditor),
      );
      expect(first.text.selection.baseOffset, 5);
      first.history.transact(() => first.text.text = 'First changed');
      h.shell.selectComposer(second);
      await tester.pumpAndSettle();
      h.shell.selectComposer(first);
      await tester.pumpAndSettle();
      first.history.undo();
      expect(first.text.text, 'First source');
      await tester.tap(
        find.byKey(ValueKey(('composer-draft-close', first))).hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(first.isDisposed, isTrue);
      expect(h.shell.visibleComposer, same(second));
      expect(
        h.api.draftsSaved.any(
          (d) =>
              d['draftKey'] == first.target.draftKey &&
              (d['data'] as String).contains('First source'),
        ),
        isTrue,
      );
      await tester.tap(
        find.byKey(ValueKey(('composer-draft-close', second))).hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(h.shell.liveComposers, isEmpty);
      expect(h.shell.visibleComposer, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final mobile in [false, true]) {
    testWidgets(
      'closing the active draft reveals the neighboring minimized draft mobile=$mobile',
      (tester) async {
        final h = await _Harness.create(
          tester,
          mobile: mobile,
          size: mobile ? const Size(390, 844) : const Size(1000, 700),
        );
        final first = h.shell.visibleComposer!;
        first.text.text = 'First draft writing';
        await h.shell.openNewTopicFromSidebar();
        final next = h.shell.visibleComposer!;
        next.title.text = 'The neighboring draft';
        next.text.text = 'Neighbor writing';
        await tester.pumpAndSettle();
        final neighborEditor = tester.state(
          find.byType(ComposerEditor).hitTestable(),
        );
        next.text.selection = const TextSelection.collapsed(offset: 5);
        await _minimize(tester, mobile: mobile);
        await tester.pumpAndSettle();
        await h.shell.openNewTopicFromSidebar();
        final last = h.shell.visibleComposer!;
        last.text.text = 'Last draft writing';
        await tester.pumpAndSettle();
        h.shell.selectComposer(first);
        await tester.pumpAndSettle();
        if (mobile) {
          await tester.tap(find.byKey(const ValueKey('composer-close')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save draft').hitTestable());
        } else {
          await tester.tap(
            find.byKey(ValueKey(('composer-draft-close', first))).hitTestable(),
          );
        }
        await tester.pumpAndSettle();
        expect(h.shell.visibleComposer, same(next));
        expect(find.byType(ComposerEditor).hitTestable(), findsOneWidget);
        expect(next.focus.hasFocus, isTrue);
        expect(
          tester.state(find.byType(ComposerEditor).hitTestable()),
          same(neighborEditor),
        );
        expect(next.text.selection.baseOffset, 5);
        for (final composer in h.shell.liveComposers) {
          await tester.runAsync(composer.finishDraftSaves);
        }
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'background forum draft closure leaves the current minimized draft put away',
    (tester) async {
      final h = await _Harness.create(tester, secondSite: true);
      await h.shell.openNewTopicFromSidebar();
      final background = h.shell.visibleComposer!;
      background.text.text = 'Background forum draft';
      h.shell.selectInstance(1);
      await h.shell.loadFeed('latest');
      await h.shell.openNewTopicFromSidebar();
      await tester.pumpAndSettle();
      final current = h.shell.visibleComposer!;
      current.text.text = 'Current forum draft';
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-minimize')));
      await tester.pumpAndSettle();
      h.shell.closeComposer(composer: background);
      await tester.pumpAndSettle();
      expect(h.shell.visibleComposer, same(current));
      expect(find.byType(ComposerEditor).hitTestable(), findsNothing);
      expect(
        find.byKey(const ValueKey('composer-restore')).hitTestable(),
        findsOneWidget,
      );
      for (final composer in h.shell.liveComposers) {
        await tester.runAsync(composer.finishDraftSaves);
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  for (final mobile in [false, true]) {
    testWidgets(
      'resuming a retained minimized draft reveals it (mobile=$mobile)',
      (tester) async {
        final h = await _Harness.create(
          tester,
          mobile: mobile,
          size: mobile ? const Size(390, 844) : const Size(1000, 700),
        );
        final composer = h.shell.visibleComposer!;
        composer.title.text = 'Resume this draft';
        composer.text.value = const TextEditingValue(
          text: 'Retained text and caret',
          selection: TextSelection.collapsed(offset: 6),
        );
        await tester.pumpAndSettle();
        await _minimize(tester, mobile: mobile);
        await tester.pumpAndSettle();
        expect(find.byType(ComposerEditor).hitTestable(), findsNothing);
        await h.shell.resumeDraft(
          composer.target.siteUrl,
          UserDraft(
            key: composer.target.draftKey,
            sequence: composer.draftSequence,
            data: const ComposerDraft(
              reply: 'Retained text and caret',
              title: 'Resume this draft',
              action: ComposerDraft.createTopicAction,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(h.shell.visibleComposer, same(composer));
        expect(find.byType(ComposerEditor).hitTestable(), findsOneWidget);
        expect(composer.focus.hasFocus, isTrue);
        expect(composer.text.selection.baseOffset, 6);
        await tester.runAsync(composer.finishDraftSaves);
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('position choices follow available workspace width', (
    tester,
  ) async {
    final h = await _Harness.create(
      tester,
      size: const Size(1000, 700),
      workspaceInset: 500,
    );
    await tester.tap(find.byKey(const ValueKey('composer-position')));
    await tester.pumpAndSettle();
    final group = tester.widget<DToggleGroup<ComposerPlacement>>(
      find.byType(DToggleGroup<ComposerPlacement>),
    );
    expect(group.items.map((item) => item.value), [
      ComposerPlacement.bottom,
      ComposerPlacement.fullScreen,
    ]);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.runAsync(h.shell.visibleComposer!.finishDraftSaves);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'All drafts reveals its page from full screen while retaining the editor',
    (tester) async {
      final h = await _Harness.create(tester);
      final composer = h.shell.visibleComposer!;
      composer.text.value = const TextEditingValue(
        text: 'Retained writing',
        selection: TextSelection.collapsed(offset: 4),
      );
      final presentation = tester
          .widget<ComposerPresentationHost>(
            find.byType(ComposerPresentationHost),
          )
          .controller!;
      presentation.dock(ComposerPlacement.fullScreen);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-all-drafts')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All drafts'));
      await tester.pumpAndSettle();
      expect(presentation.preference.placement, ComposerPlacement.right);
      expect(h.shell.currentContent!.id, 'drafts');
      expect(h.shell.visibleComposer, same(composer));
      expect(composer.text.selection.baseOffset, 4);
      await tester.runAsync(composer.finishDraftSaves);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'draft tabs keep authorized reply visibility controls available',
    (tester) async {
      final h = await _Harness.create(tester);
      const site = 'https://meta.discourse.org';
      h.shell.store.put(
        site,
        const TopicDetail(
          id: 7,
          title: 'A reply destination',
          stream: [],
          canCreatePost: true,
        ),
      );
      h.shell.pushContent(
        ContentRoute.topic(
          topicId: 7,
          slug: 'reply-destination',
          title: 'A reply destination',
        ),
      );
      h.shell.openReply();
      await tester.pumpAndSettle();
      final composer = h.shell.visibleComposer!;
      await tester.tap(find.byKey(const ValueKey('composer-reply-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-toggle-whisper')));
      await tester.pumpAndSettle();
      expect(composer.whisper, isTrue);
      expect(find.byKey(const ValueKey('composer-all-drafts')), findsOneWidget);
      await tester.runAsync(composer.finishDraftSaves);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a parked PM draft keeps one owner for the shared server key', (
    tester,
  ) async {
    final h = await _Harness.create(tester);
    final topicDraft = h.shell.visibleComposer!;
    h.shell.openPrivateMessage(
      siteUrl: 'https://meta.discourse.org',
      targetRecipients: 'first',
    );
    await tester.pumpAndSettle();
    final message = h.shell.visibleComposer!;
    expect(message.target.isPrivateMessage, isTrue);
    message.title.text = 'A private title';
    message.text.text = 'Private writing';
    h.shell.selectComposer(topicDraft);
    await tester.pumpAndSettle();
    message.beginClose();
    h.shell.openPrivateMessage(
      siteUrl: 'https://meta.discourse.org',
      targetRecipients: 'second',
    );
    expect(h.shell.visibleComposer, same(topicDraft));
    expect(
      h.shell.liveComposers.where((c) => c.target.isPrivateMessage),
      hasLength(1),
    );
    h.shell.restoreComposerAfterFailedClose(message);
    h.shell.openPrivateMessage(
      siteUrl: 'https://meta.discourse.org',
      targetRecipients: 'second',
    );
    await tester.pumpAndSettle();
    expect(message.isDisposed, isTrue);
    expect(
      h.shell.liveComposers.where((c) => c.target.isPrivateMessage),
      hasLength(1),
    );
    expect(h.shell.visibleComposer!.target.targetRecipients, 'second');
    expect(topicDraft.isDisposed, isFalse);
    await tester.runAsync(h.shell.visibleComposer!.finishDraftSaves);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'composer glyph borrows desktop panel visibility and dock position',
    (tester) async {
      final h = await _Harness.create(tester);
      final composer = h.shell.visibleComposer!;
      final icon = find.descendant(
        of: find.byType(ComposerPlacementIcon).first,
        matching: find.byType(DLayoutGlyph),
      );
      expect(tester.widget<DLayoutGlyph>(icon).mainVisible, isTrue);
      expect(tester.widget<DLayoutGlyph>(icon).secondaryVisible, isFalse);
      expect(tester.widget<DLayoutGlyph>(icon).dock, DLayoutGlyphDock.right);
      h.shell.topicPanelsVisible = true;
      composer.title.text = 'Rebuild the header';
      await tester.pump();
      expect(tester.widget<DLayoutGlyph>(icon).secondaryVisible, isTrue);
      await tester.runAsync(composer.finishDraftSaves);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'close offers Save first, Escape and outside keep writing, Enter saves',
    (tester) async {
      final h = await _Harness.create(tester);
      final composer = h.shell.visibleComposer!;
      composer.title.text = 'A retained title';
      composer.text.text = 'Keep this writing';
      await tester.pumpAndSettle();
      Future<void> openClose() async {
        await tester.tap(find.byKey(const ValueKey('composer-close')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('composer-confirm-save')),
          findsOneWidget,
        );
        expect(composer.isDisposed, isFalse);
      }

      await openClose();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.shell.visibleComposer, same(composer));
      await openClose();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(h.shell.visibleComposer, same(composer));
      await openClose();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(composer.isDisposed, isTrue);
      final saved = ComposerDraft.decode(
        h.api.draftsSaved.last['data'] as String,
      )!;
      expect(saved.title, 'A retained title');
      expect(saved.reply, 'Keep this writing');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone close defaults Enter to Save draft and Escape keeps writing',
    (tester) async {
      final h = await _Harness.create(
        tester,
        mobile: true,
        size: const Size(390, 844),
      );
      final composer = h.shell.visibleComposer!;
      composer.title.text = 'A phone draft';
      composer.text.text = 'Keep the phone writing';
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-close')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.shell.visibleComposer, same(composer));
      await tester.tap(find.byKey(const ValueKey('composer-close')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(composer.isDisposed, isTrue);
      expect(
        h.api.draftsSaved.last['data'],
        contains('Keep the phone writing'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed close keeps the editor and the save choice usable', (
    tester,
  ) async {
    final store = _FailingDraftStore();
    final h = await _Harness.create(
      tester,
      drafts: store,
      draftFailure: const WriteException(WriteFailure.unreachable),
    );
    final composer = h.shell.visibleComposer!;
    composer.title.text = 'Retry this draft';
    composer.text.text = 'This source must survive';
    await tester.pumpAndSettle();
    store.fail = true;
    await tester.tap(find.byKey(const ValueKey('composer-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-confirm-save')));
    await tester.pumpAndSettle();
    expect(composer.isDisposed, isFalse);
    expect(composer.text.text, 'This source must survive');
    expect(find.byKey(const ValueKey('composer-confirm-save')), findsOneWidget);
    store.fail = false;
    await tester.tap(find.byKey(const ValueKey('composer-confirm-save')));
    await tester.pumpAndSettle();
    expect(composer.isDisposed, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final (name, size, scale, mobile) in [
      ('desktop', const Size(1200, 800), 1.0, false),
      ('desktop-large', const Size(1200, 900), 2.0, false),
      ('phone', const Size(390, 844), 1.0, true),
      ('phone-large', const Size(390, 844), 2.0, true),
    ]) {
      testWidgets('composer retains state through minimize at $name dark=$dark', (
        tester,
      ) async {
        final h = await _Harness.create(
          tester,
          size: size,
          dark: dark,
          scale: scale,
          mobile: mobile,
        );
        final composer = h.shell.visibleComposer!;
        composer.title.text = 'Planning the next community gathering';
        composer.text.value = const TextEditingValue(
          text:
              'We can share a few ideas here.\n\nBring a question and something you have learned.',
          selection: TextSelection.collapsed(offset: 8),
        );
        await tester.pumpAndSettle();
        await _render(tester, '$name-${dark ? 'dark' : 'light'}-open');
        await _minimize(tester, mobile: mobile);
        await tester.pumpAndSettle();
        final card = find
            .byKey(const ValueKey('composer-restore'))
            .hitTestable();
        expect(card, findsOneWidget);
        expect(
          tester.getSize(card).width,
          lessThanOrEqualTo(mobile ? size.width : 460),
        );
        expect(tester.getSize(card).height, scale == 1 ? 52 : 85);
        expect(find.text('15 words'), findsOneWidget);
        await _render(tester, '$name-${dark ? 'dark' : 'light'}-minimized');
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(h.shell.visibleComposer, same(composer));
        expect(composer.text.selection.baseOffset, 8);
        expect(find.byType(ComposerEditor).hitTestable(), findsOneWidget);
        await tester.runAsync(composer.finishDraftSaves);
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }

  {
    for (final dark in [false, true]) {
      testWidgets('mobile sheet handle uses flat dark=$dark', (tester) async {
        await _Harness.create(
          tester,
          mobile: true,
          size: const Size(390, 844),
          theme: dark ? AppTheme.dark : AppTheme.light,
        );
        final handle = find.byKey(const ValueKey('sheet-drag-handle'));
        expect(handle.hitTestable(), findsOneWidget);
        final bounds = tester.getRect(handle);
        expect(bounds.center.dx, 195);
        for (final action in ['composer-close', 'composer-submit']) {
          expect(
            tester.getRect(find.byKey(ValueKey(action))).top,
            greaterThan(bounds.bottom),
          );
        }
        await _render(
          tester,
          'phone-sheet-handle-flat-${dark ? 'dark' : 'light'}',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  {
    testWidgets('phone close and submit use the mockup 34px action flat', (
      tester,
    ) async {
      await _Harness.create(
        tester,
        mobile: true,
        size: const Size(390, 844),
        theme: AppTheme.light,
      );
      for (final action in ['composer-close', 'composer-submit']) {
        final button = find.byKey(ValueKey(action));
        expect(tester.getSize(button), const Size(34, 34), reason: action);
        expect(
          tester
              .getSize(
                find.descendant(of: button, matching: find.byType(DIcon)),
              )
              .height,
          14,
          reason: action,
        );
      }
      await _render(tester, 'phone-header-actions-flat');
      expect(tester.takeException(), isNull);
    });
  }

  {
    testWidgets(
      'minimized new topic keeps contrast on a blue forum palette flat',
      (tester) async {
        final h = await _Harness.create(
          tester,
          theme: AppTheme.fromPalette(
            const ForumTheme(
              id: 'blue-fixture',
              name: 'Blue',
              brightness: Brightness.dark,
              primary: Color(0xFFE0E8FF),
              secondary: Color(0xFF2443A5),
              tertiary: Color(0xFF88ADFF),
              quaternary: Color(0xFF88ADFF),
              danger: Color(0xFFFF7777),
              success: Color(0xFF70DB82),
              love: Color(0xFFFC94CB),
            ).resolve(Brightness.dark),
          ),
        );
        final composer = h.shell.visibleComposer!;
        composer.text.text = 'Hello';
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('composer-minimize')));
        await tester.pumpAndSettle();
        final card = find.byKey(const ValueKey('composer-restore'));
        final title = find.descendant(
          of: card,
          matching: find.text('New topic'),
        );
        final context = tester.element(title);
        expect(
          DefaultTextStyle.of(context).style.color,
          DTokens.of(context).foreground,
        );
        expect(DefaultTextStyle.of(context).style.fontWeight, FontWeight.w600);
        expect(find.text('1 word'), findsOneWidget);
        await _render(tester, 'desktop-blue-flat-minimized');
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(h.shell.visibleComposer, same(composer));
        expect(composer.text.text, 'Hello');
        await tester.runAsync(composer.finishDraftSaves);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _minimize(WidgetTester tester, {required bool mobile}) async {
  if (mobile) {
    await tester.dragFrom(
      tester.getCenter(find.byKey(const ValueKey('sheet-drag-handle'))),
      const Offset(0, 350),
    );
  } else {
    await tester.tap(find.byKey(const ValueKey('composer-minimize')));
  }
}

Future<void> _render(WidgetTester tester, String name) async {
  final output = Platform.environment['COMPOSER_PARITY_RENDER_DIR'];
  if (output == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _FailingDraftStore extends FakeDraftStore {
  bool fail = false;
  @override
  Future<void> write(
    String site,
    String key,
    String data, {
    bool Function()? ifCurrent,
  }) async {
    if (fail) throw StateError('Device storage unavailable');
    await super.write(site, key, data, ifCurrent: ifCurrent);
  }
}

class _Harness {
  _Harness(this.shell, this.api);
  final ShellController shell;
  final FakeDiscourseApi api;
  static Future<_Harness> create(
    WidgetTester tester, {
    Size size = const Size(1000, 700),
    bool dark = false,
    ThemeData? theme,
    double scale = 1,
    bool mobile = false,
    double workspaceInset = 0,
    bool secondSite = false,
    FakeDraftStore? drafts,
    WriteException? draftFailure,
  }) async {
    const user = DiscourseUser(
      id: 7,
      username: 'writer',
      canCreateTopic: true,
      canSendPrivateMessages: true,
      whisperer: true,
    );
    final api = FakeDiscourseApi(
      user: user,
      feeds: const {'/latest.json': []},
      creatableFeedPaths: const {'/latest.json'},
      composerCapabilities: const TopicComposerCapabilities(canTagTopics: true),
      draftFailure: draftFailure,
    );
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: user),
        if (secondSite) instance('other.example').copyWith(user: user),
      ]),
      api: api,
      authenticator: FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'key'
        ..keys['https://other.example'] = 'other-key',
      drafts: drafts ?? FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    final presentation = ComposerPresentationController();
    addTearDown(shell.dispose);
    addTearDown(presentation.dispose);
    await shell.load();
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final baseTheme = theme ?? (dark ? AppTheme.dark : AppTheme.light);
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: baseTheme.copyWith(
            platform: mobile ? TargetPlatform.iOS : TargetPlatform.linux,
            textTheme:
                Platform.environment['COMPOSER_PARITY_RENDER_DIR'] == null
                ? null
                : baseTheme.textTheme.apply(fontFamily: 'Lato'),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: DToaster(child: child!),
          ),
          home: RepaintBoundary(
            key: _capture,
            child: ComposerPresentationHost(
              controller: presentation,
              child: Scaffold(
                body: Padding(
                  padding: EdgeInsets.only(left: workspaceInset),
                  child: const ComposerDock(child: SizedBox.expand()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await shell.openNewTopicFromSidebar();
    await tester.pumpAndSettle();
    return _Harness(shell, api);
  }
}
