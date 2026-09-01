import 'package:discourse_native/src/plugin_api/composer_component.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_component.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_composer_pill.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_plugin.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../support/fake_composer_editor_host.dart';

void main() {
  final environment = LocalDateEnvironment.instance;
  late LocalDateComposerSyntaxPolicy policy;

  setUpAll(() async {
    environment.ensureDatabase();
    environment.setDeviceTimezone('Etc/UTC');
    await initializeDateFormatting('en');
  });

  setUp(() {
    policy = LocalDateComposerSyntaxPolicy(
      environment: environment,
      accountTimezone: 'Etc/UTC',
    );
  });

  testWidgets(
    'declares an exact typed inline candidate and renders its captured block',
    (tester) async {
      const syntax =
          '[date=2026-08-09 time=09:00:00 timezone=Etc/UTC calendar=off]';
      const markdown = 'Before $syntax after';
      final component = localDateComposerComponent(policy);
      final candidate = component.find(markdown).single;
      final instance = ComposerComponentInstance(
        range: candidate.range,
        source: markdown.substring(candidate.range.start, candidate.range.end),
        value: candidate.value,
      );
      final renderContext = ComposerComponentRenderContext(
        range: instance.range,
        value: instance.value,
        baseStyle: const TextStyle(fontSize: 17),
        selected: true,
        hovered: false,
      );
      late BuildContext buildContext;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                buildContext = context;
                return component.builder(context, renderContext);
              },
            ),
          ),
        ),
      );

      expect(component.layout, ComposerComponentLayout.inline);
      expect(candidate.range, const TextRange(start: 7, end: 68));
      expect(candidate.value, isA<LocalDateComposerBlock>());
      expect(instance.source, syntax);

      final pill = tester.widget<LocalDateComposerPill>(
        find.byType(LocalDateComposerPill),
      );
      final summary = localDateComposerSummary(
        candidate.value,
        locale: const Locale('en'),
        accountTimezone: 'Etc/UTC',
        formatter: policy.formatter,
      );
      expect(pill.label, summary);
      expect(pill.highlighted, isTrue);
      final presentation = ComposerComponentPresentation(
        range: instance.range,
        value: instance.value,
      );
      expect(
        component.semanticLabel(buildContext, presentation),
        '$summary. Activate to edit.',
      );
      expect(component.onEdit, isNotNull);
      expect(component.onRemove, isNotNull);
    },
  );

  testWidgets('removal uses the existing verified action and rejects drift', (
    tester,
  ) async {
    const syntax = '[date=2026-08-09 timezone=Etc/UTC]';
    const markdown = 'Before $syntax after';
    final component = localDateComposerComponent(policy);
    final candidate = component.find(markdown).single;
    final instance = ComposerComponentInstance(
      range: candidate.range,
      source: syntax,
      value: candidate.value,
    );

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const Scaffold()),
    );
    final context = tester.element(find.byType(Scaffold));
    final editor = FakeComposerEditorHost(
      const TextEditingValue(text: markdown),
    );

    component.onRemove!(context, editor, instance);

    expect(editor.value.text, 'Before  after');
    expect(editor.value.selection, const TextSelection.collapsed(offset: 7));
    expect(editor.commitCalls, 1);
    expect(editor.focusRequested, isTrue);

    final stale = FakeComposerEditorHost(
      const TextEditingValue(text: 'Changed before $syntax after'),
    );
    component.onRemove!(context, stale, instance);

    expect(stale.value.text, 'Changed before $syntax after');
    expect(stale.commitCalls, 0);
    expect(stale.focusRequested, isFalse);
  });

  testWidgets('a formatting failure never exposes recognized source', (
    tester,
  ) async {
    const syntax = '[date=2026-08-09 timezone=Etc/UTC]';
    final component = buildLocalDateComposerComponent(
      kind: localDateComposerSyntaxKind,
      environment: environment,
      formatter: _ThrowingLocalDateFormatter(environment),
      accountTimezone: () => 'Etc/UTC',
      onEdit: (context, editor, component) {},
      onRemove: (context, editor, component) {},
    );
    final candidate = component.find(syntax).single;
    final instance = ComposerComponentInstance(
      range: candidate.range,
      source: syntax,
      value: candidate.value,
    );
    final renderContext = ComposerComponentRenderContext(
      range: instance.range,
      value: instance.value,
      baseStyle: const TextStyle(fontSize: 17),
      selected: false,
      hovered: false,
    );
    late BuildContext buildContext;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) {
            buildContext = context;
            return component.builder(context, renderContext);
          },
        ),
      ),
    );

    final pill = tester.widget<LocalDateComposerPill>(
      find.byType(LocalDateComposerPill),
    );
    expect(pill.label, 'Local date');
    expect(pill.label, isNot(contains('[date=')));
    final presentation = ComposerComponentPresentation(
      range: instance.range,
      value: instance.value,
    );
    expect(
      component.semanticLabel(buildContext, presentation),
      'Local date. Activate to edit.',
    );
  });
}

final class _ThrowingLocalDateFormatter extends LocalDateFormatter {
  const _ThrowingLocalDateFormatter(LocalDateEnvironment environment)
    : super(environment: environment);

  @override
  LocalDateResolved? resolve(
    LocalDateSpec spec, {
    required Locale locale,
    String? accountTimezone,
    DateTime? now,
    bool sameLocalDayAsFrom = false,
  }) => throw StateError('format unavailable');
}
