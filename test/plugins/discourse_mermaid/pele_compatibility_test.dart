import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'test/plugins/discourse_mermaid/fixtures/pele.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  for (final profile in CookingProfile.values) {
    testWidgets(
      'Pele diagrams render in ${profile.name} without site metadata',
      (tester) async {
        final installed = PluginInstaller.install(bundledPluginManifest);
        addTearDown(installed.close);
        final cooking = OfflineCookingService();
        addTearDown(cooking.dispose);
        final result = await tester.runAsync(
          () => cooking.cook(
            CookingRequest(
              raw: fixture['raw'] as String,
              profile: profile,
              configuration: cookingConfiguration(installed.cookingPlugins),
              snapshot: CookingSnapshot(
                siteId: 'https://pele.example',
                accountId: 'test-account',
              ),
            ),
          ),
        );
        expect(result, isNotNull);
        expect(result!.failure, isNull);
        expect(result.html, fixture['cooked']);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: CookedHtml(
                html: result.html,
                registry: installed.registry,
                compactParagraphs: profile.name == 'chat',
                contentSized: profile.name == 'chat',
                buildAsync: false,
              ),
            ),
          ),
        );
        expect(find.byType(DMermaid), findsOneWidget);
        expect(find.byType(CodeBlock), findsNothing);
        final diagram = tester.widget<DMermaid>(find.byType(DMermaid));
        expect(diagram.source, fixture['source']);
        expect(diagram.height, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
