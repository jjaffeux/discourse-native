import 'dart:async';

import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/post_flag_editor.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _siteUrl = 'https://meta.discourse.org';
const _post = Post(
  id: 42,
  postNumber: 2,
  username: 'sam',
  cooked: '<p>Hello</p>',
);
const _offTopic = PostFlagType(
  id: 3,
  nameKey: 'off_topic',
  name: 'Off-Topic',
  description: '<p>This is not relevant to the discussion.</p>',
  shortDescription: '<p>Not relevant.</p>',
  appliesTo: ['Post'],
);
const _notifyUser = PostFlagType(
  id: 7,
  nameKey: 'notify_user',
  name: 'Send @%{username} a message',
  description: '<p>Help the author improve this post.</p>',
  requireMessage: true,
  appliesTo: ['Post'],
);
const _illegal = PostFlagType(
  id: 8,
  nameKey: 'illegal',
  name: 'Illegal',
  description: '<p>This may break the law.</p>',
  requireMessage: true,
  appliesTo: ['Post'],
);

Future<void> _pumpEditor(
  WidgetTester tester, {
  required List<PostFlagType> types,
  required PostFlagSaver save,
  required VoidCallback onComplete,
  TargetPlatform platform = TargetPlatform.macOS,
  int minimum = 10,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light.copyWith(platform: platform),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: PostFlagEditor(
          siteUrl: _siteUrl,
          post: _post,
          flagTypes: types,
          minimumMessageLength: minimum,
          save: save,
          onComplete: onComplete,
        ),
      ),
    ),
  ),
);

FilledButton _submit(WidgetTester tester) => tester.widget<FilledButton>(
  find.descendant(
    of: find.byKey(const ValueKey('post-flag-submit')),
    matching: find.byType(FilledButton),
  ),
);

void main() {
  testWidgets('a sole reason is preselected and can be submitted', (
    tester,
  ) async {
    PostFlagType? saved;
    var completed = 0;
    await _pumpEditor(
      tester,
      types: const [_offTopic],
      save: (type, {message}) async {
        saved = type;
        return null;
      },
      onComplete: () => completed++,
    );
    await tester.pumpAndSettle();

    expect(find.text('Flag Post'), findsOneWidget);
    expect(_submit(tester).onPressed, isNotNull);
    final reasonSemantics = tester.getSemantics(
      find.byKey(const ValueKey('post-flag-reason-3')),
    );
    expect(
      reasonSemantics,
      matchesSemantics(
        isChecked: true,
        hasCheckedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(reasonSemantics.label, contains('Off-Topic'));
    expect(reasonSemantics.label, contains('not relevant'));

    await tester.tap(find.byKey(const ValueKey('post-flag-submit')));
    await tester.pump();
    expect(saved, _offTopic);
    expect(completed, 1);
  });

  testWidgets(
    'notify-user substitutes the author and enforces message bounds',
    (tester) async {
      final saved = <({PostFlagType type, String? message})>[];
      var completed = 0;
      await _pumpEditor(
        tester,
        types: const [_offTopic, _notifyUser],
        save: (type, {message}) async {
          saved.add((type: type, message: message));
          return null;
        },
        onComplete: () => completed++,
      );
      await tester.pumpAndSettle();

      expect(find.text('Send @sam a message'), findsOneWidget);
      await tester.tap(find.text('Send @sam a message'));
      await tester.pump();
      expect(find.text('Message'), findsOneWidget);
      expect(_submit(tester).onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('post-flag-message')),
        '123456789',
      );
      await tester.pump();
      expect(find.textContaining('1 more required'), findsOneWidget);
      expect(_submit(tester).onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('post-flag-message')),
        'A useful explanation',
      );
      await tester.pump();
      expect(_submit(tester).onPressed, isNotNull);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(saved.single.type, _notifyUser);
      expect(saved.single.message, 'A useful explanation');
      expect(completed, 1);
    },
  );

  testWidgets('illegal reports also require the accuracy confirmation', (
    tester,
  ) async {
    var saves = 0;
    await _pumpEditor(
      tester,
      types: const [_illegal],
      save: (type, {message}) async {
        saves++;
        return null;
      },
      onComplete: () {},
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('post-flag-message')),
      'Complete legal explanation',
    );
    await tester.pump();
    expect(_submit(tester).onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('post-flag-illegal-confirmation')),
    );
    await tester.pump();
    expect(_submit(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('post-flag-submit')));
    await tester.pump();
    expect(saves, 1);
  });

  testWidgets('a refusal keeps every field and announces the inline error', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      types: const [_notifyUser, _illegal],
      save: (type, {message}) async => 'The server refused this flag.',
      onComplete: () => fail('A refused flag must not close the editor'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send @sam a message'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('post-flag-message')),
      'Please revise this wording.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('post-flag-submit')));
    await tester.pumpAndSettle();

    expect(find.text('The server refused this flag.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('post-flag-message')))
          .controller
          ?.text,
      'Please revise this wording.',
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('post-flag-error'))),
      matchesSemantics(
        label: 'The server refused this flag.',
        isLiveRegion: true,
      ),
    );
    expect(_submit(tester).onPressed, isNotNull);
  });

  testWidgets('saving locks choices and repeated submission', (tester) async {
    final gate = Completer<String?>();
    var saves = 0;
    await _pumpEditor(
      tester,
      types: const [_offTopic],
      save: (type, {message}) {
        saves++;
        return gate.future;
      },
      onComplete: () {},
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('post-flag-submit')));
    await tester.pump();
    expect(_submit(tester).onPressed, isNull);
    expect(
      tester
          .widget<Radio<PostFlagType>>(find.byType(Radio<PostFlagType>))
          .enabled,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('post-flag-submit')));
    expect(saves, 1);

    gate.complete('Try again.');
    await tester.pumpAndSettle();
    expect(find.text('Try again.'), findsOneWidget);
  });

  testWidgets('touch presentation uses the server short description', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      types: const [_offTopic],
      save: (type, {message}) async => null,
      onComplete: () {},
      platform: TargetPlatform.android,
    );
    await tester.pumpAndSettle();

    final description = tester.widget<CookedHtml>(find.byType(CookedHtml));
    expect(description.html, '<p>Not relevant.</p>');
  });
}
