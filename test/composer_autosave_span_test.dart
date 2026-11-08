import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      '${mobile ? 'mobile' : 'desktop'} autosave retains the mounted editor span',
      (tester) async {
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        const user = DiscourseUser(
          id: 7,
          username: 'sam',
          canCreateTopic: true,
        );
        final api = FakeDiscourseApi(
          user: user,
          feeds: const {'/latest.json': []},
          creatableFeedPaths: const {'/latest.json'},
          draftGate: gate,
        );
        final shell = ShellController(
          mobileNavigationEnabled: mobile,
          forumTabsEnabled: false,
          instanceStore: FakeInstanceStore([
            instance('meta.discourse.org').copyWith(user: user),
          ]),
          api: api,
          authenticator: FakeAuthenticator()
            ..keys['https://meta.discourse.org'] = 'key',
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
        );
        addTearDown(shell.dispose);
        await shell.load();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = mobile
            ? const Size(390, 844)
            : const Size(1280, 850);
        tester.view.viewInsets = FakeViewPadding(bottom: mobile ? 336 : 0);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
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
        await shell.openNewTopicFromSidebar();
        await tester.pumpAndSettle();
        final composer = shell.visibleComposer!;
        final source = List.generate(
          120,
          (i) =>
              'Paragraph $i with **emphasis** and enough text to wrap across '
              'the composer viewport while scrolling a long topic draft.',
        ).join('\n\n');
        const selection = TextSelection.collapsed(offset: 0);
        composer.title.text = 'A long topic';
        composer.text.value = TextEditingValue(
          text: source,
          selection: selection,
        );
        composer.focus.requestFocus();
        await tester.pumpAndSettle();
        expect(api.draftsSaved, isEmpty);

        final field = find.byWidgetPredicate(
          (widget) =>
              widget is EditableText &&
              identical(widget.controller, composer.text),
        );
        expect(field, findsOneWidget);
        final originalState = tester.state<EditableTextState>(field);
        final originalRender = originalState.renderEditable;
        final originalSpan = originalRender.text;
        final originalTheme = Theme.of(originalState.context);
        final originalSize = originalRender.size;
        final originalStrut = originalState.widget.strutStyle;

        void expectRetained(String status) {
          final state = tester.state<EditableTextState>(field);
          final render = state.renderEditable;
          final theme = Theme.of(state.context);
          expect(shell.visibleComposer, same(composer), reason: status);
          expect(state, same(originalState), reason: status);
          expect(render, same(originalRender), reason: status);
          expect(theme, originalTheme, reason: status);
          expect(render.size, originalSize, reason: status);
          expect(state.widget.strutStyle, originalStrut, reason: status);
          expect(render.text, same(originalSpan), reason: status);
          expect(composer.text.text, source, reason: status);
          expect(composer.text.selection, selection, reason: status);
        }

        final saving = composer.flushDraft();
        for (var attempt = 0;
            attempt < 20 && api.draftsSaved.isEmpty;
            attempt++) {
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(api.draftsSaved, hasLength(1));
        expect(composer.draftStatus, DraftStatus.saving);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();
        expectRetained('saving');

        gate.complete();
        await tester.pumpAndSettle();
        await saving;
        expect(composer.draftStatus, DraftStatus.saved);
        expect(api.draftsSaved, hasLength(1));
        expectRetained('saved');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: TargetPlatformVariant.only(
        mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
      ),
    );
  }
}
