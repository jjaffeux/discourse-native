import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/policy/policies_api.dart';
import 'package:discourse_native/src/plugins/policy/policy_card.dart';
import 'package:discourse_native/src/plugins/policy/policy_data.dart';
import 'package:discourse_native/src/plugins/policy/policy_definition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _captureKey = GlobalKey();
Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['POLICY_RENDER_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final image =
        await (_captureKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

PolicyUserSummary user(int id) => PolicyUserSummary(
  id: id,
  username: 'member$id',
  avatarTemplate: '/avatars/$id/{size}.png',
);
PolicyPostData data({
  bool accepted = false,
  bool hidden = false,
  bool easy = false,
  int acceptedCount = 2,
  int outstandingCount = 2,
}) => PolicyPostData(
  canAccept: !accepted || easy,
  canRevoke: accepted || easy,
  accepted: accepted,
  revoked: false,
  statistics: hidden
      ? const PolicyStatisticsHidden()
      : PolicyStatisticsVisible(
          acceptedCount: acceptedCount,
          outstandingCount: outstandingCount,
          acceptedPreview: acceptedCount == 0 ? [] : [user(1)],
          outstandingPreview: outstandingCount == 0 ? [] : [user(10)],
        ),
);
final definition = PolicyDefinition(
  audienceGroups: const ['members'],
  version: '3',
);
Future<void> mount(
  WidgetTester tester, {
  PolicyPostData? state,
  PolicyDefinition? policyDefinition,
  PolicyActionCallback? act,
  PolicyParticipantsLoader? load,
  bool canPage = true,
  bool uncertain = false,
  double width = 900,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1000);
  final theme = AppTheme.forBrightness(
    Brightness.light,
    fontFamily: Platform.environment['POLICY_RENDER_DIR'] == null
        ? null
        : 'Open Sans',
  ).copyWith(platform: width < 600 ? TargetPlatform.iOS : TargetPlatform.macOS);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        theme: theme,
        home: DTouchTargets(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: DefaultTextStyle(
                style: theme.textTheme.bodyMedium!,
                child: PolicyCard(
                  body: const Text('A rich policy body'),
                  definition: policyDefinition ?? definition,
                  siteUrl: null,
                  data: state,
                  onAct: act,
                  onLoadParticipants: load,
                  canPage: canPage,
                  uncertain: uncertain,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (Platform.environment['POLICY_RENDER_DIR'] == null) return;
    for (final family in ['Open Sans', 'Roboto']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/OpenSans.ttf'))).load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        ))
        .load();
  });
  for (final width in [402.0, 1000.0]) {
    testWidgets('accepted confirmation and danger action at $width points', (
      tester,
    ) async {
      final actions = <PolicyAction>[];
      await mount(
        tester,
        width: width,
        state: data(accepted: true),
        act: (action) async => actions.add(action),
      );
      expect(find.text('You accepted this policy'), findsOneWidget);
      expect(find.textContaining('Your acceptance applies'), findsNothing);
      final revoke = find.widgetWithText(DButton, 'Revoke acceptance');
      expect(
        tester.widget<DButton>(revoke).variant,
        DButtonVariant.destructive,
      );
      await tester.tap(revoke);
      await tester.pump();
      expect(actions, [PolicyAction.revoke]);
      await _capture(tester, '${width.toInt()}-accepted');
      await tester.tap(
        find.byKey(const ValueKey('policy-participants-outstanding')),
      );
      await tester.pumpAndSettle();
      await _capture(tester, '${width.toInt()}-outstanding');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'static and hidden policies never reveal participant identities',
    (tester) async {
      await mount(tester);
      expect(find.text('A rich policy body'), findsOneWidget);
      expect(find.text('Accept Policy'), findsNothing);
      expect(find.byType(DToggle), findsNothing);
      await mount(tester, state: data(hidden: true));
      expect(find.text('This policy has no possible users'), findsNothing);
      expect(find.byTooltip('member1'), findsNothing);
      expect(find.byType(DToggle), findsNothing);
    },
  );
  testWidgets('visible zero statistics have the upstream empty message', (
    tester,
  ) async {
    await mount(tester, state: data(acceptedCount: 0, outstandingCount: 0));
    expect(find.text('This policy has no possible users'), findsOneWidget);
    expect(find.byType(DToggle), findsNothing);
  });
  testWidgets('inline count switch, offset pagination and deduplication', (
    tester,
  ) async {
    final offsets = <int>[];
    await mount(
      tester,
      state: data(),
      load: (list, offset) async {
        expect(list, PolicyParticipantList.outstanding);
        offsets.add(offset);
        return PolicyUsersPage(users: [user(10), user(11)], receivedCount: 2);
      },
    );
    expect(find.byTooltip('member1'), findsOneWidget);
    expect(find.byTooltip('member10'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('policy-participants-outstanding')),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('member10'), findsOneWidget);
    expect(find.byType(DSheetContent), findsNothing);
    await tester.tap(find.byKey(const ValueKey('policy-participants-more')));
    await tester.pumpAndSettle();
    expect(offsets, [1]);
    expect(find.byTooltip('member10'), findsOneWidget);
    expect(find.byTooltip('member11'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('policy-participants-more')),
      findsNothing,
    );
  });
  testWidgets(
    'actual GET refusal type clears all participant identities immediately',
    (tester) async {
      await mount(
        tester,
        state: data(),
        load: (_, _) async => throw const SiteLookupException(
          SiteLookupFailure.unreachable,
          'forum.example',
          statusCode: 403,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('policy-participants-more')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('member1'), findsNothing);
      expect(find.byType(DToggle), findsNothing);
      expect(find.text('Participant list is unavailable'), findsOneWidget);
    },
  );
  testWidgets('privacy loss drops a pending page instead of restoring names', (
    tester,
  ) async {
    final result = Completer<PolicyUsersPage?>();
    await mount(tester, state: data(), load: (_, _) => result.future);
    await tester.tap(find.byKey(const ValueKey('policy-participants-more')));
    await tester.pump();
    await mount(tester, state: data(hidden: true));
    result.complete(PolicyUsersPage(users: [user(55)], receivedCount: 1));
    await tester.pumpAndSettle();
    expect(find.byTooltip('member55'), findsNothing);
    expect(find.byType(DToggle), findsNothing);
  });
  testWidgets('easy revoke preserves both actions and customized labels', (
    tester,
  ) async {
    await mount(
      tester,
      state: data(easy: true),
      policyDefinition: PolicyDefinition(
        audienceGroups: const ['members'],
        acceptLabel: 'Agree',
        revokeLabel: 'Withdraw',
      ),
      act: (_) async {},
    );
    expect(find.widgetWithText(DButton, 'Agree'), findsOneWidget);
    expect(find.widgetWithText(DButton, 'Withdraw'), findsOneWidget);
  });
  testWidgets('guest previews cannot page and uncertain writes cannot repeat', (
    tester,
  ) async {
    await mount(
      tester,
      state: data(),
      canPage: false,
      load: (_, _) async => throw StateError('must not request'),
      uncertain: true,
      act: (_) async => throw StateError('must not mutate'),
    );
    expect(find.byTooltip('member1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('policy-participants-more')),
      findsNothing,
    );
    expect(
      tester
          .widget<DButton>(find.widgetWithText(DButton, 'Accept Policy'))
          .onPressed,
      isNull,
    );
    expect(find.text('Could not confirm acceptance'), findsOneWidget);
  });
}
