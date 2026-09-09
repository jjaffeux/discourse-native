import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/voice/voice_room_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/toggle_review_main.dart';

void main() {
  testWidgets('review fixture mounts and owns actual Voice toggle adapters', (
    tester,
  ) async {
    await tester.pumpWidget(const ToggleReviewApp());

    expect(find.byType(VoiceToolbarControl), findsNWidgets(7));
    expect(find.byType(DToggle), findsAtLeastNWidgets(6));

    await tester.tap(find.byTooltip('Mute'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unmute'), findsOneWidget);

    await tester.tap(find.text('RTL off'));
    await tester.tap(find.text('100% text'));
    await tester.pumpAndSettle();
    expect(find.text('RTL on'), findsOneWidget);
    expect(find.text('200% text'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
