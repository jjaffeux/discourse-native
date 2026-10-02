import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/voice/voice_agent_invite.dart';
import 'package:discourse_native/src/plugins/voice/voice_agents.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'voice_agent_controller_test.dart' show AgentHarness, site;

Future<void> openDialog(
  WidgetTester tester,
  VoiceAgentInvitation invitation, {
  ValueNotifier<bool>? available,
  bool settle = true,
  double textScale = 1,
}) async {
  final availability = available ?? ValueNotifier(true);
  if (available == null) addTearDown(availability.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => DButton(
            label: const Text('Open'),
            onPressed: () => showDDialog<void>(
              context: context,
              builder: (context, dialog) => VoiceAgentInviteDialog(
                invitation: invitation,
                availability: availability,
                available: () => availability.value,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets(
    'narrow large-text manual chooser keeps fields and actions usable',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final invitation = VoiceAgentInvitation(
        isCurrent: () => true,
        load: (_) async => [],
        invite: (_) async => true,
      );
      await openDialog(tester, invitation, textScale: 1.5);
      expect(
        find
            .text(
              'Ensure your LiveKit agent is deployed before adding it to this call.',
            )
            .hitTestable(),
        findsOneWidget,
      );
      await tester.enterText(find.byType(EditableText), 'assistant');
      await tester.tap(find.text('Send invitation'));
      await tester.pumpAndSettle();
      expect(find.text('Agent invitation sent.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account replacement withdraws an open chooser and reloads the action grant',
    (tester) async {
      final h = AgentHarness();
      addTearDown(h.close);
      await h.controller.ensureLoaded(site);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceAgentInviteAction(
              controller: h.controller,
              siteUrl: site,
              roomId: 7,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invite agent'));
      await tester.pumpAndSettle();
      h.requests.delegate.forget(site);
      h.transport.responses['GET /site.json'] = {};
      await h.controller.refreshAgentPermission(site);
      await tester.pumpAndSettle();
      expect(find.text('Send invitation'), findsNothing);
      expect(
        find.text('This invitation is no longer available.'),
        findsOneWidget,
      );
      expect(h.transport.writes, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Invite agent'), findsNothing);
    },
  );

  testWidgets(
    'authorized action opens chooser and submits the selected dispatch name',
    (tester) async {
      final h = AgentHarness();
      addTearDown(h.close);
      await h.controller.ensureLoaded(site);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceAgentInviteAction(
              controller: h.controller,
              siteUrl: site,
              roomId: 7,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Invite agent'), findsOneWidget);
      await tester.tap(find.text('Invite agent'));
      await tester.pumpAndSettle();
      expect(find.byType(DInput), findsNothing);
      await tester.tap(find.text('Choose an agent'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('assistant').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send invitation'));
      await tester.pumpAndSettle();
      expect(h.transport.writes.single.body, {'agent_name': 'assistant'});
      expect(find.text('Agent invitation sent.'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'missing authenticated grant hides action even with a public LiveKit room',
    (tester) async {
      final h = AgentHarness();
      addTearDown(h.close);
      h.transport.responses['GET /site.json'] = {
        'admin': true,
        'voice_livekit_agent_enabled': true,
      };
      await h.controller.ensureLoaded(site);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceAgentInviteAction(
              controller: h.controller,
              siteUrl: site,
              roomId: 7,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Invite agent'), findsNothing);
      expect(h.transport.requests.map((r) => r.path), [
        '/voice/rooms.json',
        '/site.json',
      ]);
    },
  );

  for (final unavailable in [false, true]) {
    testWidgets(
      '${unavailable ? 'unavailable' : 'empty'} catalogue supports manual names, validation and refresh',
      (tester) async {
        var names = <String>[];
        var fail = unavailable;
        final refreshes = <bool>[];
        final sent = <String>[];
        final invitation = VoiceAgentInvitation(
          isCurrent: () => true,
          load: (refresh) async {
            refreshes.add(refresh);
            if (fail) throw StateError('offline');
            return names;
          },
          invite: (name) async {
            sent.add(name);
            return true;
          },
        );
        await openDialog(tester, invitation);
        expect(find.byType(DInput), findsOneWidget);
        if (unavailable) {
          expect(
            find.text("Couldn't load deployed agents. You can type a name."),
            findsOneWidget,
          );
        }
        await tester.tap(find.text('Send invitation'));
        await tester.pumpAndSettle();
        expect(find.text('Enter an agent name.'), findsOneWidget);
        expect(sent, isEmpty);
        await tester.enterText(find.byType(EditableText), 'x' * 257);
        await tester.tap(find.text('Send invitation'));
        await tester.pumpAndSettle();
        expect(find.text('Use 256 characters or fewer.'), findsOneWidget);
        names = ['assistant'];
        fail = false;
        await tester.tap(find.text('Refresh agents'));
        await tester.pumpAndSettle();
        expect(refreshes, [false, true]);
        expect(find.byType(DInput), findsNothing);
        await tester.tap(find.text('Type a name'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(EditableText), ' custom ');
        await tester.tap(find.text('Send invitation'));
        await tester.pumpAndSettle();
        expect(sent, ['custom']);
        expect(find.text('Agent invitation sent.'), findsOneWidget);
      },
    );
  }

  testWidgets('manual fallback submits without a deployed catalogue', (
    tester,
  ) async {
    final sent = <String>[];
    final invitation = VoiceAgentInvitation(
      isCurrent: () => true,
      load: (_) async => [],
      invite: (name) async {
        sent.add(name);
        return true;
      },
    );
    await openDialog(tester, invitation);
    await tester.enterText(find.byType(EditableText), ' dev-worker ');
    await tester.tap(find.text('Send invitation'));
    await tester.pumpAndSettle();
    expect(sent, ['dev-worker']);
  });

  testWidgets(
    'loading and sending disable duplicate actions and show errors for retry',
    (tester) async {
      final catalogue = Completer<List<String>>();
      final dispatch = Completer<bool>();
      var submits = 0;
      final invitation = VoiceAgentInvitation(
        isCurrent: () => true,
        load: (_) => catalogue.future,
        invite: (_) {
          submits++;
          return dispatch.future;
        },
      );
      // Hold the catalogue request while checking disabled actions.
      await openDialog(tester, invitation, settle: false);
      expect(
        tester
            .widget<DButton>(find.widgetWithText(DButton, 'Refresh agents'))
            .loading,
        isFalse,
      );
      expect(
        tester
            .widget<DButton>(find.widgetWithText(DButton, 'Send invitation'))
            .onPressed,
        isNull,
      );
      catalogue.complete([]);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'assistant');
      await tester.tap(find.text('Send invitation'));
      await tester.pump();
      expect(
        tester
            .widget<DButton>(find.widgetWithText(DButton, 'Send invitation'))
            .loading,
        isTrue,
      );
      await tester.tap(find.text('Send invitation'));
      expect(submits, 1);
      dispatch.completeError(StateError('failed'));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't invite the agent. Try again."),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DButton>(find.widgetWithText(DButton, 'Send invitation'))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('revoked permission withdraws submission from an open chooser', (
    tester,
  ) async {
    final available = ValueNotifier(true);
    addTearDown(available.dispose);
    var submits = 0;
    final invitation = VoiceAgentInvitation(
      isCurrent: () => true,
      load: (_) async => [],
      invite: (_) async {
        submits++;
        return true;
      },
    );
    await openDialog(tester, invitation, available: available);
    available.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Send invitation'), findsNothing);
    expect(
      find.text('This invitation is no longer available.'),
      findsOneWidget,
    );
    expect(submits, 0);
  });
}
