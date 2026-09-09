import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/local_dates/local_date_environment.dart';
import 'package:discourse_native/src/shell/app_settings_page.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/switch_review_main.dart';

void main() {
  testWidgets(
    'local review settings switch writes only its memory settings owner',
    (tester) async {
      await tester.pumpWidget(const SwitchReviewApp());
      await tester.tap(find.text('Settings — memory persistence'));
      await tester.pumpAndSettle();
      final settings = ShellScope.read(
        tester.element(find.byType(AppSettingsModal)),
      ).appSettings;
      expect(settings.disableGifAnimations, false);
      await tester.tap(find.text('Disable GIF animations'));
      await tester.pumpAndSettle();
      expect(settings.disableGifAnimations, true);
      expect(
        tester
            .widget<DSwitchTile>(
              find.byKey(const ValueKey('disable-gif-animations-switch')),
            )
            .value,
        true,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('local review opens real poll date group and Voice controls', (
    tester,
  ) async {
    LocalDateEnvironment.instance.ensureDatabase();
    for (final (label, switchLabel) in [
      ('Preferences — fake account', 'Notify me about replies to linked posts'),
      ('Chat settings — fake account', 'Mute channel'),
      ('Poll — local draft', 'Show who voted'),
      ('Local date — local draft', 'Include time'),
      ('Group management — local updates', 'Members can leave'),
      ('Voice diagnostics — fake capture', 'Recording Off'),
    ]) {
      await tester.pumpWidget(const SwitchReviewApp());
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.byType(DSwitch), findsWidgets, reason: label);
      if (label.startsWith('Group') || label.startsWith('Voice')) {
        expect(find.text(switchLabel), findsOneWidget);
        await tester.tap(find.text(switchLabel));
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
    }
  });
}
