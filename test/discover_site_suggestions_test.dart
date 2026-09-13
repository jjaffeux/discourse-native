import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discover_sites.dart';
import 'package:discourse_native/src/shell/add_instance_sheet.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/discover_sites.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart' show watchBrowser;

void main() {
  Future<ShellController> open(
    WidgetTester tester,
    DiscoverSites source, {
    Size size = const Size(1100, 900),
    double textScale = 1,
    TargetPlatform platform = TargetPlatform.macOS,
    bool dark = false,
    bool rtl = false,
    double keyboard = 0,
    FakeDiscourseApi? api,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ShellController(
      instanceStore: FakeInstanceStore([instance('community0.example')]),
      api: api ?? FakeDiscourseApi(),
      discoverSites: source,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
            platform: platform,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: child!,
            ),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => DButton(
                label: const Text('Add site'),
                onPressed: () => showAddInstanceSheet(context),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add site'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return controller;
  }

  http.Response batch() => http.Response(
    jsonEncode({'topics': List.generate(50, discoverEntry)}),
    200,
  );

  testWidgets(
    'skeleton leaves the form and Discover link usable, then shows ten in two columns',
    (tester) async {
      final gate = Completer<http.Response>();
      final source = DiscoverSites(client: MockClient((_) => gate.future));
      final launched = watchBrowser(tester);
      await open(tester, source);

      expect(find.byType(DSkeletonRegion), findsOneWidget);
      expect(find.byType(DItem), findsNWidgets(10));
      expect(tester.widget<DInput>(find.byType(DInput)).enabled, isTrue);
      expect(find.byType(DBadge), findsNothing);
      await tester.tap(find.text('Discover more communities'));
      await tester.pump();
      expect(launched, [DiscoverSites.browseUrl]);

      gate.complete(batch());
      await tester.pumpAndSettle();
      expect(find.byType(DSkeletonRegion), findsNothing);
      expect(find.byType(DItem), findsNWidgets(10));
      expect(find.text('Community 0'), findsNothing);
      expect(find.text('Community 10'), findsOneWidget);
      expect(find.text('Community 11'), findsNothing);
      final first = tester.getRect(
        find.byKey(const ValueKey('discover-site-https://community1.example')),
      );
      final second = tester.getRect(
        find.byKey(const ValueKey('discover-site-https://community2.example')),
      );
      expect(first.top, second.top);
      expect(second.left, greaterThan(first.right));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selection fills the address and connects through the existing lookup',
    (tester) async {
      var fetches = 0;
      final source = DiscoverSites(
        client: MockClient((_) async {
          fetches++;
          return batch();
        }),
      );
      final api = FakeDiscourseApi(
        results: {'https://community1.example': instance('community1.example')},
      );
      final controller = await open(tester, source, api: api);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Community 1'));
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'https://community1.example',
      );
      expect(
        tester
            .widget<DItem>(
              find.byKey(
                const ValueKey('discover-site-https://community1.example'),
              ),
            )
            .selected,
        isTrue,
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(api.lookups, ['https://community1.example']);
      expect(
        controller.instances.any(
          (site) => site.url == 'https://community1.example',
        ),
        isTrue,
      );

      await tester.tap(find.text('Add site'));
      await tester.pumpAndSettle();
      expect(fetches, 1);
      expect(find.text('Community 1'), findsNothing);
      expect(find.text('Community 11'), findsOneWidget);
      expect(find.byType(DItem), findsNWidgets(10));
    },
  );

  testWidgets('failure can be retried and dismissal ignores late results', (
    tester,
  ) async {
    var fetches = 0;
    final gate = Completer<http.Response>();
    final source = DiscoverSites(
      client: MockClient((_) async {
        if (++fetches == 1) return http.Response('{}', 200);
        return gate.future;
      }),
    );
    await open(tester, source);
    await tester.pumpAndSettle();
    expect(find.text('Suggestions are unavailable right now.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.byType(DSkeletonRegion), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pump(const Duration(milliseconds: 400));
    gate.complete(batch());
    await tester.pumpAndSettle();
    expect(find.byType(DDialogContent), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    testWidgets(
      'narrow ${platform.name} layout handles large RTL text and keyboard insets',
      (tester) async {
        final source = DiscoverSites(client: MockClient((_) async => batch()));
        await open(
          tester,
          source,
          size: const Size(390, 844),
          textScale: 2,
          platform: platform,
          dark: true,
          rtl: true,
          keyboard: 280,
        );
        await tester.pumpAndSettle();
        final first = tester.getRect(
          find.byKey(
            const ValueKey('discover-site-https://community1.example'),
          ),
        );
        final second = tester.getRect(
          find.byKey(
            const ValueKey('discover-site-https://community2.example'),
          ),
        );
        expect(first.left, second.left);
        expect(second.top, greaterThan(first.bottom));
        expect(find.byType(DItem), findsNWidgets(10));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
