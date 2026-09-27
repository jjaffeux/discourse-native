import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _meta = 'https://meta.discourse.org';
const _team = 'https://team.discourse.org';

// macOS and Linux expose a node's label to the screen reader, never its
// tooltip, so a rail forum must be named by its label on both.
const _desktopBridges = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.linux,
});

Future<FakeInstanceStore> _pumpRail(WidgetTester tester) async {
  const user = DiscourseUser(id: 7, username: 'reader');
  final store = FakeInstanceStore([
    const DiscourseInstance(
      url: _meta,
      title: 'Meta',
      iconUrl: '$_meta/logo.svg',
      user: user,
    ),
    const DiscourseInstance(
      url: _team,
      title: 'Team',
      iconUrl: '$_team/logo.svg',
    ),
  ]);
  await pumpShell(
    tester,
    desktop,
    store: store,
    authenticator: FakeAuthenticator()..keys[_meta] = 'meta-key',
    api: FakeDiscourseApi(
      user: user,
      totals: const NotificationTotals(unreadNotifications: 7),
    ),
    mediaClient: MockClient(
      (_) async => http.Response(
        '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
        '<path d="M0 0h24v24H0z"/></svg>',
        200,
        headers: {'content-type': 'image/svg+xml'},
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

Finder _railItem(String url) =>
    find.byKey(ValueKey('instance-rail-tooltip-$url'));

List<String?> _customActions(SemanticsNode node) => [
  for (final id
      in node.getSemanticsData().customSemanticsActionIds ?? const <int>[])
    CustomSemanticsAction.getAction(id)?.label,
];

void main() {
  testWidgets('a rail forum is a named button that says which is current', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpRail(tester);

      // Both forums draw their site icon, not the monogram fallback.
      for (final url in [_meta, _team]) {
        expect(
          find.descendant(
            of: _railItem(url),
            matching: find.byType(SvgPicture),
          ),
          findsOneWidget,
        );
      }

      final meta = tester.getSemantics(_railItem(_meta));
      expect(
        meta,
        isSemantics(isButton: true, isSelected: true, isImage: false),
      );
      final label = meta.getSemanticsData().label;
      expect(label, startsWith('Meta'));
      expect(label, contains('7 unread notifications'));
      expect(
        _customActions(meta),
        unorderedEquals(['Show forum actions', 'Move down']),
      );

      final team = tester.getSemantics(_railItem(_team));
      expect(
        team,
        isSemantics(
          label: 'Team',
          isButton: true,
          isSelected: false,
          isImage: false,
        ),
      );
      expect(
        _customActions(team),
        unorderedEquals(['Show forum actions', 'Move up']),
      );
    } finally {
      semantics.dispose();
    }
  }, variant: _desktopBridges);

  testWidgets('a rail forum moves through its semantics action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final store = await _pumpRail(tester);

      final meta = tester.getSemantics(_railItem(_meta));
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.customAction,
          nodeId: meta.id,
          viewId: tester.view.viewId,
          arguments: CustomSemanticsAction.getIdentifier(
            const CustomSemanticsAction(label: 'Move down'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect((await store.load()).map((site) => site.url), [_team, _meta]);
      expect(
        _customActions(tester.getSemantics(_railItem(_meta))),
        unorderedEquals(['Show forum actions', 'Move up']),
      );
    } finally {
      semantics.dispose();
    }
  }, variant: _desktopBridges);

  testWidgets('All forums says when it is the current view', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpRail(tester);
      final all = find.byKey(const ValueKey('aggregate-rail-button'));

      expect(
        tester.getSemantics(all),
        isSemantics(label: 'All forums', isButton: true, isSelected: false),
      );

      await tester.tap(all);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(all),
        isSemantics(label: 'All forums', isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(_railItem(_meta)),
        isSemantics(isButton: true, isSelected: false),
      );
    } finally {
      semantics.dispose();
    }
  }, variant: _desktopBridges);
}
