import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/media_pipeline.dart';

void main() {
  final requests = <String>[];
  setUp(() {
    requests.clear();
    installTestMediaPipeline(
      client: MockClient((request) async {
        requests.add(request.url.path);
        return http.Response('', 404);
      }),
    );
  });

  testWidgets('reduced motion requests only static emoji artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Center(
            child: DAnimatedEmoji(
              url: 'https://example.com/static.png',
              animatedUrl: 'https://example.com/animated.avif',
              alt: ':clap:',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, ['/static.png']);
    expect(find.text(':clap:'), findsOneWidget);
  });

  testWidgets('missing animation falls back to the static asset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Center(
          child: DAnimatedEmoji(
            url: 'https://example.com/static.png',
            animatedUrl: 'https://example.com/animated.avif',
            alt: ':clap:',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, containsAll(['/animated.avif', '/static.png']));
    expect(find.text(':clap:'), findsOneWidget);
  });

  testWidgets('overlay stays inside a narrow stage at large text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Center(
            child: SizedBox(
              width: 72,
              height: 180,
              child: DReactionOverlay(
                entries: [
                  DReactionOverlayEntry(
                    id: 1,
                    label: 'a_very_long_username',
                    artwork: SizedBox.square(dimension: 32),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    final overlay = tester.getRect(find.byType(DReactionOverlay));
    final badge = tester.getRect(find.byType(DBadge));
    expect(badge.left, greaterThanOrEqualTo(overlay.left));
    expect(badge.right, lessThanOrEqualTo(overlay.right));
    await tester.pump(const Duration(seconds: 4));
  });
}
