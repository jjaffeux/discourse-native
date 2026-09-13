import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/add_instance_sheet.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/discover_sites.dart';

void main() {
  Future<void> openAddSite(
    WidgetTester tester,
    TargetPlatform platform, {
    ThemeData? theme,
  }) async {
    final source = emptyDiscoverSites();
    addTearDown(source.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: (theme ?? AppTheme.dark).copyWith(platform: platform),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () =>
                  showAddInstanceSheet(context, discoverSites: source),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('uses a dialog on macOS', (tester) async {
    await openAddSite(tester, TargetPlatform.macOS);

    expect(find.byType(DDialogContent), findsOneWidget);
    expect(find.byType(DDialogTitle), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Add a site'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
  });

  testWidgets('uses the Native drawer on Android', (tester) async {
    await openAddSite(tester, TargetPlatform.android);

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(DDrawerContent), findsOneWidget);
    expect(find.text('Add a site'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    testWidgets(
      '${platform.name} uses Home colors and follows system appearance',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final siteTheme = StyleguideTheme.plum.resolve(AppTheme.light);
        await openAddSite(tester, platform, theme: siteTheme);

        void expectHomeTheme(ThemeData expected) {
          for (final finder in [
            find.byType(
              platform == TargetPlatform.macOS
                  ? DDialogContent
                  : DDrawerContent,
            ),
            find.byType(DInput),
            find.text('Connect'),
            find.text('Discover more communities'),
          ]) {
            final theme = Theme.of(tester.element(finder));
            expect(theme.colorScheme, expected.colorScheme);
            final tokens = theme.extension<DTokens>()!;
            final homeTokens = expected.extension<DTokens>()!;
            expect(tokens.surface, homeTokens.surface);
            expect(tokens.primary, homeTokens.primary);
            expect(tokens.foreground, homeTokens.foreground);
            expect(theme.platform, platform);
          }
          expect(
            Theme.of(tester.element(find.text('Open'))).colorScheme,
            siteTheme.colorScheme,
          );
        }

        expectHomeTheme(AppTheme.light);
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.pumpAndSettle();
        expectHomeTheme(AppTheme.dark);
      },
    );
  }
}
