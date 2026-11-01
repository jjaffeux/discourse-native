import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/plugins/chat/chat_mobile_sidebar.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.discourse.native/notification_opens');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => null));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
    'chat restores chrome after topic and search dismissal',
    (tester) async {
      final shell = await pumpMobileShellFixture(tester);
      shell.selectMobilePanel('chat');
      await tester.pumpAndSettle();
      expect(find.byType(ChatMobileSidebar), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-search-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.inputKey), findsOneWidget);
      shell.openSearchResult(
        const SearchPostHit(
          postId: 1,
          topicId: 7,
          postNumber: 1,
          topicTitle: 'Shared topic card',
          topicSlug: 'shared',
          username: 'reader',
          excerpt: SearchExcerpt([]),
        ),
        words: 'shared',
      );
      await tester.pumpAndSettle();
      expect(shell.currentContent?.topicId, 7);
      expect(shell.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(ForumSearch.inputKey), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-search-back')));
      await tester.pumpAndSettle();
      expect(find.byType(ChatMobileSidebar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile-header')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mobile-bottom-bar')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
}
