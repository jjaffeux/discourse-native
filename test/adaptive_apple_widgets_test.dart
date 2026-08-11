import 'package:discourse_native/src/shell/adaptive_activity_indicator.dart';
import 'package:discourse_native/src/shell/adaptive_dialog_action.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in const [TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets('uses Cupertino activity indicators on ${platform.name}', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          platform,
          const AdaptiveActivityIndicator(color: Color(0xFF123456)),
        ),
      );

      final indicator = tester.widget<CupertinoActivityIndicator>(
        find.byType(CupertinoActivityIndicator),
      );
      expect(indicator.color, const Color(0xFF123456));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('uses Cupertino dialog actions on ${platform.name}', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          platform,
          const AdaptiveDialogAction(
            onPressed: null,
            kind: AdaptiveDialogActionKind.destructive,
            child: Text('Remove'),
          ),
        ),
      );

      final action = tester.widget<CupertinoDialogAction>(
        find.byType(CupertinoDialogAction),
      );
      expect(action.isDestructiveAction, isTrue);
      expect(find.byType(FilledButton), findsNothing);
    });
  }

  testWidgets('keeps Material controls on non-Apple platforms', (tester) async {
    await tester.pumpWidget(
      _app(
        TargetPlatform.linux,
        const Column(
          children: [
            AdaptiveActivityIndicator(color: Color(0xFF123456)),
            AdaptiveDialogAction(
              onPressed: null,
              kind: AdaptiveDialogActionKind.destructive,
              child: Text('Remove'),
            ),
          ],
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.byType(CupertinoDialogAction), findsNothing);
  });

  testWidgets('uses the Discourse modal theme for app-owned Apple dialogs', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        TargetPlatform.macOS,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDiscourseDialog<void>(
              context: context,
              builder: (dialogContext) => DiscourseAlertDialog(
                title: const Text('Remove site?'),
                actions: [
                  AdaptiveDialogAction(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  AdaptiveDialogAction(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    kind: AdaptiveDialogActionKind.destructive,
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    final alert = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(alert.actionsAlignment, MainAxisAlignment.start);
    expect(alert.actionsOverflowAlignment, OverflowBarAlignment.start);
    expect(alert.actionsOverflowButtonSpacing, 8);
    expect(find.widgetWithText(FilledButton, 'Cancel'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Remove'), findsOneWidget);
    final cancel = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Cancel'),
    );
    final colors = AppTheme.light.colorScheme;
    expect(
      cancel.style?.backgroundColor?.resolve({}),
      colors.surfaceContainerHigh,
    );
    expect(cancel.style?.foregroundColor?.resolve({}), colors.onSurface);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.byType(CupertinoDialogAction), findsNothing);
  });
}

Widget _app(TargetPlatform platform, Widget child) => MaterialApp(
  theme: AppTheme.light.copyWith(platform: platform),
  home: Scaffold(body: Center(child: child)),
);
