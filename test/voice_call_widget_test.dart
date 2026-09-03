import 'dart:async';

import 'package:discourse_native/src/plugins/voice/voice_call_port.dart';
import 'package:discourse_native/src/plugins/voice/voice_call_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_voice_call_port.dart';

void main() {
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
      expect(find.text('meta · 2 present'), findsOneWidget);
      expect(find.byTooltip('Mute'), findsOneWidget);
      expect(find.byTooltip('Leave room'), findsOneWidget);
    });
  });

  testWidgets(
    'keeps the current call card through joining, connected, leaving, and failed states',
    (tester) async {
      final port = FakeVoiceCallPort(
        state: _state(status: VoiceCallPresentationStatus.joining),
      );
      addTearDown(port.close);
      await _pump(tester, port);

      for (final status in const [
        VoiceCallPresentationStatus.joining,
        VoiceCallPresentationStatus.connected,
        VoiceCallPresentationStatus.leaving,
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

    expect(find.byTooltip('Recording'), findsOneWidget);
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
  Widget? preview,
}) => VoiceCallPortState(
  supported: true,
  call: VoiceCallPresentation(
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
