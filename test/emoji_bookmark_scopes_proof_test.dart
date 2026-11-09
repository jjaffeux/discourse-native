import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/shell/destination_bookmark_menu_item.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.example';

/// Counts the resolution itself, so it stays honest whichever owner a widget
/// asks for the URL.
class _CountingConfig extends SiteConfig {
  const _CountingConfig(this.resolutions);

  final ValueNotifier<int> resolutions;

  @override
  String emojiUrl(String name, {required String siteUrl}) {
    resolutions.value++;
    return super.emojiUrl(name, siteUrl: siteUrl);
  }
}

class _CountingShell extends ShellController {
  _CountingShell(SiteConfig config)
    : super(
        instanceStore: FakeInstanceStore([
          instance('meta.example').copyWith(config: config),
        ]),
        api: FakeDiscourseApi(siteConfigs: {_site: config}),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );

  int listeners = 0;

  @override
  void addListener(VoidCallback listener) {
    listeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listeners--;
    super.removeListener(listener);
  }

  void publishWithoutChange() => notifyListeners();
}

void main() {
  testWidgets(
    'a screen of emoji and a bookmark item cost a shell notification nothing',
    (tester) async {
      final resolutions = ValueNotifier(0);
      addTearDown(resolutions.dispose);
      final shell = _CountingShell(_CountingConfig(resolutions));
      addTearDown(shell.dispose);
      await shell.load();

      var bookmarkRebuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (element.widget is DestinationBookmarkMenuItem) bookmarkRebuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);

      await tester.pumpWidget(
        ShellScope(
          controller: shell,
          child: MaterialApp(
            home: Scaffold(
              body: Wrap(
                children: [
                  for (var index = 0; index < 100; index++)
                    SiteEmojiImage(
                      siteUrl: _site,
                      name: 'wave$index',
                      size: 20,
                      alt: '',
                    ),
                  DestinationBookmarkMenuItem(
                    route: ContentRoute.preferences(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(SiteEmojiImage), findsNWidgets(100));
      expect(resolutions.value, greaterThanOrEqualTo(100));

      final shellListeners = shell.listeners;
      resolutions.value = 0;
      bookmarkRebuilds = 0;
      for (var notification = 0; notification < 10; notification++) {
        shell.publishWithoutChange();
        await tester.pump();
      }

      // ignore: avoid_print
      print('PERF_PROOF emoji-bookmark-scopes shell_listeners=$shellListeners');
      // ignore: avoid_print
      print(
        'PERF_PROOF emoji-bookmark-scopes emoji_url_calls=${resolutions.value}',
      );
      // ignore: avoid_print
      print(
        'PERF_PROOF emoji-bookmark-scopes bookmark_rebuilds=$bookmarkRebuilds',
      );

      expect(shellListeners, lessThanOrEqualTo(2));
      expect(resolutions.value, 0);
      expect(bookmarkRebuilds, 0);
    },
  );
}
