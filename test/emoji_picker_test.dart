import 'dart:async';

import 'package:discourse_native/src/data/emoji_cache.dart';
import 'package:discourse_native/src/data/emoji_picker_store.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/plugin_api/emoji_usage.dart';
import 'package:discourse_native/src/plugins/chat/chat_emoji_usage.dart';
import 'package:discourse_native/src/shell/emoji_picker.dart';
import 'package:discourse_native/src/shell/emoji_picker_controller.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _siteUrl = 'https://meta.discourse.org';
final _catalog = SiteEmojiCatalog(
  groups: [
    SiteEmojiGroup(
      id: 'smileys_&_emotion',
      emojis: const [
        SiteEmoji(
          name: 'wave',
          url: 'https://emoji.example/wave.png?v=1',
          tonable: true,
        ),
        SiteEmoji(name: 'smile', url: 'https://emoji.example/smile.png'),
      ],
    ),
    SiteEmojiGroup(
      id: 'my_custom_group',
      emojis: const [
        SiteEmoji(name: 'discourse', url: 'https://emoji.example/custom.png'),
      ],
    ),
    SiteEmojiGroup(
      id: 'default',
      emojis: const [
        SiteEmoji(name: 'party', url: 'https://emoji.example/party.png'),
      ],
    ),
  ],
);

