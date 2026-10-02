import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/data/scalar_preference_repository.dart';
import 'package:discourse_native/src/shell/forum_theme_editor.dart';
import 'package:discourse_native/src/shell/forum_theme_thumbnail.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/theme_settings.dart';

const _site = 'https://a.example';
final _name = find.byKey(const ValueKey('theme-name'));
final _save = find.byKey(const ValueKey('theme-save'));
final _thumbnail = find.byKey(const ValueKey('theme-editor-thumbnail'));

void main() {
  testWidgets('a completed save keeps a replacement theme editor and preview', (
    tester,
  ) async {
    final (shell, persistence) = await _startSave(tester);
    expect(
      tester
          .widget<DButton>(find.byKey(const ValueKey('all-themes')))
          .onPressed,
      isNotNull,
    );
    await _tap(tester, find.byKey(const ValueKey('all-themes')));
    await _tap(tester, find.byKey(const ValueKey('new-theme')));
    await tester.enterText(_name, 'Replacement draft');
    await _changeBackground(tester);

    persistence.release();
    await tester.pumpAndSettle();
    expect(find.byType(ForumThemeEditor), findsOneWidget);
    expect(tester.widget<DInput>(_name).controller!.text, 'Replacement draft');
    expect(
      tester.widget<ThemeThumbnail>(_thumbnail).theme.shell.content,
      const Color(0xff112233),
    );
    final saved = await shell.forumSettings.store.loadThemes(_site);
    expect(saved.customThemes.single.name, 'Original saved theme');
    expect(saved.customThemes.single.secondary, isNot(const Color(0xff112233)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a completed save keeps newer edits in its original editor', (
    tester,
  ) async {
    final (shell, persistence) = await _startSave(tester);
    await _changeBackground(tester);
    persistence.release();
    await tester.pumpAndSettle();
    expect(find.byType(ForumThemeEditor), findsOneWidget);
    expect(
      tester.widget<ThemeThumbnail>(_thumbnail).theme.shell.content,
      const Color(0xff112233),
    );
    final saved = await shell.forumSettings.store.loadThemes(_site);
    expect(saved.customThemes.single.secondary, isNot(const Color(0xff112233)));

    // The original save persists, and the subsequent draft remains savable.
    await _tap(tester, _save);
    expect(find.byType(ForumThemeEditor), findsNothing);
    final updated = await shell.forumSettings.store.loadThemes(_site);
    expect(updated.customThemes.single.secondary, const Color(0xff112233));
    expect(tester.takeException(), isNull);
  });
}

Future<(ShellController, _HeldPersistence)> _startSave(
  WidgetTester tester,
) async {
  final persistence = _HeldPersistence();
  final shell = controller(
    forumSettingsStore: ForumSettingsStore(persistence: persistence),
  );
  addTearDown(shell.dispose);
  addTearDown(persistence.release);
  await pumpSettings(tester, shell);
  await _tap(tester, find.byKey(const ValueKey('new-theme')));
  await tester.enterText(_name, 'Original saved theme');
  await tester.pumpAndSettle();
  persistence.holdWrites = true;
  await tester.ensureVisible(_save);
  await tester.tap(_save);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  expect(persistence.started.isCompleted, isTrue);
  expect(find.byType(ForumThemeEditor), findsOneWidget);
  return (shell, persistence);
}

Future<void> _changeBackground(WidgetTester tester) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(const ValueKey('theme-color-background')),
      matching: find.byType(EditableText),
    ),
    '#112233',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  expect(
    tester.widget<ThemeThumbnail>(_thumbnail).theme.shell.content,
    const Color(0xff112233),
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _HeldPersistence implements ScalarPreferencePersistence<String> {
  final values = <String, String>{};
  final started = Completer<void>();
  final _gate = Completer<void>();
  bool holdWrites = false;

  void release() {
    holdWrites = false;
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<bool> write(String key, String value) async {
    if (holdWrites) {
      if (!started.isCompleted) started.complete();
      await _gate.future;
    }
    values[key] = value;
    return true;
  }
}
