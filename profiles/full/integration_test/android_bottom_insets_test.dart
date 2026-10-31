import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../../test/mobile_shell_test.dart' as fixture;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;

  testWidgets('Android navigation area stays below the dock and sidebar', (
    tester,
  ) async {
    await fixture.pumpMobileShellFixture(tester);
    tester.view.reset();
    await tester.pumpAndSettle();
    final view = tester.view;
    final height = view.physicalSize.height / view.devicePixelRatio;
    final inset = view.padding.bottom / view.devicePixelRatio;
    expect(inset, greaterThan(0));
    final usableBottom = height - inset;
    final dock = find.byKey(const ValueKey('mobile-dock-surface'));
    expect(
      tester.getRect(dock).bottom,
      lessThanOrEqualTo(usableBottom),
      reason: 'The dock must clear Android system navigation',
    );
    await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
    await tester.pumpAndSettle();
    final account = find.byKey(const ValueKey('user-profile-card'));
    expect(tester.getRect(account).bottom, lessThanOrEqualTo(usableBottom));
    await tester.tap(find.byKey(const ValueKey('mobile-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(DMobileDock.moreKey));
    await tester.pumpAndSettle();
    final panel = find.byKey(DMobileDock.panelKey);
    expect(tester.getRect(panel).bottom, lessThanOrEqualTo(usableBottom));
    expect(tester.takeException(), isNull);
  });
}
