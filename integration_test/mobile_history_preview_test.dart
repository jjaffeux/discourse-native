import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/mobile_shell_test.dart' show pumpMobileShellFixture;
import '../test/support/fakes.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;

  testWidgets('Forward shows the saved topic before opening it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('org.discourse.native/notification_opens');
    final messenger = binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final nativeSize = tester.view.physicalSize;
    final nativeRatio = tester.view.devicePixelRatio;
    const title = 'A discussion to return to';
    final shell = await pumpMobileShellFixture(
      tester,
      topics: const [Topic(id: 7, title: title, slug: 'discussion')],
      topic: topicPayload(
        id: 7,
        title: title,
        posts: const [
          Post(
            id: 1,
            postNumber: 1,
            username: 'reader',
            cooked: '<p>First post</p>',
          ),
        ],
      ),
    );
    tester.view.physicalSize = nativeSize;
    tester.view.devicePixelRatio = nativeRatio;
    await tester.pumpAndSettle();
    await tester.tap(find.text(title).first);
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, 7);

    expect(shell.handleBack(), isTrue);
    await tester.pumpAndSettle();
    binding.handleMemoryPressure();
    await tester.pumpAndSettle();
    final preview = find.text('First post', findRichText: true);
    expect(preview, findsNothing);
    final phone = tester.getRect(find.byKey(const ValueKey('mobile-root')));
    final swipe = await tester.startGesture(
      Offset(phone.right - 5, phone.center.dy),
    );
    await swipe.moveBy(
      const Offset(-270, 0),
      timeStamp: const Duration(milliseconds: 200),
    );
    await tester.pump();
    expect(preview, findsOneWidget);
    expect(preview.hitTestable(), findsNothing);
    expect(shell.currentContent?.isTopicList, isTrue);

    await swipe.up(timeStamp: const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.topicId, 7);
    expect(tester.takeException(), isNull);
  });
}
