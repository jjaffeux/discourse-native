import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/emoji_picker_store.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/plugin_api/emoji_usage.dart';
import 'package:discourse_native/src/shell/emoji_picker.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/media_pipeline.dart';

const _site = 'https://meta.discourse.org';
const _other = 'https://other.example';
final _catalog = SiteEmojiCatalog(
  groups: [
    SiteEmojiGroup(
      id: 'smileys_&_emotion',
      emojis: const [
        SiteEmoji(
          name: 'wave',
          url: 'https://emoji.example/wave.png',
          tonable: true,
        ),
        SiteEmoji(name: 'heart', url: 'https://emoji.example/heart.png'),
      ],
    ),
  ],
);
String _key(String site) =>
    SharedPreferencesEmojiPickerPersistence.keys.of(site);
String _encoded(String tone) => jsonEncode({
  'version': EmojiPickerStore.formatVersion,
  'tone': tone,
  'history': {
    CoreEmojiUsageContexts.topic.id: ['wave'],
  },
});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      _key(_site): _encoded('t4'),
      _key(_other): _encoded('t5'),
    });
    installTestMediaPipeline(
      client: MockClient((_) async => http.Response('', 404)),
    );
  });

  testWidgets(
    're-added forum picker ignores a read begun before durable removal',
    (tester) async {
      final fixture = await _fixture();
      addTearDown(fixture.shell.dispose);
      await fixture.store.ensureLoaded(siteUrl: _other);
      fixture.persistence.heldRead = Completer<void>();
      final oldLoad = fixture.store.ensureLoaded(
        siteUrl: 'HTTPS://META.DISCOURSE.ORG:443/',
      );
      await fixture.persistence.readStarted.future;

      final removal = fixture.shell.removeInstance(
        fixture.shell.instanceFor(_site)!,
      );
      await tester.pump();
      expect(await removal, isTrue);
      await tester.pump();
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey(_key(_site)), isFalse);
      expect(
        await fixture.shell.addInstance(instance('meta.discourse.org')),
        isTrue,
      );
      final freshLoad = fixture.store.ensureLoaded(siteUrl: _site);
      fixture.persistence.heldRead!.complete();
      await Future.wait([oldLoad, freshLoad]);

      await tester.pumpWidget(fixture.host());
      await _openPicker(tester);
      expect(find.bySemanticsLabel('Insert :wave:'), findsOneWidget);
      expect(fixture.store.skinToneFor(siteUrl: _site), EmojiSkinTone.neutral);
      expect(
        fixture.store.favoriteEmojiCodesFor(
          siteUrl: _site,
          context: CoreEmojiUsageContexts.topic,
          catalog: _catalog,
        ),
        isEmpty,
      );
      fixture.expectOtherUnchanged();
      await tester.tap(find.byKey(const ValueKey('emoji-picker-tone')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('emoji-picker-tone-t3')));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Insert :wave:t3:'));
      await tester.pumpAndSettle();
      await fixture.lastPickWrite;
      expect(fixture.store.skinToneFor(siteUrl: _site), EmojiSkinTone.t3);
      final saved =
          jsonDecode(preferences.getString(_key(_site))!)
              as Map<String, dynamic>;
      expect(saved['tone'], 't3');
      expect(saved['history'], {
        CoreEmojiUsageContexts.topic.id: ['wave:t3'],
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a queued Native emoji pick cannot recreate a removed forum preference key',
    (tester) async {
      final fixture = await _fixture();
      addTearDown(fixture.shell.dispose);
      await fixture.store.ensureLoaded(siteUrl: _other);
      await tester.pumpWidget(fixture.host());
      await _openPicker(tester);
      fixture.persistence.heldWriteAcknowledgement = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('emoji-picker-tone')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('emoji-picker-tone-t6')));
      await tester.pumpAndSettle();
      await fixture.persistence.writeStarted.future;
      // The tone already reached real storage, but its acknowledgement is held.
      // The picker returns this code and queues its history behind that write.
      await tester.tap(find.bySemanticsLabel('Insert :heart:'));
      await tester.pumpAndSettle();
      expect(fixture.lastPickWrite, isNotNull);
      final removal = fixture.shell.removeInstance(
        fixture.shell.instanceFor(_site)!,
      );
      await tester.pump();
      expect(await removal, isTrue);
      await tester.pump();
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey(_key(_site)), isFalse);
      fixture.persistence.heldWriteAcknowledgement!.complete();
      await fixture.lastPickWrite;

      expect(preferences.containsKey(_key(_site)), isFalse);
      fixture.expectOtherUnchanged();
      expect(
        await fixture.shell.addInstance(instance('meta.discourse.org')),
        isTrue,
      );
      await _openPicker(tester);
      expect(find.bySemanticsLabel('Insert :wave:'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Insert :heart:'));
      await tester.pumpAndSettle();
      await fixture.lastPickWrite;
      final saved =
          jsonDecode(preferences.getString(_key(_site))!)
              as Map<String, dynamic>;
      expect(saved['tone'], 'neutral');
      expect(saved['history'], {
        CoreEmojiUsageContexts.topic.id: ['heart'],
      });
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.text('Open emoji'));
  await tester.pumpAndSettle();
}

Future<_Fixture> _fixture() async {
  final persistence = _HeldSharedPreferencesPersistence();
  final store = EmojiPickerStore(persistence: persistence);
  final shell = ShellController(
    emojiPickerStore: store,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org'),
      instance('other.example'),
    ]),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  return _Fixture(shell, store, persistence);
}

