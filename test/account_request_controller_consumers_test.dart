import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_transport.dart';
import 'package:discourse_native/src/data/groups_api.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/invites_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/data/user_directory_api.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/do_not_disturb.dart';
import 'package:discourse_native/src/models/invite.dart';
import 'package:discourse_native/src/models/user_directory.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/shell/account_activity_controller.dart';
import 'package:discourse_native/src/shell/do_not_disturb_controller.dart';
import 'package:discourse_native/src/shell/groups_controller.dart';
import 'package:discourse_native/src/shell/invites_controller.dart';
import 'package:discourse_native/src/shell/preferences_controller.dart';
import 'package:discourse_native/src/shell/topic_feed_controller.dart';
import 'package:discourse_native/src/shell/user_directory_controller.dart';
import 'package:discourse_native/src/shell/user_summary_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _site = 'https://forum.example';
const _instance = DiscourseInstance(
  url: _site,
  title: 'Forum',
  user: DiscourseUser(id: 1, username: 'reader', canInviteToForum: true),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final outcome in ['success', 'unknown']) {
    test(
      'dispatched controller write preserves $outcome after retirement without retry',
      () async {
        final dispatched = Completer<void>();
        final response = Completer<http.Response>();
        var sends = 0;
        final api = DiscourseApi(
          client: MockClient((request) {
            sends++;
            dispatched.complete();
            return response.future;
          }),
        );
        addTearDown(api.close);
        final lifecycle = SiteLifecycle();
        var publications = 0;
        final controller = DoNotDisturbController(
          api: api,
          credentials: _Credentials(),
          lifecycle: lifecycle,
          onCommitted: (_, _) => publications++,
        );
        addTearDown(controller.dispose);
        final pending = controller.pause(
          _site,
          const DoNotDisturbDuration.minutes(30),
        );
        await dispatched.future;
        lifecycle.invalidate(_site);
        await pumpEventQueue();
        expect(sends, 1);
        if (outcome == 'success') {
          response.complete(http.Response('{}', 200));
        } else {
          response.completeError(http.ClientException('response lost'));
        }
        await pending;
        await pumpEventQueue();
        expect(sends, 1);
        expect(publications, 0);
      },
    );
  }

  for (final consumer in [
    'activity totals',
    'topic feed',
    'user summary',
    'preferences',
    'directory metadata',
    'group directory',
    'invites read',
    'invites write',
    'do not disturb write',
  ]) {
    test('$consumer withdraws queued HTTP when its account retires', () async {
      final sent = <http.Request>[];
      final transport = DiscourseTransport(
        SafeHttpClient.owned(
          MockClient((request) async {
            sent.add(request);
            return http.Response('{}', 200);
          }),
        ),
        const Duration(seconds: 5),
        4096,
        maxConcurrentPerOrigin: 1,
      );
      final api = DiscourseApi(transport: transport);
      addTearDown(api.close);
      final lifecycle = SiteLifecycle();
      final credentials = _Credentials();
      final release = Completer<http.Response>();
      addTearDown(() {
        if (!release.isCompleted) release.complete(http.Response('{}', 200));
      });
      final occupied = transport.coordinator.run(
        Uri.parse(_site),
        () => release.future,
      );
      late Future<void> operation;
      switch (consumer) {
        case 'activity totals':
          final controller = AccountActivityController(
            api: api,
            credentials: credentials,
            lifecycle: lifecycle,
          );
          addTearDown(controller.dispose);
          operation = controller.refresh(_instance).then((_) {});
        case 'topic feed':
          final controller = TopicFeedController(
            api: api,
            credentials: credentials,
            lifecycle: lifecycle,
            store: Store(),
          );
          addTearDown(controller.dispose);
          operation = controller.load(
            instance: _instance,
            destinationId: 'latest',
            path: '/latest.json',
            incoming: null,
          );
        case 'user summary':
          final controller = UserSummaryController(
            api: api,
            credentials: credentials,
            lifecycle: lifecycle,
          );
          addTearDown(controller.dispose);
          operation = controller.load(_instance);
        case 'preferences':
          final controller = PreferencesController(
            api: api,
            credentials: credentials,
            lifecycle: lifecycle,
          );
          addTearDown(controller.dispose);
          operation = controller.load(_instance);
        case 'directory metadata':
          final controller = UserDirectoryController(
            api: UserDirectoryApi(api, const DiscourseModelCodec.core()),
            credentials: credentials,
            lifecycle: lifecycle,
          );
          addTearDown(controller.dispose);
          operation = controller.load(
            _instance,
            query: const UserDirectoryQuery(),
          );
        case 'group directory':
          final controller = GroupsController(
            api: GroupsApi(api, const DiscourseModelCodec.core()),
            credentials: credentials,
            lifecycle: lifecycle,
          );
          addTearDown(controller.dispose);
          operation = controller.loadDirectory(
            _instance,
            const GroupDirectoryQuery(),
          );
        case 'invites read' || 'invites write':
          final controller = InvitesController(
            api: InvitesApi(api),
            credentials: credentials,
            instance: _instance,
            lifecycle: lifecycle,
          );
          addTearDown(controller.dispose);
          operation = consumer == 'invites read'
              ? controller.load()
              : controller
                    .create(
                      InviteDraft(
                        maxRedemptions: 1,
                        expiresAt: DateTime.utc(2027),
                      ),
                    )
                    .then((_) {});
        case 'do not disturb write':
          final controller = DoNotDisturbController(
            api: api,
            credentials: credentials,
            lifecycle: lifecycle,
            onCommitted: (_, _) => fail('Retired work published.'),
          );
          addTearDown(controller.dispose);
          operation = controller
              .pause(_site, const DoNotDisturbDuration.minutes(30))
              .then((_) {});
      }
      var settled = false;
      final completion = operation.whenComplete(() => settled = true);
      await pumpEventQueue();
      expect(credentials.keyReads, 1);
      expect(
        settled,
        isFalse,
        reason: 'The production consumer must be waiting for admission.',
      );
      expect(sent, isEmpty);
      lifecycle.invalidate(_site);
      await completion.timeout(const Duration(seconds: 1));
      release.complete(http.Response('{}', 200));
      await occupied;
      await pumpEventQueue();
      expect(sent, isEmpty);
      if ([
        'activity totals',
        'topic feed',
        'user summary',
      ].contains(consumer)) {
        expect(credentials.clientReads, 0);
      }
    });
  }
}

final class _Credentials implements ApiCredentialReader {
  int keyReads = 0;
  int clientReads = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    keyReads++;
    return 'key';
  }

  @override
  Future<String> clientId() async {
    clientReads++;
    return 'migration-id';
  }
}
