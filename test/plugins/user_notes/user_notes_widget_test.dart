import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_data.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_entry.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'user_notes_fixture.dart';

Future<void> _mount(
  WidgetTester tester,
  NotesFixture fixture, {
  bool mobile = false,
  int count = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = mobile
      ? const Size(430, 932)
      : const Size(1000, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light.copyWith(
        platform: mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
      ),
      home: Scaffold(
        body: DTouchTargets(
          child: DTouchFields(
            child: Center(
              child: UserNotesEntry(
                controller: fixture.controller,
                siteUrl: notesSite,
                userId: 7,
                username: 'mira',
                count: count,
                postId: 11,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(fixture.cooker.start);
}

Future<void> _settleCooking(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 350)),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      '${mobile ? 'phone' : 'desktop'} real identity entry opens notes, preserves failed draft, and saves',
      (tester) async {
        final f = NotesFixture();
        addTearDown(() => tester.runAsync(f.dispose));
        await _mount(tester, f, mobile: mobile);
        await tester.tap(find.byTooltip('User notes (1)'));
        await tester.pump(const Duration(milliseconds: 250));
        await _settleCooking(tester);
        expect(find.byType(UserNotesPanel), findsOneWidget);
        expect(find.text('Only staff can see these notes.'), findsOneWidget);
        expect(find.text('system'), findsOneWidget);
        expect(f.regularCooking, 0);
        expect(f.transientCooking, 1);
        await tester.enterText(find.byType(DTextarea), 'Keep my draft');
        await tester.pump();
        f.transport.responders.remove('POST /user_notes');
        f.transport.failures['POST /user_notes'] = const WriteException(
          WriteFailure.validation,
          errors: ['Rejected by the server'],
        );
        await tester.ensureVisible(
          find.widgetWithText(DButton, 'Add user note'),
        );
        await tester.tap(find.widgetWithText(DButton, 'Add user note'));
        await tester.pumpAndSettle();
        expect(find.text('Rejected by the server'), findsOneWidget);
        expect(find.text('Keep my draft'), findsOneWidget);
        f.transport.responses['POST /user_notes'] = {
          'user_note': noteWire(id: 'new', raw: 'Keep my draft'),
        };
        await tester.tap(find.widgetWithText(DButton, 'Add user note'));
        await tester.pump(const Duration(milliseconds: 250));
        await _settleCooking(tester);
        expect(find.text('User notes (2)'), findsOneWidget);
        expect(
          tester.widget<DTextarea>(find.byType(DTextarea)).controller!.text,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'identity icon hides at zero and disabling closes private overlay and clears draft',
    (tester) async {
      final f = NotesFixture();
      addTearDown(() => tester.runAsync(f.dispose));
      await _mount(tester, f, count: 0);
      expect(find.byType(DButton), findsNothing);
      await _mount(tester, f, count: 1);
      await tester.tap(find.byTooltip('User notes (1)'));
      await tester.pump(const Duration(milliseconds: 250));
      await _settleCooking(tester);
      await tester.enterText(find.byType(DTextarea), 'Sensitive unsaved text');
      f.settings(enabled: false);
      await tester.pumpAndSettle();
      expect(find.byType(UserNotesPanel), findsNothing);
      expect(find.text('Sensitive unsaved text'), findsNothing);
      expect(find.byType(UserNotesEntry), findsOneWidget);
      expect(find.byType(DButton), findsNothing);
    },
  );
  testWidgets(
    'full long raw text survives cooker limit and renders in scrollable notes',
    (tester) async {
      final f = NotesFixture(failCooking: true);
      addTearDown(() => tester.runAsync(f.dispose));
      final raw = '${'a' * 66000} END OF PRIVATE NOTE';
      f.transport.responders['GET /user_notes?user_id=7'] = (_) =>
          notesPage([noteWire(raw: raw)]);
      await _mount(tester, f);
      await tester.tap(find.byTooltip('User notes (1)'));
      await tester.pump(const Duration(milliseconds: 250));
      await _settleCooking(tester);
      expect(find.text('Shown as unformatted text'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is DText && widget.data == raw,
        ),
        findsOneWidget,
      );
      expect(f.transientCooking, 0);
      expect(find.textContaining('truncated'), findsNothing);
      expect(find.byType(Scrollable), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'removal requires confirmation and honors the returned note permission',
    (tester) async {
      final f = NotesFixture();
      addTearDown(() => tester.runAsync(f.dispose));
      await _mount(tester, f);
      await tester.tap(find.byTooltip('User notes (1)'));
      await tester.pump(const Duration(milliseconds: 250));
      await _settleCooking(tester);
      await _settleCooking(tester);
      await tester.ensureVisible(find.byTooltip('Remove user note'));
      await tester.tap(find.byTooltip('Remove user note'));
      await tester.pumpAndSettle();
      expect(f.transport.writes, isEmpty);
      await tester.tap(find.widgetWithText(DButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(f.transport.writes, isEmpty);
      await tester.tap(find.byTooltip('Remove user note'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(DButton, 'Remove user note'));
      await tester.pumpAndSettle();
      expect(f.transport.writes.single.method, 'DELETE');
      expect(find.text('No user notes yet'), findsOneWidget);
    },
  );
  testWidgets('placement responds to settings without losing its controller', (
    tester,
  ) async {
    final f = NotesFixture();
    addTearDown(() => tester.runAsync(f.dispose));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Column(
            children: [
              UserNotesEntry(
                controller: f.controller,
                siteUrl: notesSite,
                userId: 7,
                count: 1,
                placement: PostAuthorDecorationPlacement.beforeName,
              ),
              UserNotesEntry(
                controller: f.controller,
                siteUrl: notesSite,
                userId: 7,
                count: 1,
                placement: PostAuthorDecorationPlacement.afterAvatar,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DButton), findsOneWidget);
    final before = tester.getTopLeft(find.byType(DButton)).dy;
    f.settings(enabled: true, placement: UserNotesPlacement.avatar);
    await tester.pumpAndSettle();
    expect(find.byType(DButton), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(DButton)).dy,
      greaterThanOrEqualTo(before),
    );
  });
}
