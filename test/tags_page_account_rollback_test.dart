import 'dart:async';

import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/tags_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _oldTag = SidebarTag(
  id: 17,
  name: 'old-private',
  slug: 'old-private',
  pmOnly: true,
);
const _freshTag = SidebarTag(id: 18, name: 'fresh-tag', slug: 'fresh-tag');
const _user = DiscourseUser(
  id: 1,
  username: 'reader',
  displaySidebarTags: true,
  sidebarTags: [_freshTag],
);

void main() {
  for (final pending in [false, true]) {
    for (final disconnect in [false, true]) {
      testWidgets(
        'retained ${pending ? 'pending' : 'loaded'} Tags page reloads after failed ${disconnect ? 'disconnect' : 'reconnect'}',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final site = instance('meta.discourse.org').copyWith(user: _user);
          final store = _FailingStore([site]);
          final api = _HeldTagsApi();
          addTearDown(() {
            if (!api.releaseOld.isCompleted) api.releaseOld.complete();
          });
          final auth = FakeAuthenticator()..keys[_site] = 'original-key';
          await pumpShell(
            tester,
            desktop,
            store: store,
            api: api,
            authenticator: auth,
          );
          final allTags = find.descendant(
            of: find.byType(InstanceSidebar),
            matching: find.text('All tags'),
          );
          await tester.ensureVisible(allTags);
          await tester.tap(allTags);
          await tester.pump();
          await api.oldStarted.future;
          if (!pending) {
            api.releaseOld.complete();
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('tag-directory-tag-17')),
              findsOneWidget,
            );
          }
          final page = find.byType(TagsPage);
          expect(page, findsOneWidget);
          final state = tester.state(page);
          final shell = ShellScope.read(tester.element(page));
          final lease = shell.lifecycle.capture(_site);
          final route = shell.currentContent;

          store.failSignedOut = true;
          if (disconnect) {
            expect(
              await tester.runAsync(() => shell.disconnectInstance(_site)),
              isFalse,
            );
          } else {
            await tester.runAsync(shell.connectCurrentInstance);
          }
          expect(shell.currentInstance?.user, same(_user));
          expect(await auth.apiKeyFor(_site), 'original-key');
          expect(lease.isCurrent, isFalse);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.state(page), same(state));
          expect(shell.currentContent, same(route));
          expect(api.requestKeys, ['original-key', 'original-key']);
          expect(
            find.byKey(const ValueKey('tag-directory-tag-18')),
            findsOneWidget,
          );
          if (!api.releaseOld.isCompleted) api.releaseOld.complete();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            find.byKey(const ValueKey('tag-directory-tag-17')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('tag-directory-tag-18')),
            findsOneWidget,
          );
          expect(shell.tagDirectoryFeedFor(_site).loaded, isTrue);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
      );
    }
  }
}

final class _HeldTagsApi extends FakeDiscourseApi {
  _HeldTagsApi() : super(user: _user, feeds: const {'/latest.json': []});

  final oldStarted = Completer<void>();
  final releaseOld = Completer<void>();
  final requestKeys = <String?>[];

  @override
  Future<List<SidebarTag>> tags({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    requestKeys.add(apiKey);
    if (requestKeys.length == 1) {
      oldStarted.complete();
      await releaseOld.future;
      return const [_oldTag];
    }
    return const [_freshTag];
  }
}

final class _FailingStore extends FakeInstanceStore {
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
