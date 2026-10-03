import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/voice/voice_call_port.dart';
import 'package:discourse_native/src/plugins/voice/voice_call_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_voice_call_port.dart';

void main() {
  testWidgets('room and native PiP visibility preserve a tucked call', (
    tester,
  ) async {
    final identity = Object();
    final port = FakeVoiceCallPort(state: _state(identity: identity));
    addTearDown(port.close);
    await _pump(tester, port);
    final panel = tester
        .widget<DFloatingPanel>(find.byType(DFloatingPanel))
        .controller!;
    panel.tuck();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('floating-panel-restore')),
      findsOneWidget,
    );
    for (final native in [false, true]) {
      port.replaceState(
        _state(identity: identity, roomVisible: !native, pipActive: native),
      );
      await tester.pump();
      expect(find.byType(DFloatingPanel), findsNothing);
      port.replaceState(_state(identity: identity));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('floating-panel-restore')),
        findsOneWidget,
      );
    }
    expect(port.actions, isEmpty);
    await tester.tap(find.byKey(const ValueKey('floating-panel-restore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mute'));
    expect(port.actions, [VoiceCallAction.toggleMuted]);
    panel.tuck();
    await tester.pumpAndSettle();
    port.replaceState(_state(identity: Object(), roomName: 'New call'));
    await tester.pumpAndSettle();
    expect(find.text('New call'), findsOneWidget);
    expect(find.byKey(const ValueKey('floating-panel-restore')), findsNothing);
    port.replaceState(_state(status: VoiceCallPresentationStatus.leaving));
    await tester.pump();
    expect(find.byType(DFloatingPanel), findsNothing);
  });

  testWidgets('mobile preview stays above the dock and fits large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final port = FakeVoiceCallPort(state: _state(mobile: true));
    addTearDown(port.close);
    for (final scale in [1.0, 2.0, 3.0]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(top: 44, bottom: 34),
            ),
            child: Stack(children: [VoiceCallWidget(port: port)]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = tester.getRect(find.byType(DCard));
      expect(card.left, greaterThanOrEqualTo(12));
      expect(card.right, lessThanOrEqualTo(378));
      expect(card.bottom, lessThanOrEqualTo(844 - 34 - 62 * scale));
      expect(tester.takeException(), isNull);
    }
  });

  group('VoiceCallWidget platform availability', () {
    testWidgets('hides the overlay on unsupported platforms', (tester) async {
      final port = FakeVoiceCallPort(
        state: const VoiceCallPortState.unsupported(),
      );
      addTearDown(port.close);

      await _pump(tester, port);

      expect(find.text('Planning'), findsNothing);
      expect(find.byTooltip('Leave room'), findsNothing);
    });

    testWidgets('shows the active call on supported platforms', (tester) async {
      final port = FakeVoiceCallPort(state: _state());
      addTearDown(port.close);

      await _pump(tester, port);

      expect(find.text('Planning'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.byTooltip('Mute'), findsOneWidget);
      expect(find.byTooltip('Leave room'), findsOneWidget);
      expect(find.byType(DToggle), findsOneWidget);
    });
  });

  testWidgets(
    'keeps the call card through joining, connected and failed states',
    (tester) async {
      final port = FakeVoiceCallPort(
        state: _state(status: VoiceCallPresentationStatus.joining),
      );
      addTearDown(port.close);
      await _pump(tester, port);

      for (final status in const [
        VoiceCallPresentationStatus.joining,
        VoiceCallPresentationStatus.connected,
        VoiceCallPresentationStatus.failed,
      ]) {
        port.replaceState(_state(status: status));
        await tester.pump();

        expect(
          find.text('Planning'),
          findsOneWidget,
          reason: 'the $status call should retain the global call card',
        );
        expect(find.byTooltip('Mute'), findsOneWidget);
        expect(find.byTooltip('Leave room'), findsOneWidget);
      }
    },
  );

  testWidgets('shows a recording light while the call is recorded', (
    tester,
  ) async {
    final port = FakeVoiceCallPort(state: _state());
    addTearDown(port.close);
    await _pump(tester, port);
    expect(find.byTooltip('Recording'), findsNothing);

    port.replaceState(_state(recording: true));
    await tester.pump();

    expect(find.text('Recording'), findsOneWidget);
    expect(find.text('Planning'), findsOneWidget);
  });

  testWidgets('renders the port-owned local video preview', (tester) async {
    final port = FakeVoiceCallPort(
      state: _state(
        preview: const ColoredBox(
          key: ValueKey('local-video-preview'),
          color: Colors.green,
        ),
      ),
    );
    addTearDown(port.close);

    await _pump(tester, port);

    expect(find.byKey(const ValueKey('local-video-preview')), findsOneWidget);
  });

  testWidgets('dispatches open, mute, and leave actions through the port', (
    tester,
  ) async {
    final port = FakeVoiceCallPort(state: _state());
    addTearDown(port.close);
    await _pump(tester, port);

    await tester.tap(find.text('Planning'));
    await tester.tap(find.byTooltip('Mute'));
    await tester.tap(find.byTooltip('Leave room'));

    expect(port.actions, const [
      VoiceCallAction.openRoom,
      VoiceCallAction.toggleMuted,
      VoiceCallAction.leave,
    ]);
  });

  testWidgets('updates the microphone action from port state', (tester) async {
    final port = FakeVoiceCallPort(state: _state());
    addTearDown(port.close);
    await _pump(tester, port);

    port.replaceState(_state(muted: true));
    await tester.pump();
    await tester.tap(find.byTooltip('Unmute'));

    expect(port.actions, const [VoiceCallAction.toggleMuted]);
  });

  testWidgets('fails closed when the runtime dependency is unavailable', (
    tester,
  ) async {
    final port = FakeVoiceCallPort(
      state: const VoiceCallPortState(
        supported: true,
        failureMessage: 'Voice calling is unavailable.',
      ),
    );
    addTearDown(port.close);

    await _pump(tester, port);
    expect(find.text('Planning'), findsNothing);
    expect(tester.takeException(), isNull);

    port.replaceState(_state());
    await tester.pump();
    expect(find.text('Planning'), findsOneWidget);
  });

  testWidgets('moves its listener and actions to a replacement port', (
    tester,
  ) async {
    final original = FakeVoiceCallPort(state: _state(roomName: 'Original'));
    final replacement = FakeVoiceCallPort(
      state: _state(roomName: 'Replacement'),
    );
    addTearDown(original.close);
    addTearDown(replacement.close);

    await _pump(tester, original);
    await _pump(tester, replacement);
    original.replaceState(_state(roomName: 'Late original'));
    await tester.pump();

    expect(find.text('Original'), findsNothing);
    expect(find.text('Late original'), findsNothing);
    expect(find.text('Replacement'), findsOneWidget);
    await tester.tap(find.byTooltip('Mute'));
    expect(original.actions, isEmpty);
    expect(replacement.actions, const [VoiceCallAction.toggleMuted]);
  });

  testWidgets('ignores an action completion after widget disposal', (
    tester,
  ) async {
    final completion = Completer<void>();
    final port = FakeVoiceCallPort(
      state: _state(),
      onDispatch: (_) => completion.future,
    );
    addTearDown(port.close);
    await _pump(tester, port);

    await tester.tap(find.byTooltip('Mute'));
    await tester.pumpWidget(const SizedBox.shrink());
    completion.complete();
    await tester.pump();

    expect(port.completedActions, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(WidgetTester tester, VoiceCallPort port) =>
    tester.pumpWidget(
      MaterialApp(
        home: Stack(children: [VoiceCallWidget(port: port)]),
      ),
    );

VoiceCallPortState _state({
  VoiceCallPresentationStatus status = VoiceCallPresentationStatus.connected,
  String roomName = 'Planning',
  bool muted = false,
  bool recording = false,
  bool roomVisible = false,
  bool pipActive = false,
  bool mobile = false,
  Object? identity,
  Widget? preview,
}) => VoiceCallPortState(
  supported: true,
  roomVisible: roomVisible,
  pictureInPictureActive: pipActive,
  usesMobileNavigation: mobile,
  call: VoiceCallPresentation(
    identity: identity,
    roomName: roomName,
    siteName: 'meta',
    participantCount: 2,
    status: status,
    muted: muted,
    recording: recording,
    localVideoPreview: preview,
    failureMessage: status == VoiceCallPresentationStatus.failed
        ? 'The media connection could not be restored.'
        : null,
  ),
);
