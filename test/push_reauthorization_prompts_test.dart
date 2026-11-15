import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/push_registration.dart';
import 'package:discourse_native/src/data/push_registration_ledger.dart';
import 'package:discourse_native/src/shell/push_reauthorization_prompts.dart';
import 'package:discourse_native/src/shell/push_registration_health.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _site = 'https://meta.discourse.org';

PushAuthorization _authorization(String token) => PushAuthorization(
  registration: PushRegistration(
    clientId: token,
    pushUrl: 'https://push.example/',
  ),
  accepted: true,
);

void main() {
  late String token;
  late List<String> reauthorized;

  PushRegistrationHealth launch() {
    final health = PushRegistrationHealth(
      current: () async =>
          PushRegistration(clientId: token, pushUrl: 'https://push.example/'),
      lastAuthorizedClientId: () async => null,
      accounts: () => const [(siteUrl: _site, username: 'reader')],
    );
    addTearDown(health.dispose);
    return health;
  }

  Future<void> pumpPrompts(WidgetTester tester, PushRegistrationHealth health) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => DToaster(
          child: PushReauthorizationPrompts(
            health: health,
            siteTitle: (_) => 'Meta',
            onReauthorize: (siteUrl) async => reauthorized.add(siteUrl),
            child: child!,
          ),
        ),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
  }

  Future<void> check(WidgetTester tester, PushRegistrationHealth health) async {
    await tester.runAsync(health.check);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    token = 'token-a';
    reauthorized = [];
  });

  testWidgets('a rotated token offers one sign-in and never starts it', (
    tester,
  ) async {
    final health = launch();
    await tester.runAsync(
      () => health.authorized(_site, 'reader', _authorization('token-a')),
    );
    await pumpPrompts(tester, health);
    await check(tester, health);
    expect(find.text('Sign in again'), findsNothing);

    token = 'token-b';
    await check(tester, health);
    await check(tester, health);

    expect(find.text('Push notifications stopped for Meta'), findsOneWidget);
    expect(reauthorized, isEmpty);
    await tester.pump(const Duration(minutes: 5));
    expect(find.text('Sign in again'), findsOneWidget);

    await tester.tap(find.text('Sign in again'));
    await tester.pump();
    expect(reauthorized, [_site]);
  });

  testWidgets('closing the prompt keeps it away on the next launch', (
    tester,
  ) async {
    var health = launch();
    await tester.runAsync(
      () => health.authorized(_site, 'reader', _authorization('token-a')),
    );
    token = 'token-b';
    await pumpPrompts(tester, health);
    await check(tester, health);
    expect(find.text('Sign in again'), findsOneWidget);

    await tester.tap(find.byTooltip('Close toast'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(health.prompts, isEmpty);
    expect(find.text('Sign in again'), findsNothing);

    health = launch();
    await pumpPrompts(tester, health);
    await check(tester, health);
    expect(find.text('Sign in again'), findsNothing);
    expect(
      await tester.runAsync(
        () => const PushRegistrationLedger().dismissed(_site, 'reader'),
      ),
      pushTokenFingerprint('token-b'),
    );
  });
}
