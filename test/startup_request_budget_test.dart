import 'dart:async';

import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/site_appearance_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cold start finishes selected account work before other sites',
    () async {
      const firstUrl = 'https://first.example';
      const secondUrl = 'https://second.example';
      final first = _connected(firstUrl).copyWith(appearance: siteAppearance());
      final second = _connected(secondUrl);
      final api = _StartupApi(firstUrl, first.appearance!);
      final authenticator = FakeAuthenticator()
        ..keys[firstUrl] = 'first-key'
        ..keys[secondUrl] = 'second-key';
      final shell = ShellController(
        instanceStore: FakeInstanceStore([first, second]),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(shell.dispose);

      await shell.load();
      await pumpEventQueue();

      expect(api.totalsSites, [firstUrl]);
      expect(
        api.appearancesRequested,
        isEmpty,
        reason: 'persisted appearance refresh waits behind selected JSON work',
      );

      api.firstTotals.complete(const NotificationTotals());
      await pumpEventQueue();

      expect(api.appearancesRequested, [firstUrl]);
      expect(api.totalsSites, [firstUrl, secondUrl]);
    },
  );
}

DiscourseInstance _connected(String url) => DiscourseInstance(
  url: url,
  title: Uri.parse(url).host,
  apiVersion: 4,
  user: const DiscourseUser(id: 7, username: 'reader'),
);

final class _StartupApi extends FakeDiscourseApi {
  _StartupApi(this.firstUrl, SiteAppearance appearance)
    : super(
        totals: const NotificationTotals(),
        siteAppearances: {firstUrl: appearance},
      );

  final String firstUrl;
  final Completer<NotificationTotals> firstTotals = Completer();
  final List<String> totalsSites = [];

  @override
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) {
    totalsSites.add(siteUrl);
    if (siteUrl == firstUrl) return firstTotals.future;
    return Future.value(const NotificationTotals());
  }
}
