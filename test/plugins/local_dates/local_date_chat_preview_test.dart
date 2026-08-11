import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugins/chat/chat_preview.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_widget.dart';
import 'package:discourse_native/src/plugins/local_dates/local_dates_plugin.dart';
import 'package:discourse_native/src/plugins/site_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    LocalDateEnvironment.instance.ensureDatabase();
    LocalDateEnvironment.instance.setDeviceTimezone('Etc/UTC');
    await initializeDateFormatting('en');
  });

  const plugin = LocalDatesPlugin();
  const enabled = SiteConfig(localDatesEnabled: true);
  const disabled = SiteConfig(localDatesEnabled: false);

  ChatPreviewRequest request(String raw, {SiteConfig config = enabled}) =>
      ChatPreviewRequest(raw: raw, siteConfig: config);

  test(
    'claims safely projectable syntax when the cached setting is enabled',
    () {
      const raw = 'Meet [date=2026-08-12 time=09:30 timezone=Etc/UTC].';
      final inspection = plugin.inspect(request(raw));

      expect(inspection.blockers, isEmpty);
      expect(inspection.claims, hasLength(1));
      expect(inspection.claims.single.node.featureId, plugin.previewFeatureId);
      expect(inspection.claims.single.node.fallbackText, contains('[date='));

      final projected =
          ChatPreviewEngine(plugins: const [plugin]).project(request(raw))
              as ProjectedPreview;
      expect(
        projected.document.nodes.whereType<PluginPreviewNode>(),
        hasLength(1),
      );
    },
  );

  test('known syntax blocks projection when Local Dates is disabled', () {
    const raw = '[date=2026-08-12 timezone=Etc/UTC]';
    final inspection = plugin.inspect(request(raw, config: disabled));
    final result = ChatPreviewEngine(
      plugins: const [plugin],
    ).project(request(raw, config: disabled));

    expect(inspection.claims, isEmpty);
    expect(inspection.blockers, isNotEmpty);
    expect(result, isA<SourceFallback>());
  });

  test('malformed and forward-incompatible options block projection', () {
    for (final raw in const [
      '[date=not-a-date]',
      '[date=2026-08-12 timezone=Future/Mars]',
      '[date=2026-08-12 future-option=enabled]',
    ]) {
      final inspection = plugin.inspect(request(raw));
      expect(inspection.claims, isEmpty, reason: raw);
      expect(inspection.blockers, isNotEmpty, reason: raw);
    }
  });

  test('date-looking source inside code belongs to the core code grammar', () {
    for (final raw in const [
      '`[date=2026-08-12]`',
      '```\n[date=2026-08-12]\n```',
    ]) {
      final inspection = plugin.inspect(request(raw));
      final result = ChatPreviewEngine(
        plugins: const [plugin],
      ).project(request(raw));

      expect(inspection.claims, isEmpty, reason: raw);
      expect(inspection.blockers, isEmpty, reason: raw);
      expect(result, isA<ProjectedPreview>(), reason: raw);
    }
  });

  testWidgets(
    'the static registry renders a claimed node with Local Dates UI',
    (tester) async {
      const raw = '[date=2026-08-12 time=09:30 timezone=Etc/UTC]';
      final result =
          pluginRegistry.chatPreviewEngine.project(request(raw))
              as ProjectedPreview;
      final node = result.document.nodes.whereType<PluginPreviewNode>().single;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  pluginRegistry.buildChatPreviewNode(context, node)!,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LocalDateInline), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
