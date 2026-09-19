import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_settings_dialog.dart';
import 'package:discourse_native/src/shell/forum_theme_editor.dart';
import 'package:discourse_native/src/shell/forum_theme_preview.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Finder input(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(EditableText),
);

void main() {
  testWidgets(
    'invalid colors disable saving and valid edits emit a portable theme',
    (tester) async {
      ForumTheme? draft;
      ForumTheme? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: SingleChildScrollView(
            child: DCard(
              child: ForumThemeEditor(
                initialTheme: forumThemePresets[9],
                customThemes: const [],
                onChanged: (value) => draft = value,
                onSave: (value) async => saved = value,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(input('custom-theme-tertiary'), '#broken');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DButton>(find.byKey(const ValueKey('save-custom-theme')))
            .onPressed,
        isNull,
      );
      expect(draft, isNull);
      await tester.enterText(input('custom-theme-tertiary'), '#39845B');
      await tester.enterText(input('custom-theme-name'), 'Forest');
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('save-custom-theme')),
      );
      await tester.tap(find.byKey(const ValueKey('save-custom-theme')));
      expect(saved?.name, 'Forest');
      expect(saved?.tertiary, const Color(0xff39845b));
      expect(saved?.id, startsWith('custom-'));
      expect(ForumTheme.fromJson(saved!.toJson(), id: saved!.id), saved);
    },
  );

  testWidgets('imports validated JSON into the editor without applying it', (
    tester,
  ) async {
    ForumTheme? draft;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SingleChildScrollView(
          child: DCard(
            child: ForumThemeEditor(
              initialTheme: forumThemePresets[1],
              customThemes: const [],
              onChanged: (value) => draft = value,
              onSave: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Import'));
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    await tester.enterText(input('import-theme-json'), '{invalid');
    await tester.tap(find.byKey(const ValueKey('confirm-import-theme')));
    await tester.pumpAndSettle();
    expect(find.text('Paste a valid exported theme.'), findsOneWidget);
    expect(draft, isNull);
    final payload = {
      ...forumThemePresets[9].toJson(),
      'name': 'Imported night',
    };
    await tester.enterText(input('import-theme-json'), jsonEncode(payload));
    await tester.tap(find.byKey(const ValueKey('confirm-import-theme')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('import-theme-json')), findsNothing);
    expect(draft?.name, 'Imported night');
    expect(draft?.tertiary, forumThemePresets[9].tertiary);
    expect(draft?.id, startsWith('custom-'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar, presets, and custom preview use real components', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => DButton(
              label: const Text('Open'),
              onPressed: () => showForumSettingsDialog(
                context,
                siteUrl: 'https://a.example',
                name: 'A forum',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(DSidebar), findsOneWidget);
    expect(find.byType(ForumThemePreview), findsOneWidget);
    expect(find.byType(TopicListRow), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('forum-settings-general')));
    await tester.pumpAndSettle();
    expect(find.text('Address'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('forum-settings-appearance')));
    await tester.pumpAndSettle();
    final dracula = find.byKey(const ValueKey('forum-theme-dracula'));
    await tester.ensureVisible(dracula);
    await tester.tap(dracula);
    await tester.pumpAndSettle();
    expect(
      controller.forumSettings.themesFor('https://a.example').selectedId,
      'dracula',
    );
    final preview = find.byKey(const ValueKey('forum-theme-preview'));
    expect(
      Theme.of(tester.element(preview)).colorScheme.primary,
      const Color(0xffbd93f9),
    );
    await tester.ensureVisible(find.text('Custom'));
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(input('custom-theme-tertiary'));
    await tester.enterText(input('custom-theme-tertiary'), '#39845B');
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(preview)).colorScheme.primary,
      const Color(0xff39845b),
    );
    expect(
      controller.forumSettings
          .themesFor('https://a.example')
          .selectedTheme
          ?.tertiary,
      const Color(0xffbd93f9),
    );
    await tester.enterText(input('custom-theme-tertiary'), '#39');
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(input('custom-theme-tertiary'))
          .controller
          .text,
      '#39',
    );
    expect(
      Theme.of(tester.element(preview)).colorScheme.primary,
      const Color(0xff39845b),
    );
    expect(tester.takeException(), isNull);
    await tester.enterText(input('custom-theme-tertiary'), '#39845B');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('save-custom-theme')));
    await tester.tap(find.byKey(const ValueKey('save-custom-theme')));
    await tester.pumpAndSettle();
    expect(
      controller.forumSettings.themesFor('https://a.example').selectedId,
      startsWith('custom-'),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('forum-default-theme')),
    );
    await tester.tap(find.byKey(const ValueKey('forum-default-theme')));
    await tester.pumpAndSettle();
    expect(
      controller.forumSettings.themesFor('https://a.example').selectedId,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
