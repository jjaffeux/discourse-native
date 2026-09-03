import 'dart:async';

import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_notices.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('each notice is shown once as a snackbar', (tester) async {
    final notices = StreamController<VoiceNotice>.broadcast();
    addTearDown(notices.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VoiceNoticeHost(notices: notices.stream)),
      ),
    );

    notices.add(
      const VoiceNotice(
        "You've been made a speaker.",
        siteUrl: 'https://voice.example.com',
        roomId: 7,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text("You've been made a speaker."), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(notices.hasListener, isFalse);
  });

  testWidgets('a replaced stream is followed and the old one released', (
    tester,
  ) async {
    final first = StreamController<VoiceNotice>.broadcast();
    final second = StreamController<VoiceNotice>.broadcast();
    addTearDown(first.close);
    addTearDown(second.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VoiceNoticeHost(notices: first.stream)),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VoiceNoticeHost(notices: second.stream)),
      ),
    );
    await tester.pump();

    expect(first.hasListener, isFalse);
    second.add(
      const VoiceNotice(
        'The recording has stopped.',
        siteUrl: 'https://voice.example.com',
        roomId: 7,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('The recording has stopped.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
