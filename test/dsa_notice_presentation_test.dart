import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/dsa_notices_api.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/shell/dsa_notice_form.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/post_flag_editor.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/native_ui_evidence.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://forum.example';
const _user = DiscourseUser(
  id: 4,
  username: 'member',
  name: 'Reporter',
  canUseDsaAccountEmail: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.discourse.native/notification_opens'),
          (_) async => null,
        );
  });
  setUpAll(() async {
    final fonts =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    for (final entry in fonts.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
  });
  testWidgets('phone notice keeps its submission in the visible sheet footer', (
    tester,
  ) async {
    await prepareNativeUiEvidence(tester);
    final connection = _Connection();
    final api = _Api(connection);
    await pumpShell(
      tester,
      phone,
      api: api,
      instances: const [
        DiscourseInstance(
          url: _site,
          title: 'Forum',
          config: SiteConfig(dsaReportingEnabled: true),
          user: DiscourseUser(
            id: 4,
            username: 'member',
            name: 'Reporter',
            canUseDsaAccountEmail: true,
          ),
        ),
      ],
      authenticator: FakeAuthenticator()..keys[_site] = 'key',
    );
    final context = tester.element(find.byType(MainContent).first);
    final appearance = ShellScope.read(context).forumSettings;
    await appearance.setShared(
      appearance.shared.copyWith(interfaceFont: ForumFont.openSans),
    );
    await tester.pumpAndSettle();
    unawaited(
      showIllegalContentReport(
        context: context,
        siteUrl: _site,
        contentUrl: '$_site/t/example/10/2',
        title: 'Example',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DsaNoticeForm), findsOneWidget);
    expect(find.byKey(const ValueKey('dsa-email')), findsNothing);
    final submit = find.byKey(const ValueKey('dsa-submit'));
    expect(tester.getRect(submit).bottom, lessThanOrEqualTo(phone.height));
    await tester.enterText(
      find.byKey(const ValueKey('dsa-explanation')),
      'This content contains an illegal threat against a named person.',
    );
    if (tester.testTextInput.isRegistered) {
      tester.testTextInput.hide();
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    await tester.pumpAndSettle();
    final declaration = find.byKey(const ValueKey('dsa-declaration'));
    await tester.ensureVisible(declaration);
    await tester.pumpAndSettle();
    await tester.tap(declaration);
    await tester.pumpAndSettle();
    expect(submit.hitTestable(), findsOneWidget);
    await _capture(tester, 'dsa-phone-report');
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Report reference: DSA-PHONE'), findsOneWidget);
    expect(connection.submissions, 1);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'phone ordinary flag shares a visible footer and keeps its endpoint',
    (tester) async {
      await prepareNativeUiEvidence(tester);
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var submitted = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(
            platform: TargetPlatform.iOS,
            textTheme: AppTheme.light.textTheme.apply(fontFamily: 'Open Sans'),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => DButton(
                label: const Text('Open'),
                onPressed: () => showFlagEditor(
                  context: context,
                  siteUrl: _site,
                  targetUsername: 'author',
                  flagTypes: const [
                    PostFlagType(
                      id: 7,
                      nameKey: 'spam',
                      name: 'Spam',
                      description: 'Advertising',
                      appliesTo: ['Chat::Message'],
                    ),
                  ],
                  minimumMessageLength: 10,
                  save: (type, {message}) async {
                    submitted = true;
                    return null;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final submit = find.byKey(const ValueKey('post-flag-submit'));
      expect(submit.hitTestable(), findsOneWidget);
      expect(tester.getRect(submit).bottom, lessThanOrEqualTo(phone.height));
      await _capture(tester, 'ordinary-phone-flag');
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(submitted, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['NATIVE_UI_EVIDENCE_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final builder = ui.SceneBuilder();
    view.debugLayer!.addToScene(builder);
    final scene = builder.build();
    final image = await scene.toImage(
      view.size.width.round(),
      view.size.height.round(),
    );
    scene.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(directory).createSync(recursive: true);
    File('$directory/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _Api extends FakeDiscourseApi {
  _Api(this.connection) : super(user: _user, feeds: const {'/latest.json': []});
  final DsaNoticeConnection connection;
  @override
  DsaNoticeConnection dsaNoticeConnection({
    required String siteUrl,
    required String? apiKey,
    String? clientId,
  }) => connection;
}

class _Connection implements DsaNoticeConnection {
  int submissions = 0;
  @override
  Future<String> requestVerification(String email) async => 'a' * 64;
  @override
  Future<void> verifyEmail(String email, String token, String code) async {}
  @override
  Future<String> submit(Map<String, Object?> notice, {String? token}) async {
    submissions++;
    return 'DSA-PHONE';
  }

  @override
  void dispose() {}
}
