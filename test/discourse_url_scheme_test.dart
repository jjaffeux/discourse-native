import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'support/fakes.dart';

const _iosInfoPlists = [
  'ios/Runner/Info.plist',
  'profiles/full/ios/Runner/Info.plist',
];

const _macosInfoPlists = [
  'macos/Runner/Info.plist',
  'profiles/full/macos/Runner/Info.plist',
];

void main() {
  group('Info.plist', () {
    test('every Apple runner registers the sign-in callback scheme', () {
      for (final path in [..._iosInfoPlists, ..._macosInfoPlists]) {
        final urlTypes = _plistDict(_infoPlist(path))['CFBundleURLTypes'];

        expect(urlTypes, isNotNull, reason: path);
        expect(
          [
            for (final type in urlTypes!.childElements)
              ...?_plistDict(
                type,
              )['CFBundleURLSchemes']?.childElements.map((e) => e.innerText),
          ],
          contains(UserApiKeyProtocol.redirectScheme),
          reason: path,
        );
      }
    });

    test('iOS runners keep opened URLs out of the Flutter navigator', () {
      for (final path in _iosInfoPlists) {
        expect(
          _plistDict(_infoPlist(path))['FlutterDeepLinkingEnabled']?.name.local,
          'false',
          reason:
              '$path: the engine pushes every URL opened in a registered '
              'scheme as a route unless this is false.',
        );
      }
    });
  });

  group('a route pushed by the platform', () {
    for (final location in [
      'discourse://auth_redirect/',
      'discourse://auth_redirect?payload=abc',
    ]) {
      testWidgets('is claimed and leaves one shell: $location', (tester) async {
        await tester.pumpWidget(
          DiscourseApp(
            store: FakeInstanceStore([
              const DiscourseInstance(
                url: 'https://one.example',
                title: 'One',
                user: DiscourseUser(username: 'me'),
              ),
            ]),
            api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
            authenticator: FakeAuthenticator(),
            drafts: FakeDraftStore(),
            forumTabs: FakeForumTabStore(),
            trackers: FakeSiteTracker.reset(),
            updater: FakeUpdater(),
            updateStore: FakeUpdateStore(),
            initialRootMode: ShellRootMode.forum,
          ),
        );
        await tester.pumpAndSettle();
        final shells = find.byType(AdaptiveShell, skipOffstage: false);
        expect(shells, findsOneWidget);

        final handled = await _openUrl(tester, location);
        await tester.pumpAndSettle();

        expect(handled, isTrue);
        expect(tester.takeException(), isNull);
        expect(shells, findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });
}

/// Delivers an opened URL the way the iOS engine does: a
/// `pushRouteInformation` call on the navigation channel carrying only the
/// location, answered with whether the framework handled it.
Future<Object?> _openUrl(WidgetTester tester, String location) async {
  const codec = JSONMethodCodec();
  final reply = Completer<ByteData?>();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    codec.encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': location}),
    ),
    reply.complete,
  );
  return codec.decodeEnvelope((await reply.future)!);
}

XmlElement _infoPlist(String path) => XmlDocument.parse(
  File(path).readAsStringSync(),
).rootElement.childElements.single;

/// A plist `<dict>` alternates `<key>` elements with their values; comments
/// between them are not elements.
Map<String, XmlElement> _plistDict(XmlElement dict) {
  final entries = dict.childElements.toList();
  return {
    for (var i = 0; i + 1 < entries.length; i += 2)
      entries[i].innerText: entries[i + 1],
  };
}
