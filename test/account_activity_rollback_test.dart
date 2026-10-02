import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/user_activity.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'reader');

enum _Page { activity, bookmarks }

enum _Operation { cancelledReconnect, failedReconnect, failedDisconnect }

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final page in _Page.values) {
    for (final operation in _Operation.values) {
      testWidgets(
        '${page.name} restores its loaded rows after ${operation.name}',
        (tester) async {
          final site = instance('meta.discourse.org').copyWith(user: _user);
          final store = _FailingStore([site]);
          final api = FakeDiscourseApi(
            user: _user,
            feeds: const {'/latest.json': []},
            userActivityItems: const [
              UserActivityItem(
                actionType: 4,
                topicId: 42,
                postNumber: 1,
                title: 'Activity restored',
                slug: 'restored',
                username: 'reader',
                excerpt: '',
              ),
            ],
            bookmarkList: const [
              Bookmark(
                id: 1,
                bookmarkableType: 'Topic',
                path: '/t/restored/42',
                postNumber: 1,
                title: 'Bookmark restored',
              ),
            ],
          );
          final auth = FakeAuthenticator(
            failure: operation == _Operation.cancelledReconnect
                ? UserApiAuthFailure.cancelled
                : null,
          )..keys[_site] = 'old-key';
          await pumpShell(
            tester,
            desktop,
            instances: [site],
            store: store,
            api: api,
            authenticator: auth,
          );
          final shell = ShellScope.read(
            tester.element(find.byType(MainContent).first),
          );
          if (page == _Page.activity) {
            shell.openUserActivity(_site);
          } else {
            shell.selectDestination(
              const SidebarDestination(
                id: 'user-bookmarks',
                label: 'Bookmarks',
                icon: DIcons.bookmark,
              ),
            );
          }
          await tester.pumpAndSettle();
          expect(
            find.byType(
              page == _Page.activity ? UserActivityView : BookmarkSection,
            ),
            findsOneWidget,
          );
          final loader = find.byWidgetPredicate(
            (widget) =>
                widget.runtimeType.toString() == '_AccountActivityRequestView',
          );
          final state = tester.state(loader);
          final route = shell.currentContent?.id;
          final lease = shell.lifecycle.capture(_site);
          final title = page == _Page.activity
              ? 'Activity restored'
              : 'Bookmark restored';
          expect(find.text(title), findsOneWidget);
          int requests() => page == _Page.activity
              ? api.userActivityRequests.length
              : api.bookmarkListRequests.length;
          expect(requests(), 1);
          bool loaded() => page == _Page.activity
              ? shell.accountActivity.userActivityFor(_site).loaded
              : shell.accountActivity.bookmarkListFor(_site).loaded;
          expect(loaded(), isTrue);

          // A storage failure can finish before the next frame, so the actual
          // account coordinator restores this route while its loader stays mounted.
          store.failSignedOut = operation != _Operation.cancelledReconnect;
          if (operation == _Operation.failedDisconnect) {
            expect(
              await tester.runAsync(() => shell.disconnectInstance(_site)),
              isFalse,
            );
          } else {
            await tester.runAsync(shell.connectCurrentInstance);
          }
          expect(shell.currentInstance?.user?.id, _user.id);
          expect(shell.currentContent?.id, route);
          expect(lease.isCurrent, operation == _Operation.cancelledReconnect);
          expect(loaded(), operation == _Operation.cancelledReconnect);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.state(loader), same(state));
          expect(
            requests(),
            operation == _Operation.cancelledReconnect ? 1 : 2,
          );
          expect(find.text(title), findsOneWidget);
          expect(loaded(), isTrue);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
      );
    }
  }
}

class _FailingStore extends FakeInstanceStore {
  _FailingStore(super.instances);
  bool failSignedOut = false;

  @override
  Future<void> save(List<DiscourseInstance> instances) {
    if (failSignedOut &&
        instances.any((site) => site.url == _site && site.user == null)) {
      return Future.error(StateError('Account snapshot storage unavailable'));
    }
    return super.save(instances);
  }
}
