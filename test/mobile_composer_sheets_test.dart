import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_composer.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_composer_parser.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/gifs/gif.dart';
import 'package:discourse_native/src/plugins/gifs/gif_picker.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_settings.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_editor.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_parser.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_sheet.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_editor.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_parser.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_composer_editor_host.dart';
import 'support/fakes.dart';

const _gif = GifResult(
  title: 'Cat dance',
  url: 'https://media.example.com/cat.webp',
  width: 240,
  height: 180,
);

const _eventSource = '[event start="2026-09-30 12:00" name="Lunch"][/event]';
const _pollSource = '[poll]\n* A\n* B\n[/poll]';
const _dateSource = '[date=2026-09-30 timezone=Etc/UTC]';

void main() {
  setUpAll(() {
    LocalDateEnvironment.instance.ensureDatabase();
    LocalDateEnvironment.instance.setDeviceTimezone('Etc/UTC');
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final picker in ['event', 'poll', 'date']) {
      testWidgets(
        '$picker retains fixed edit actions with keyboard on $platform',
        (tester) async {
          tester.view.physicalSize = const Size(320, 700);
          tester.view.devicePixelRatio = 1;
          tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
          addTearDown(tester.view.reset);
          final editor = FakeComposerEditorHost(
            TextEditingValue(text: picker == 'event' ? _eventSource : ''),
          );
          Object? result;
          var completed = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark.copyWith(platform: platform),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => DButton(
                    label: const Text('Open'),
                    onPressed: () async {
                      result = await _openPicker(
                        context,
                        picker,
                        editor,
                        editing: true,
                      );
                      completed = true;
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          final apply = find.widgetWithText(DButton, 'Apply');
          final remove = find.widgetWithText(
            DButton,
            picker == 'event' ? 'Remove event' : 'Remove',
          );
          final footer = find.byType(DSheetFooter);
          expect(find.widgetWithText(DButton, 'Cancel'), findsNothing);
          expect(apply.hitTestable(), findsOneWidget);
          expect(remove.hitTestable(), findsOneWidget);
          expect(tester.getRect(apply).width, tester.getRect(remove).width);
          expect(
            tester.getRect(apply).bottom,
            lessThan(tester.getRect(remove).top),
          );
          expect(tester.getRect(footer).bottom, lessThanOrEqualTo(666));
          final footerBounds = tester.getRect(footer);
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -300),
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(footer), footerBounds);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          tester.view.padding = const FakeViewPadding(top: 24);
          await tester.pumpAndSettle();
          expect(apply.hitTestable(), findsOneWidget);
          expect(remove.hitTestable(), findsOneWidget);
          expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
          expect(tester.getRect(footer).bottom, lessThanOrEqualTo(420));
          expect(tester.takeException(), isNull);
          await tester.tap(remove);
          await tester.pumpAndSettle();
          expect(find.byType(DSheetContent), findsNothing);
          expect(completed, isTrue);
          switch (picker) {
            case 'date':
              expect(
                (result as LocalDateComposerSheetAction).type,
                LocalDateComposerSheetActionType.remove,
              );
            case 'poll':
              expect(
                (result as PollComposerSheetAction).type,
                PollComposerSheetActionType.remove,
              );
            case 'event':
              expect(editor.value.text, isEmpty);
              expect(editor.commitTextCalls, 1);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
    for (final picker in ['event', 'poll', 'date', 'gif']) {
      testWidgets('$picker uses the mobile picker sheet on $platform', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final editor = FakeComposerEditorHost(TextEditingValue.empty);
        var completions = 0;
        Object? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            home: Scaffold(
              body: Builder(
                builder: (context) => DButton(
                  label: const Text('Open'),
                  onPressed: () async {
                    result = await _openPicker(context, picker, editor);
                    completions++;
                  },
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final sheet = find.byType(DSheetContent);
        expect(sheet, findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
        final bounds = tester.getRect(sheet);
        expect(bounds.left, greaterThan(0));
        expect(bounds.right, lessThan(320));
        expect(bounds.height, greaterThan(550));

        if (picker != 'gif') {
          final apply = find.widgetWithText(DButton, 'Apply');
          final header = find.byType(DSheetHeader);
          final footer = find.byType(DSheetFooter);
          expect(find.widgetWithText(DButton, 'Cancel'), findsNothing);
          expect(apply.hitTestable(), findsOneWidget);
          expect(tester.getSize(apply).width, closeTo(bounds.width - 32, .01));
          final headerBounds = tester.getRect(header);
          final footerBounds = tester.getRect(footer);
          final scroll = find
              .descendant(
                of: sheet,
                matching: find.byType(SingleChildScrollView),
              )
              .first;
          await tester.drag(scroll, const Offset(0, -250));
          await tester.pumpAndSettle();
          expect(tester.getRect(header), headerBounds);
          expect(tester.getRect(footer), footerBounds);
          expect(apply.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(find.byType(DSheetTitle)).right,
            lessThan(tester.getRect(find.byTooltip('Close')).left),
          );
        }

        await tester.drag(find.byType(DSheetTitle), const Offset(0, 400));
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(completions, 1);
        expect(result, isNull);
        expect(editor.value.text, isEmpty);

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        expect(sheet, findsOneWidget);
        expect(tester.getRect(sheet).bottom, lessThanOrEqualTo(420));
        expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
        if (picker != 'gif') {
          final apply = find.widgetWithText(DButton, 'Apply');
          expect(apply.hitTestable(), findsOneWidget);
          expect(tester.getRect(apply).bottom, lessThanOrEqualTo(420));
          if (picker == 'date') {
            await tester.enterText(
              find.byType(DInputGroupInput).first,
              'invalid',
            );
            await tester.tap(apply);
            await tester.pumpAndSettle();
            final error = find.byKey(const ValueKey('local-date-sheet-error'));
            expect(error.hitTestable(), findsOneWidget);
            expect(
              find.descendant(of: find.byType(DSheetFooter), matching: error),
              findsOneWidget,
            );
            expect(apply.hitTestable(), findsOneWidget);
          }
        }
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(completions, 2);
        expect(result, isNull);
        expect(editor.value.text, isEmpty);
        expect(tester.takeException(), isNull);

        if (picker == 'event') return;
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        if (picker == 'gif') {
          await tester.enterText(
            find.byKey(const ValueKey('gif-picker-search')),
            'cats',
          );
          await tester.pump(const Duration(milliseconds: 700));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('gif-result-0')));
        } else {
          if (picker == 'poll') {
            for (final (label, value) in [
              ('Option 1', 'A'),
              ('Option 2', 'B'),
            ]) {
              final field = find.byWidgetPredicate(
                (widget) => widget is DInput && widget.labelText == label,
              );
              await tester.ensureVisible(field);
              await tester.enterText(field, value);
            }
          }
          final apply = find.widgetWithText(DButton, 'Apply');
          await tester.pumpAndSettle();
          await tester.ensureVisible(apply);
          await tester.pumpAndSettle();
          expect(apply.hitTestable(), findsOneWidget);
          await tester.tap(apply);
        }
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(completions, 3);
        switch (picker) {
          case 'poll':
            expect((result as PollComposerSheetAction).draft!.options, [
              'A',
              'B',
            ]);
          case 'date':
            expect(
              (result as LocalDateComposerSheetAction).draft!.startDate,
              '2026-09-30',
            );
          case 'gif':
            expect(result, _gif);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Future<Object?> _openPicker(
  BuildContext context,
  String picker,
  FakeComposerEditorHost editor, {
  bool editing = false,
}) async {
  switch (picker) {
    case 'event':
      final state = ComposerPluginState(
        createsTopic: true,
        siteSettings: PluginData.none.withValue(
          eventSettingsKey,
          const EventSettings(enabled: true),
        ),
        freshCurrentUser: PluginData.none.withValue(
          eventUserKey,
          const EventUserPermissions(true),
        ),
      );
      await openEventComposer(
        context,
        editor,
        EventSyntaxPolicy(
          ComposerSyntaxPolicyContext(
            siteUrl: editor.siteUrl,
            isPluginTarget: false,
            isEdit: false,
            initialState: state,
            readState: () => state,
          ),
        ),
        block: editing ? parseEventBlocks(editor.value.text).single : null,
      );
      return null;
    case 'poll':
      return showPollComposerSheet(
        context: context,
        draft: editing
            ? PollComposerDraft.fromBlock(
                parsePollComposerBlocks(_pollSource).single,
              )
            : PollComposerDraft.newPoll(name: 'poll', defaultPublic: false),
        maximumOptions: 20,
        isStaff: false,
        isPublished: false,
      );
    case 'date':
      return showLocalDateComposerSheet(
        context: context,
        draft: editing
            ? LocalDateComposerDraft.fromBlock(
                parseLocalDateComposerBlocks(
                  _dateSource,
                  environment: LocalDateEnvironment.instance,
                ).single,
              )
            : LocalDateComposerDraft.newDate(
                now: DateTime(2026, 9, 30),
                timezone: 'Etc/UTC',
                environment: LocalDateEnvironment.instance,
              ),
        siteFormats: const [],
      );
    case 'gif':
      return showGifPicker(
        context: context,
        siteUrl: editor.siteUrl,
        api: FakeDiscourseApi(
          gifSearchPages: {
            FakeDiscourseApi.gifSearchKey('cats'): GifSearchPage(
              results: const [_gif],
            ),
          },
        ),
        requests: FakePluginRequestHost(
          credentials: FakeAuthenticator()..keys[editor.siteUrl] = 'api-key',
          lifecycle: SiteLifecycle(),
        ),
        settings: const GifsSettings(enabled: true),
      );
    default:
      throw ArgumentError.value(picker, 'picker');
  }
}
