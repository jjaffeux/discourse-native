import 'dart:io';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/shell/group_pages_coordinator.dart';
import 'package:discourse_native/src/shell/group_pages_shell_port.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('Groups shell authority stops at the composition adapter', () {
    final coordinator = File(
      'lib/src/shell/group_pages_coordinator.dart',
    ).readAsStringSync();
    final host = File('lib/src/shell/group_pages_host.dart').readAsStringSync();
    final port = File('lib/src/shell/group_pages_port.dart').readAsStringSync();
    final directoryView = File(
      'lib/src/shell/groups_page.dart',
    ).readAsStringSync();
    final detailView = File('lib/src/shell/group_page.dart').readAsStringSync();
    final adapter = File(
      'lib/src/shell/group_pages_shell_port.dart',
    ).readAsStringSync();

    for (final source in [coordinator, host, port, directoryView, detailView]) {
      expect(source, isNot(contains("import 'shell_controller.dart'")));
      expect(source, isNot(contains("import 'shell_scope.dart'")));
    }
    expect(coordinator, isNot(contains('package:flutter/')));
    expect(adapter, contains("import 'shell_controller.dart'"));
  });

  test('shell adapters identify their controller across rebuilds', () {
    final shell = _Shell();
    final otherShell = _Shell();
    addTearDown(shell.dispose);
    addTearDown(otherShell.dispose);

    expect(
      ShellGroupPagesPort(shell).controllerIdentity,
      same(ShellGroupPagesPort(shell).controllerIdentity),
    );
    expect(
      ShellGroupPagesPort(shell).controllerIdentity,
      isNot(same(ShellGroupPagesPort(otherShell).controllerIdentity)),
    );
  });

  for (final navigateBeforeBind in [false, true]) {
    test(
      'directory redirect ${navigateBeforeBind ? 'rejects navigation before the next bind' : 'replaces the current group'}',
      () {
        final shell = _Shell();
        addTearDown(shell.dispose);
        final coordinator = GroupPagesCoordinator();
        addTearDown(coordinator.dispose);
        coordinator.bind(
          ShellGroupPagesPort(shell),
          GroupPagesRouteSnapshot(
            owner: (
              siteUrl: shell.currentInstance.url,
              accountIdentity: shell.currentAccountIdentity,
              tabId: shell.activeTabId,
            ),
            routeId: shell.content.id,
            groupNamespace: true,
            route: shell.content.groupRoute,
            canPopContent: false,
          ),
        );
        final navigation = coordinator.navigationIdentity;
        if (navigateBeforeBind) {
          shell.content = ContentRoute.group(GroupRoute.detail('moderators'));
        }

        coordinator.showDirectory(from: navigation);

        expect(shell.directoryReplacements, navigateBeforeBind ? 0 : 1);
        expect(
          shell.content.groupRoute,
          navigateBeforeBind
              ? GroupRoute.detail('moderators')
              : const GroupRoute.directory(),
        );
      },
    );
  }
}

final class _Shell extends ShellController {
  _Shell()
    : super(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
      );

  ContentRoute content = ContentRoute.group(GroupRoute.detail('staff'));
  int directoryReplacements = 0;

  @override
  DiscourseInstance get currentInstance =>
      const DiscourseInstance(url: 'https://one.example', title: 'Example');

  @override
  String get currentAccountIdentity => 'user:one';

  @override
  String get activeTabId => 'tab-1';

  @override
  ContentRoute get currentContent => content;

  @override
  void replaceCurrentContent(ContentRoute route) {
    directoryReplacements++;
    content = route;
  }
}
