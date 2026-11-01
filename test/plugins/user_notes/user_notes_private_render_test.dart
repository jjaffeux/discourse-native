import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_entry.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_sheet.dart';
import 'package:discourse_native/src/shell/code_block.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'user_notes_fixture.dart';

void main() {
  testWidgets(
    'phone notes open expanded without headings and the first note visible',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 932);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = NotesFixture();
      addTearDown(() => tester.runAsync(f.dispose));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: DTouchTargets(
              child: Center(
                child: UserNotesEntry(
                  controller: f.controller,
                  siteUrl: notesSite,
                  userId: 7,
                  count: 1,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(f.cooker.start);
      await tester.tap(find.byTooltip('User notes (1)'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 350)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DDialogTitle), findsNothing);
      expect(find.text('User notes (1)'), findsNothing);
      expect(find.text('system').hitTestable(), findsOneWidget);
      expect(find.text('Only staff can see these notes.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'real note cooking and account retirement never retain fenced code globally',
    (tester) async {
      clearSyntaxHighlightCacheForTesting();
      addTearDown(clearSyntaxHighlightCacheForTesting);
      final f = NotesFixture();
      addTearDown(() => tester.runAsync(f.dispose));
      const source = 'def secret_note\n  puts "private evidence"\nend';
      f.transport.responders['GET /user_notes.json?user_id=7'] = (_) => notesPage([
        noteWire(raw: 'Staff **context**\n\n```ruby\n$source\n```'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: UserNotesEntry(
                controller: f.controller,
                siteUrl: notesSite,
                userId: 7,
                count: 1,
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(f.cooker.start);
      await tester.tap(find.byTooltip('User notes (1)'));
      await tester.pump(const Duration(milliseconds: 250));
      for (
        var i = 0;
        i < 100 && find.byType(CodeBlock).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.byType(UserNotesPanel), findsOneWidget);
      expect(find.byType(CodeBlock), findsOneWidget);
      expect(
        tester.widget<CodeBlock>(find.byType(CodeBlock)).data.text,
        source,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(highlightNeedsParse(source, 'ruby'), isTrue);
      expect(find.byTooltip('View code full screen'), findsNothing);
      expect(f.transientCooking, 1);
      f.requests.forget(notesSite);
      await tester.pumpAndSettle();
      expect(find.byType(UserNotesPanel), findsNothing);
      expect(find.byType(CodeBlockFullscreen), findsNothing);
      expect(highlightNeedsParse(source, 'ruby'), isTrue);
    },
  );
}