class _Fixture {
  _Fixture(this.shell, this.store, this.persistence);
  final ShellController shell;
  final EmojiPickerStore store;
  final _HeldSharedPreferencesPersistence persistence;
  Future<void>? lastPickWrite;

  Widget host() => ShellScope(
    controller: shell,
    child: MaterialApp(
      theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => DButton(
              label: const Text('Open emoji'),
              onPressed: () async {
                final code = await showEmojiPicker(
                  context: context,
                  siteUrl: _site,
                  pickerContext: CoreEmojiUsageContexts.topic,
                  store: store,
                  loadCatalog: ({refresh = false}) async => _catalog,
                  loadSearchAliases: ({refresh = false}) async => const {},
                );
                if (code != null) {
                  lastPickWrite = store.trackEmoji(
                    siteUrl: _site,
                    context: CoreEmojiUsageContexts.topic,
                    emoji: code,
                  );
                  await lastPickWrite;
                }
              },
            ),
          ),
        ),
      ),
    ),
  );

  void expectOtherUnchanged() {
    expect(store.skinToneFor(siteUrl: _other), EmojiSkinTone.t5);
    expect(
      store.favoriteEmojiCodesFor(
        siteUrl: _other,
        context: CoreEmojiUsageContexts.topic,
        catalog: _catalog,
      ),
      ['wave'],
    );
  }
}

/// Hold operation completion while using real SharedPreferences keys and
/// the public shell's durable removal. A held write already committed before
/// its delayed acknowledgement, so only the queued pre-removal pick can revive it.
final class _HeldSharedPreferencesPersistence
    implements EmojiPickerPersistence {
  final delegate = const SharedPreferencesEmojiPickerPersistence();
  Completer<void>? heldRead;
  Completer<void>? heldWriteAcknowledgement;
  final readStarted = Completer<void>();
  final writeStarted = Completer<void>();
  bool _readHeld = false;
  bool _writeHeld = false;

  @override
  Future<String?> readPreferences({required String siteUrl}) async {
    final value = await delegate.readPreferences(siteUrl: siteUrl);
    if (siteUrl == _site && heldRead != null && !_readHeld) {
      _readHeld = true;
      readStarted.complete();
      await heldRead!.future;
    }
    return value;
  }

  @override
  Future<bool> writePreferences({
    required String siteUrl,
    required String encoded,
  }) async {
    final saved = await delegate.writePreferences(
      siteUrl: siteUrl,
      encoded: encoded,
    );
    if (siteUrl == _site && heldWriteAcknowledgement != null && !_writeHeld) {
      _writeHeld = true;
      writeStarted.complete();
      await heldWriteAcknowledgement!.future;
    }
    return saved;
  }
}
