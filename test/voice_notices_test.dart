import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_notices.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('notices arrive once before and after replacing their stream', (
    tester,
  ) async {
    final first = StreamController<VoiceNotice>.broadcast();
    final second = StreamController<VoiceNotice>.broadcast();
    addTearDown(first.close);
    addTearDown(second.close);
    await tester.pumpWidget(
      MaterialApp(
        home: DToaster(
          child: Scaffold(body: VoiceNoticeHost(notices: first.stream)),
        ),
      ),
    );
    first.add(const VoiceNotice("You've been made a speaker."));
    await tester.pump();
    await tester.pump();
    expect(find.byType(Dismissible), findsOneWidget);
    expect(find.text("You've been made a speaker."), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: DToaster(
          child: Scaffold(body: VoiceNoticeHost(notices: second.stream)),
        ),
      ),
    );
    await tester.pump();

    expect(first.hasListener, isFalse);
    second.add(const VoiceNotice('The recording has stopped.'));
    await tester.pump();
    await tester.pump();

    expect(find.text('The recording has stopped.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(first.hasListener, isFalse);
    expect(second.hasListener, isFalse);
  });
}
