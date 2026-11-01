import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/models/composer_upload.dart'
    show ComposerUploadFile;
import 'package:discourse_native/src/plugins/policy/policy_builder.dart';
import 'package:discourse_native/src/plugins/policy/policy_composer.dart';
import 'package:discourse_native/src/plugins/policy/policy_data.dart';
import 'package:discourse_native/src/plugins/policy/policy_definition.dart';
import 'package:discourse_native/src/plugins/policy/policy_groups.dart';
import 'package:discourse_native/src/plugins/policy/policy_preferences.dart';
import 'package:discourse_native/src/shell/composer/controller.dart'
    show ReplyComposerTarget;
import 'package:discourse_native/src/shell/composer/panel.dart'
    show ComposerRichBodyEditor;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('email preference owns its payload and preserves partial updates', () {
    const codec = PolicyEmailCodec();
    final away = codec.decode({
      'user_option': {'policy_email_frequency': 'when_away'},
    }, null);
    expect(away.payload, {'policy_email_frequency': 'when_away'});
    expect(
      codec.decode({
        'user_option': {'timezone': 'UTC'},
      }, away),
      away,
    );
    expect(
      codec.decode({
        'user_option': {'policy_email_frequency': 'new-option'},
      }, null).payload,
      {'policy_email_frequency': 'never'},
    );
  });

  testWidgets('builder requires groups and preserves every configured field', (
    tester,
  ) async {
    PolicyDefinition? saved;
    final initial = PolicyDefinition(
      audienceGroups: const ['crew'],
      version: 'v2',
      renewal: const PolicyRenewByCalendar(PolicyCalendarInterval.quarterly),
      reminder: PolicyReminder.weekly,
      renewStartDate: '2026-11-01',
      acceptLabel: 'I agree',
      revokeLabel: 'Withdraw',
      targetGroup: 'qualified',
      privateStatistics: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => Scaffold(body: child),
        home: SizedBox(
          width: 500,
          height: 800,
          child: PolicyBuilder(
            initial: initial,
            loadGroups: () async => const [
              PolicyGroup(41, 'crew', false),
              PolicyGroup(42, 'qualified', false),
            ],
            isCurrent: () => true,
            onClose: (value) => saved = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(saved!.attributes, initial.attributes);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => Scaffold(body: child),
        home: SizedBox(
          height: 800,
          child: PolicyBuilder(
            key: UniqueKey(),
            initial: PolicyDefinition(audienceGroups: const []),
            loadGroups: () async => const [],
            isCurrent: () => true,
            onClose: (_) => fail('invalid policy must not save'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(find.text('Choose at least one group.'), findsOneWidget);
  });

  testWidgets('retired builder cannot apply its settings', (tester) async {
    var current = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => Scaffold(body: child),
        home: SizedBox(
          height: 800,
          child: PolicyBuilder(
            initial: PolicyDefinition(audienceGroups: const ['crew']),
            loadGroups: () async => const [PolicyGroup(41, 'crew', false)],
            isCurrent: () => current,
            onClose: (_) => fail('retired editor saved'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    current = false;
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(
      find.text(
        'The policy changed while its settings were open. Open the settings again.',
      ),
      findsOneWidget,
    );
  });

  for (final reminder in [false, true]) {
    testWidgets(
      'persisted unsupported disable is explained (reminder: $reminder)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => Scaffold(body: child),
            home: SizedBox(
              height: 800,
              child: PolicyBuilder(
                persistedDefinition: PolicyDefinition(
                  audienceGroups: const ['crew'],
                  reminder: reminder
                      ? PolicyReminder.daily
                      : PolicyReminder.none,
                  renewal: reminder
                      ? const PolicyNoRenewal()
                      : const PolicyRenewByCalendar(
                          PolicyCalendarInterval.monthly,
                        ),
                ),
                initial: PolicyDefinition(
                  audienceGroups: const ['crew'],
                  reminder: reminder
                      ? PolicyReminder.daily
                      : PolicyReminder.none,
                  renewal: reminder
                      ? const PolicyNoRenewal()
                      : const PolicyRenewByCalendar(
                          PolicyCalendarInterval.monthly,
                        ),
                ),
                loadGroups: () async => const [PolicyGroup(41, 'crew', false)],
                isCurrent: () => true,
                onClose: (_) => fail('unsupported transition saved'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (reminder) {
          tester
              .widget<DSelect<PolicyReminder>>(
                find.byType(DSelect<PolicyReminder>),
              )
              .onChanged!(PolicyReminder.none);
        } else {
          tester
              .widget<DSelect<String>>(find.byType(DSelect<String>).first)
              .onChanged!('none');
        }
        await tester.pump();
        await tester.tap(find.text('Save changes'));
        await tester.pump();
        expect(
          find.text(
            reminder
                ? 'This site does not support turning off an existing policy reminder. Keep a reminder selected.'
                : 'This site does not support turning off existing calendar renewal. Choose a renewal schedule.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final variant in [
    (separator: '\n', body: 'hello', tight: false),
    (separator: '\r\n', body: 'hello', tight: false),
    (separator: '\n', body: '', tight: false),
    (separator: '\n', body: '', tight: true),
    (separator: '\r\n', body: '', tight: true),
  ]) {
    testWidgets('Policy rich body preserves wrapper for $variant', (
      tester,
    ) async {
      late ComposerController composer;
      final state = ComposerPluginState(
        siteSettings: PluginData.none.withValue(
          policySettingsKey,
          const PolicySettings(enabled: true),
        ),
        freshCurrentUser: PluginData.none.withValue(
          policyCurrentUserKey,
          const PolicyCurrentUser(canCreate: true),
        ),
      );
      final policy = PolicyComposerPolicy(
        ComposerSyntaxPolicyContext(
          siteUrl: 'https://example.test',
          isPluginTarget: false,
          isEdit: false,
          initialState: state,
          readState: () => state,
          readEditor: () => composer,
        ),
      );
      composer = ComposerController(
        const ReplyComposerTarget(
          siteUrl: 'https://example.test',
          topicId: 1,
          slug: 'topic',
          topicTitle: 'Topic',
          privateMessageTopic: false,
        ),
        syntaxPolicies: [policy],
        imageUploader:
            (file, {required onProgress, required abortTrigger}) async =>
                const ComposerUploadResult(
                  id: 1,
                  originalFilename: 'new.png',
                  shortUrl: 'upload://new',
                  url: 'https://example.test/new.png',
                  width: 100,
                  height: 80,
                ),
      );
      addTearDown(composer.dispose);
      final source = [
        'Before',
        '',
        '[policy groups="crew" version="v2"]',
        if (!variant.tight) variant.body,
        '[/policy]',
        '',
        'After',
      ].join(variant.separator);
      composer.text.text = source;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => Scaffold(body: child),
          home: SizedBox(
            height: 500,
            child: ComposerEditor(
              composer: composer,
              hintText: '',
              textStyle: const TextStyle(fontSize: 16),
              hintStyle: const TextStyle(fontSize: 16),
              autofocus: false,
              enableDropTarget: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Policy'), findsOneWidget);
      final body = tester
          .widget<ComposerRichBodyEditor>(find.byType(ComposerRichBodyEditor))
          .composer;
      expect(body.value.text, variant.body);
      if (variant.tight) {
        body.addFiles([
          ComposerUploadFile(
            name: 'new.png',
            length: () async => 3,
            openRead: () => Stream.value([1, 2, 3]),
          ),
        ], 0);
        await tester.pumpAndSettle();
        expect(
          const PolicySourceCodec().find(composer.value.text).single.body,
          contains('upload://new'),
        );
        expect(body.isCurrent, isTrue);
      }
      body.text.text = 'updated body';
      await tester.pump();
      expect(
        composer.value.text,
        contains('[policy groups="crew" version="v2"]'),
      );
      expect(
        composer.value.text,
        [
          'Before',
          '',
          '[policy groups="crew" version="v2"]',
          'updated body',
          '[/policy]',
          '',
          'After',
        ].join(variant.separator),
      );
      expect(
        composer.value.text,
        endsWith('[/policy]${variant.separator}${variant.separator}After'),
      );
      body.text.text = '';
      body.text.text = 'second edit';
      expect(
        composer.value.text,
        contains(
          '${variant.separator}second edit${variant.separator}[/policy]',
        ),
      );
      expect(body.history.undo(), isTrue);
      expect(body.history.redo(), isTrue);
      expect(
        composer.value.text,
        contains(
          '${variant.separator}second edit${variant.separator}[/policy]',
        ),
      );
      expect(body.isCurrent, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