void main() {
  late EmojiCache previousEmojiCache;

  setUp(() {
    previousEmojiCache = EmojiCache.instance;
    EmojiCache.instance = EmojiCache(
      client: MockClient((_) async => http.Response('', 404)),
    );
  });

  tearDown(() {
    EmojiCache.instance.clear();
    EmojiCache.instance = previousEmojiCache;
  });

  testWidgets('desktop opens an anchored popover and returns a toned code', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? selected;
    final store = EmojiPickerStore(persistence: _MemoryPersistence());

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  selected = await showEmojiPicker(
                    context: context,
                    siteUrl: _siteUrl,
                    pickerContext: CoreEmojiUsageContexts.topic,
                    store: store,
                    loadCatalog: ({refresh = false}) async => _catalog,
                    loadSearchAliases: ({refresh = false}) async => const {},
                  );
                },
                child: const Text('Open emoji'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open emoji'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('emoji-picker-desktop-popover')),
      findsOneWidget,
    );
    final search = tester.widget<TextField>(
      find.byKey(const ValueKey('emoji-picker-search')),
    );
    expect(search.focusNode, isNotNull);
    expect(search.focusNode!.hasFocus, isTrue);
    expect(
      find.byKey(const ValueKey('emoji-picker-category-nav-desktop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('emoji-picker-category-my_custom_group')),
      findsOneWidget,
    );
    expect(find.text('my_custom_group'), findsOneWidget);
    expect(find.text('Custom emojis'), findsOneWidget);
    expect(
      tester
          .getTopLeft(
            find.byKey(
              const ValueKey('emoji-picker-category-smileys_&_emotion'),
            ),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(
                const ValueKey('emoji-picker-category-my_custom_group'),
              ),
            )
            .dy,
      ),
    );
    expect(tester.getSize(find.bySemanticsLabel('Insert :wave:')).height, 44);

    await tester.tap(find.byKey(const ValueKey('emoji-picker-tone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('emoji-picker-tone-t4')));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Insert :wave:t4:'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Insert :wave:t4:'));
    await tester.pumpAndSettle();

    expect(selected, 'wave:t4');
    expect(
      find.byKey(const ValueKey('emoji-picker-desktop-popover')),
      findsNothing,
    );
  });

  testWidgets('touch picker uses a keyboard-safe sheet and bottom navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => unawaited(
                showEmojiPicker(
                  context: context,
                  siteUrl: _siteUrl,
                  pickerContext: chatEmojiUsageContext,
                  store: EmojiPickerStore(persistence: _MemoryPersistence()),
                  loadCatalog: ({refresh = false}) async => _catalog,
                  loadSearchAliases: ({refresh = false}) async => const {},
                ),
              ),
              child: const Text('Open emoji'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open emoji'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('emoji-picker-category-nav-touch')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('emoji-picker-desktop-popover')),
      findsNothing,
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    final inset = tester.widget<AnimatedPadding>(
      find.byKey(const ValueKey('shell-sheet-keyboard-inset')),
    );
    expect(inset.padding, const EdgeInsets.only(bottom: 260));

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('desktop picker centers when its live anchor disappears', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final showAnchor = ValueNotifier(true);
    addTearDown(showAnchor.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: showAnchor,
            builder: (context, visible, _) => visible
                ? Align(
                    alignment: Alignment.bottomLeft,
                    child: EmojiPickerAnchor(
                      child: Builder(
                        builder: (anchorContext) => FilledButton(
                          onPressed: () => unawaited(
                            showEmojiPicker(
                              context: anchorContext,
                              anchorContext: anchorContext,
                              siteUrl: _siteUrl,
                              pickerContext: CoreEmojiUsageContexts.topic,
                              store: EmojiPickerStore(
                                persistence: _MemoryPersistence(),
                              ),
                              loadCatalog: ({refresh = false}) async =>
                                  _catalog,
                              loadSearchAliases: ({refresh = false}) async =>
                                  const {},
                            ),
                          ),
                          child: const Text('Open live anchor'),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open live anchor'));
    await tester.pumpAndSettle();
    final picker = find.byKey(const ValueKey('emoji-picker-desktop-popover'));
    expect(tester.getCenter(picker).dx, lessThan(450));

    showAnchor.value = false;
    await tester.pump();
    await tester.pump();
    expect(tester.getCenter(picker), const Offset(450, 350));

    await tester.tapAt(const Offset(890, 10));
    await tester.pumpAndSettle();
  });

  testWidgets('frequent history clears and keyboard selects from search', (
    tester,
  ) async {
    final store = EmojiPickerStore(persistence: _MemoryPersistence());
    await store.trackEmoji(
      siteUrl: _siteUrl,
      context: CoreEmojiUsageContexts.topic,
      emoji: 'smile',
    );
    final controller = EmojiPickerController(
      siteUrl: _siteUrl,
      context: CoreEmojiUsageContexts.topic,
      store: store,
      loadCatalog: ({refresh = false}) async => _catalog,
      loadSearchAliases: ({refresh = false}) async => const {},
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.load();
    String? selected;
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: SizedBox(
            width: 405,
            height: 360,
            child: EmojiPicker(
              controller: controller,
              touch: false,
              onPicked: (code) => selected = code,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Frequently used'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('emoji-picker-clear-history')));
    await tester.pumpAndSettle();
    expect(find.text('Frequently used'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('emoji-picker-search')),
      'wave',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, 'wave');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(dismissed, isTrue);
  });

  testWidgets('search loading uses only the results spinner', (tester) async {
    final controller = EmojiPickerController(
      siteUrl: _siteUrl,
      context: CoreEmojiUsageContexts.topic,
      store: EmojiPickerStore(persistence: _MemoryPersistence()),
      loadCatalog: ({refresh = false}) async => _catalog,
      loadSearchAliases: ({refresh = false}) async => const {},
      searchDebounce: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: SizedBox(
            width: 405,
            height: 360,
            child: EmojiPicker(
              controller: controller,
              touch: false,
              onPicked: (_) {},
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );

    final search = find.byKey(const ValueKey('emoji-picker-search'));
    await tester.enterText(search, 'waiting');
    await tester.pump();

    expect(controller.searchPending, isTrue);
    expect(
      find.descendant(
        of: search,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byKey(const ValueKey('emoji-picker-clear-search')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('emoji-picker-clear-search')));
    await tester.pump();
    expect(controller.searchPending, isFalse);
  });

  testWidgets('grouped keyboard navigation preserves the nearest column', (
    tester,
  ) async {
    final controller = EmojiPickerController(
      siteUrl: _siteUrl,
      context: CoreEmojiUsageContexts.topic,
      store: EmojiPickerStore(persistence: _MemoryPersistence()),
      loadCatalog: ({refresh = false}) async => _catalog,
      loadSearchAliases: ({refresh = false}) async => const {},
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.load();
    String? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: SizedBox(
            width: 405,
            height: 360,
            child: EmojiPicker(
              controller: controller,
              touch: false,
              onPicked: (code) => selected = code,
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    // The first group has two cells while the next has only one. Down from
    // column one lands on that nearest cell instead of becoming a no-op.
    expect(selected, 'discourse');
  });
}

final class _MemoryPersistence implements EmojiPickerPersistence {
  final Map<String, String> values = {};

  @override
  Future<String?> readPreferences({required String siteUrl}) async =>
      values[siteUrl];

  @override
  Future<bool> writePreferences({
    required String siteUrl,
    required String encoded,
  }) async {
    values[siteUrl] = encoded;
    return true;
  }
}
