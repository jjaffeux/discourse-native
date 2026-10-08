import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _oldRow = DiscourseNotification.test(
  id: 1,
  typeId: NotificationTypeId(2),
);
const _newRow = DiscourseNotification.test(
  id: 2,
  typeId: NotificationTypeId(2),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bulk read includes server-defined types and reconciles cached rows',
    () async {
      final api = _BulkApi();
      final shell = await _shell(api);
      addTearDown(shell.dispose);
      await shell.loadNotifications(_site);
      expect(
        shell.notificationsFor(_site).notifications.single.isUnread,
        isTrue,
      );
      await shell.markAllNotificationsRead(_site);
      expect(
        api.markedTypesRead.single,
        contains(const NotificationTypeName('replied')),
      );
      expect(
        api.markedTypesRead.single,
        contains(const NotificationTypeName('custom_server_type')),
      );
      expect(
        shell.notificationsFor(_site).notifications.single.isUnread,
        isFalse,
      );
    },
  );

  test('old bulk read cannot clear a replacement account cache', () async {
    final api = _BulkApi()..bulkGate = Completer<void>();
    final shell = await _shell(api);
    addTearDown(shell.dispose);
    await shell.loadNotifications(_site);
    final reading = shell.markAllNotificationsRead(_site);
    await api.entered.future;
    shell.lifecycle.invalidate(_site);
    shell.clearAccountSessionState(_site);
    api.rows = [_newRow];
    await shell.loadNotifications(_site);
    api.bulkGate!.complete();
    await reading;
    expect(shell.notificationsFor(_site).notifications.single.id, 2);
    expect(shell.notificationsFor(_site).notifications.single.isUnread, isTrue);
  });

  test(
    'failed bulk read leaves cached unread state available to retry',
    () async {
      final api = _BulkApi(bulkFailure: StateError('Offline'));
      final shell = await _shell(api);
      addTearDown(shell.dispose);
      await shell.loadNotifications(_site);
      await expectLater(
        shell.markAllNotificationsRead(_site),
        throwsStateError,
      );
      expect(
        shell.notificationsFor(_site).notifications.single.isUnread,
        isTrue,
      );
    },
  );
}

Future<ShellController> _shell(_BulkApi api) async {
  const user = DiscourseUser(id: 7, username: 'reader');
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user),
    ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  return shell;
}

class _BulkApi extends FakeDiscourseApi {
  _BulkApi({this.bulkFailure})
    : super(
        siteNotificationTypeList: [
          ...CoreNotificationTypes.values,
          const NotificationWireType(101, 'custom_server_type'),
        ],
      );
  final Object? bulkFailure;
  List<DiscourseNotification> rows = [_oldRow];
  Completer<void>? bulkGate;
  final entered = Completer<void>();

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationTypeName> filterByTypes = const [],
    String? clientId,
  }) async => rows;

  @override
  Future<void> markNotificationsRead({
    required String siteUrl,
    required String apiKey,
    required List<NotificationTypeName> types,
    String? clientId,
  }) async {
    final held = rows;
    entered.complete();
    await bulkGate?.future;
    if (bulkFailure case final error?) throw error;
    await super.markNotificationsRead(
      siteUrl: siteUrl,
      apiKey: apiKey,
      types: types,
      clientId: clientId,
    );
    if (identical(rows, held)) {
      rows = [
        for (final row in rows)
          DiscourseNotification.fromJson({...row.toJson(), 'read': true}),
      ];
    }
  }
}
