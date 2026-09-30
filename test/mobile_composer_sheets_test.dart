import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_composer.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/gifs/gif.dart';
import 'package:discourse_native/src/plugins/gifs/gif_picker.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_settings.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_editor.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_sheet.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/poll/poll_composer_editor.dart';
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

void main() {
  setUpAll(() {
    LocalDateEnvironment.instance.ensureDatabase();
    LocalDateEnvironment.instance.setDeviceTimezone('Etc/UTC');
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
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
          await tester.ensureVisible(apply);
          await tester.pumpAndSettle();
          expect(apply.hitTestable(), findsOneWidget);
          expect(tester.getRect(apply).bottom, lessThanOrEqualTo(420));
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
  FakeComposerEditorHost editor,
) async {
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
      );
      return null;
    case 'poll':
      return showPollComposerSheet(
        context: context,
        draft: PollComposerDraft.newPoll(name: 'poll', defaultPublic: false),
        maximumOptions: 20,
        isStaff: false,
        isPublished: false,
      );
    case 'date':
      return showLocalDateComposerSheet(
        context: context,
        draft: LocalDateComposerDraft.newDate(
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
