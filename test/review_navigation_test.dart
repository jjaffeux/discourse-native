import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/shell/review_page.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/review_fixture.dart';
import 'support/shell_test_harness.dart';

const siteUrl = 'https://forum.example/discuss';
const moderator = DiscourseUser(id: 7, username: 'sam', staff: true);
const member = DiscourseUser(id: 9, username: 'ann');

class ReviewTestApi extends FakeDiscourseApi {
  ReviewTestApi(DiscourseUser user) : super(user: user);

  final reads = <String>[];
  final writes = <String>[];

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final uri = Uri.parse(path);
    if (uri.path == '/review.json') {
      reads.add(path);
      return reviewListFixture(more: false);
    }
    if (RegExp(r'^/review/\d+\.json$').hasMatch(uri.path)) {
      reads.add(path);
      return reviewDetailFixture(int.parse(uri.pathSegments[1].split('.')[0]));
    }
    return super.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    if (path.startsWith('/review/')) {
      writes.add('$method $path');
      return reviewPerformFixture(77);
    }
    return super.pluginWriteJson(
      siteUrl: siteUrl,
      path: path,
      method: method,
      apiKey: apiKey,
      body: body,
      clientId: clientId,
    );
  }
}

void main() {
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <String>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, (call) async {
          if (call.method == 'launch') {
            launched.add((call.arguments as Map)['url'] as String);
          }
          return true;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, null);
  });

  testWidgets('a review notification opens the item natively and acting on it '
      'returns to a queue without it', (tester) async {
    final api = ReviewTestApi(moderator);
    final auth = FakeAuthenticator()..keys[siteUrl] = 'staff-key';
    await pumpShell(
      tester,
      desktop,
      api: api,
      authenticator: auth,
      instances: const [
        DiscourseInstance(url: siteUrl, title: 'Forum', user: moderator),
      ],
    );
    final shell = ShellScope.read(tester.element(primaryMainContent));

    expect(await shell.openNotificationUrl('$siteUrl/review/77'), isTrue);
    await tester.pumpAndSettle();

    expect(launched, isEmpty);
    expect(shell.currentContent?.isPage(CorePage.review), isTrue);
    expect(find.byType(ReviewItemPage), findsOneWidget);
    expect(api.reads, containsAll(['/review.json?status=pending']));
    expect(api.reads, contains('/review/77.json'));

    await tester.tap(find.text('Keep post'));
    await tester.pumpAndSettle();

    expect(api.writes, ['PUT /review/77/perform/agree_and_keep?version=2']);
    expect(find.byType(ReviewItemPage), findsNothing);
    final queue = tester.widget<ReviewQueuePage>(find.byType(ReviewQueuePage));
    expect(queue.state.items.map((item) => item.id), [78, 79, 80]);
    expect(find.text('Flag agreed.'), findsOneWidget);
    expect(
      api.reads.where((path) => path.startsWith('/review.json')),
      hasLength(1),
    );

    // The tab is the queue again, so the same link is a new destination.
    expect(shell.currentContent?.id, 'review');
    expect(await shell.openNotificationUrl('$siteUrl/review/78'), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(ReviewItemPage), findsOneWidget);
    await tester.tap(find.text('Back to queue'));
    await tester.pumpAndSettle();
    expect(shell.currentContent?.id, 'review');
    expect(await shell.openNotificationUrl('$siteUrl/review/78'), isTrue);
    await tester.pumpAndSettle();
    expect(find.byType(ReviewItemPage), findsOneWidget);
    expect(
      api.reads.where((path) => path.startsWith('/review.json')),
      hasLength(1),
    );
  });

  testWidgets('the sidebar row counts unseen items for a reviewer only', (
    tester,
  ) async {
    final api = ReviewTestApi(moderator);
    final auth = FakeAuthenticator()..keys[siteUrl] = 'staff-key';
    await pumpShell(
      tester,
      desktop,
      api: api,
      authenticator: auth,
      instances: const [
        DiscourseInstance(url: siteUrl, title: 'Forum', user: moderator),
      ],
    );
    final shell = ShellScope.read(tester.element(primaryMainContent));
    shell.accountActivity.applyReviewableCounts(siteUrl, {
      'unseen_reviewable_count': 3,
    });
    expect(
      shell.sidebarBadgeFor(SidebarDestination.reviewId),
      const SidebarBadge.count(3),
    );
  });

  testWidgets('a member following a review link is told, and nothing is read', (
    tester,
  ) async {
    final api = ReviewTestApi(member);
    final auth = FakeAuthenticator()..keys[siteUrl] = 'member-key';
    await pumpShell(
      tester,
      desktop,
      api: api,
      authenticator: auth,
      instances: const [
        DiscourseInstance(url: siteUrl, title: 'Forum', user: member),
      ],
    );
    final shell = ShellScope.read(tester.element(primaryMainContent));
    shell.accountActivity.applyReviewableCounts(siteUrl, {
      'unseen_reviewable_count': 3,
    });
    expect(
      shell.sidebarBadgeFor(SidebarDestination.reviewId),
      SidebarBadge.none,
    );

    expect(await shell.openNotificationUrl('$siteUrl/review/77'), isTrue);
    await tester.pumpAndSettle();

    expect(
      find.text('Only staff and category moderators can see the review queue.'),
      findsOneWidget,
    );
    expect(find.byType(ReviewItemPage), findsNothing);
    expect(api.reads, isEmpty);
    expect(launched, isEmpty);
  });
}
