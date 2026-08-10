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
}

Widget _app(TargetPlatform platform, Widget child) => MaterialApp(
  theme: AppTheme.light.copyWith(platform: platform),
  home: Scaffold(body: Center(child: child)),
);
