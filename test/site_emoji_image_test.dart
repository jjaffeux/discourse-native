import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _host = 'meta.example';
const _site = 'https://$_host';

String _artwork(String emojiSet) => '$_site/images/emoji/$emojiSet/wave.png';

final _defaultArtwork = _artwork(SiteConfig.defaultEmojiSet);

DiscourseInstance _persisted(String emojiSet) =>
    instance(_host).copyWith(config: SiteConfig(emojiSet: emojiSet));

/// Nothing warms a forum behind a sign-in wall, so the rail's own write is the
/// only thing that can announce its snapshot.
DiscourseInstance _behindSignIn(String emojiSet) =>
    _persisted(emojiSet).copyWith(loginRequired: true);

ShellController _shell({
  Iterable<DiscourseInstance> stored = const [],
  FakeDiscourseApi? api,
}) {
  final shell = ShellController(
    instanceStore: FakeInstanceStore(stored),
    api: api ?? FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(shell.dispose);
  return shell;
}

Future<void> _mount(WidgetTester tester, ShellController shell) async {
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: const MaterialApp(
        home: Scaffold(
          body: SiteEmojiImage(
            siteUrl: _site,
            name: 'wave',
            size: 20,
            alt: ':wave:',
          ),
        ),
      ),
    ),
  );
}

String _drawn(WidgetTester tester) =>
    tester.widget<EmojiImage>(find.byType(EmojiImage)).url;

void main() {
  testWidgets('a fetched site config repaints a mounted emoji', (tester) async {
    final configs = {_site: const SiteConfig(emojiSet: 'apple')};
    final shell = _shell(
      stored: [_persisted('google')],
      api: FakeDiscourseApi(siteConfigs: configs),
    );
    await shell.load();
    await _mount(tester, shell);

    await shell.sitePresentation.refreshConfig(_site);
    await tester.pump();
    expect(_drawn(tester), _artwork('apple'));

    configs[_site] = const SiteConfig(emojiSet: 'facebook');
    await shell.sitePresentation.refreshConfig(_site);
    await tester.pump();
    expect(_drawn(tester), _artwork('facebook'));
  });

  testWidgets('a custom emoji arriving repaints a mounted emoji', (
    tester,
  ) async {
    final shell = _shell(
      stored: [instance(_host)],
      api: FakeDiscourseApi(
        customEmojisBySite: const {
          _site: {'wave': 'https://cdn.example/wave.png'},
        },
      ),
    );
    await shell.load();
    await _mount(tester, shell);

    await shell.sitePresentation.ensureCustomEmojis(_site);
    await tester.pump();

    expect(_drawn(tester), 'https://cdn.example/wave.png');
  });

  testWidgets('retiring the session returns a mounted emoji to the snapshot', (
    tester,
  ) async {
    final shell = _shell(
      stored: [_persisted('google')],
      api: FakeDiscourseApi(
        customEmojisBySite: const {
          _site: {'wave': 'https://cdn.example/wave.png'},
        },
      ),
    );
    await shell.load();
    await _mount(tester, shell);
    await shell.sitePresentation.ensureCustomEmojis(_site);
    await tester.pump();
    expect(_drawn(tester), 'https://cdn.example/wave.png');

    shell.lifecycle.invalidate(_site);
    await tester.pump();

    expect(_drawn(tester), _artwork('google'));
  });

  testWidgets('the stored rail arriving repaints an emoji mounted before it', (
    tester,
  ) async {
    final shell = _shell(stored: [_behindSignIn('google')]);
    await _mount(tester, shell);
    expect(_drawn(tester), _defaultArtwork);

    await shell.load();
    await tester.pump();

    expect(_drawn(tester), _artwork('google'));
  });

  testWidgets('adding the forum repaints an emoji that already names it', (
    tester,
  ) async {
    final shell = _shell();
    await shell.load();
    await _mount(tester, shell);
    expect(_drawn(tester), _defaultArtwork);

    await shell.addInstance(_behindSignIn('google'));
    await tester.pump();

    expect(_drawn(tester), _artwork('google'));
  });

  testWidgets('replacing the stored config repaints a mounted emoji', (
    tester,
  ) async {
    final held = _persisted('google');
    final shell = _shell(stored: [held]);
    await shell.load();
    await _mount(tester, shell);
    expect(_drawn(tester), _artwork('google'));

    shell.applyAccountSessionInstance(
      held.copyWith(config: const SiteConfig(emojiSet: 'apple')),
      AccountSessionPhase.restored,
    );
    await tester.pump();

    expect(_drawn(tester), _artwork('apple'));
  });

  testWidgets('removing the forum returns a mounted emoji to the default', (
    tester,
  ) async {
    final held = _behindSignIn('google');
    final shell = _shell(stored: [held]);
    await shell.load();
    await _mount(tester, shell);
    expect(_drawn(tester), _artwork('google'));

    expect(await shell.removeInstance(held), isTrue);
    await tester.pump();

    expect(_drawn(tester), _defaultArtwork);
  });
}
