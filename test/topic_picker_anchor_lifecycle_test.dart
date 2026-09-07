import 'dart:async';

import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/anchored_picker.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_category_picker.dart';
import 'package:discourse_native/src/shell/topic_tag_picker.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteA = 'https://a.example';
const _siteB = 'https://b.example';
const _design = TopicTag(id: 7, name: 'design');
const _mobile = TopicTag(id: 8, name: 'mobile');
const _categories = [
  TopicCategory(id: 1, name: 'General', color: '888888'),
  TopicCategory(id: 2, name: 'Support', color: '888888'),
  TopicCategory(id: 3, name: 'Phones', color: '888888', parentCategoryId: 2),
  TopicCategory(id: 4, name: 'Tablets', color: '888888', parentCategoryId: 2),
  TopicCategory(id: 5, name: 'Other', color: '888888', parentCategoryId: 1),
];

void main() {
  for (final tags in [false, true]) {
    final kind = tags ? 'tag' : 'category';
    for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
      for (final changeSite in [false, true]) {
        testWidgets(
          '$kind ${platform.name} selection cannot edit a replacement ${changeSite ? 'site' : 'topic'}',
          (tester) async {
            final harness = _Harness(tags: tags, platform: platform);
            await harness.pump(tester);
            final state = tester.state(harness.anchor);
            await harness.open(tester);

            harness.rebuild(() {
              if (changeSite) {
                harness.siteUrl = _siteB;
              } else {
                harness.topicId = 20;
              }
            });
            await tester.pump();
            expect(tester.state(harness.anchor), same(state));
            expect(state.mounted, isTrue);

            await tester.tap(harness.option);
            await tester.pumpAndSettle();

            expect(harness.shell.saves, isEmpty);
            expect(harness.picker, findsNothing);
            await harness.open(tester);
            await tester.tap(harness.option);
            await tester.pumpAndSettle();
            expect(harness.shell.saves.single.siteUrl, harness.siteUrl);
            expect(harness.shell.saves.single.topicId, harness.topicId);
          },
        );
      }
    }

    testWidgets('$kind search cannot query a replacement site', (tester) async {
      final harness = _Harness(tags: tags);
      await harness.pump(tester);
      await harness.open(tester);
      final searches = harness.shell.searches.length;

      harness.rebuild(() {
        harness.siteUrl = _siteB;
        harness.categoryId = 2;
        harness.selectedTags = const [_mobile];
      });
      await tester.pump();
      await tester.enterText(harness.query, 'new search');
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(harness.shell.searches, hasLength(searches));
      expect(harness.shell.saves, isEmpty);
    });

    testWidgets('$kind selection expires after reconnecting the same URL', (
      tester,
    ) async {
      final harness = _Harness(tags: tags);
      await harness.pump(tester);
      final state = tester.state(harness.anchor);
      await harness.open(tester);

      harness.shell.reconnect(_siteA);
      await tester.pump();
      expect(tester.state(harness.anchor), same(state));
      await tester.tap(harness.option);
      await tester.pumpAndSettle();

      expect(harness.shell.saves, isEmpty);
      await harness.open(tester);
      await tester.tap(harness.option);
      await tester.pumpAndSettle();
      expect(harness.shell.saves, hasLength(1));
    });

    testWidgets('$kind delayed search results expire with their account', (
      tester,
    ) async {
      final harness = _Harness(tags: tags);
      final pending = Completer<void>();
      harness.shell.searchGate = pending.future;
      await harness.pump(tester);
      await tester.tap(find.text('Edit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(harness.shell.searches, hasLength(1));

      harness.shell.reconnect(_siteA);
      pending.complete();
      await tester.pumpAndSettle();
      expect(harness.option, findsNothing);

      await tester.enterText(harness.query, 'another');
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(harness.shell.searches, hasLength(1));
    });

    for (final revoked in [false, true]) {
      testWidgets(
        '$kind search failure ${revoked ? 'expires with its account' : 'remains visible for its owner'}',
        (tester) async {
          final harness = _Harness(tags: tags);
          final pending = Completer<void>();
          addTearDown(() {
            if (!pending.isCompleted) pending.complete();
          });
          harness.shell.searchGate = pending.future;
          await harness.pump(tester);
          await tester.tap(find.text('Edit'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(harness.shell.searches, hasLength(1));

          if (revoked) harness.shell.reconnect(_siteA);
          pending.completeError(StateError('Search failed'));
          await tester.pumpAndSettle();

          expect(
            find.text(
              tags ? "Couldn't load tags." : "Couldn't load categories.",
            ),
            revoked ? findsNothing : findsOneWidget,
          );
          if (revoked) {
            await tester.enterText(harness.query, 'another');
            await tester.pumpAndSettle(const Duration(milliseconds: 300));
            expect(harness.shell.searches, hasLength(1));
          }
          expect(harness.shell.saves, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('$kind route can rebuild while its anchor is removed', (
      tester,
    ) async {
      final shell = _PickerShell();
      addTearDown(shell.dispose);
      Widget button(BuildContext context, VoidCallback? open, bool saving) =>
          TextButton(onPressed: open, child: const Text('Edit'));
      Widget host({required bool visible}) => ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: !visible
                  ? const SizedBox.shrink()
                  : tags
                  ? TopicTagMenuAnchor(
                      siteUrl: _siteA,
                      topicId: 10,
                      categoryId: 1,
                      tags: const [_design],
                      enabled: true,
                      builder: button,
                    )
                  : TopicCategoryMenuAnchor(
                      siteUrl: _siteA,
                      topicId: 10,
                      categoryId: 1,
                      enabled: true,
                      builder: button,
                    ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(host(visible: true));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(visible: false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(
          tags
              ? const ValueKey(('topic-tag-picker-option', 'mobile'))
              : const ValueKey('topic-category-option-2'),
        ),
      );
      await tester.pumpAndSettle();
      expect(shell.saves, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '$kind completion cannot clear a newer save or show its error',
      (tester) async {
        final harness = _Harness(tags: tags);
        final oldSave = Completer<String?>();
        final newSave = Completer<String?>();
        harness.shell.saveResult = oldSave.future;
        await harness.pump(tester);
        await harness.open(tester);
        await tester.tap(harness.option);
        await tester.pumpAndSettle();
        expect(harness.saving, isTrue);
        expect(harness.shell.saves.single.topicId, 10);

        harness.rebuild(() => harness.topicId = 20);
        await tester.pump();
        expect(harness.saving, isFalse);
        harness.shell.saveResult = newSave.future;
        await harness.open(tester);
        await tester.tap(harness.option);
        await tester.pumpAndSettle();
        expect(harness.saving, isTrue);
        expect(harness.shell.saves.last.topicId, 20);

        oldSave.complete('Old failure');
        await tester.pumpAndSettle();
        expect(harness.saving, isTrue);
        expect(harness.openMenu, isNull);
        expect(find.text('Old failure'), findsNothing);

        newSave.complete('Please retry');
        await tester.pumpAndSettle();
        expect(harness.saving, isFalse);
        expect(find.text('Please retry'), findsOneWidget);
        harness.shell.saveResult = null;
        await harness.open(tester);
        await tester.tap(harness.option);
        await tester.pumpAndSettle();
        expect(harness.shell.saves, hasLength(3));
        expect(harness.saving, isFalse);
      },
    );

    testWidgets('$kind picker stays retired after switching away and back', (
      tester,
    ) async {
      final harness = _Harness(tags: tags);
      await harness.pump(tester);
      await harness.open(tester);
      harness.rebuild(() => harness.topicId = 20);
      await tester.pump();
      harness.rebuild(() => harness.topicId = 10);
      await tester.pump();

      await tester.tap(harness.option);
      await tester.pumpAndSettle();
      expect(harness.shell.saves, isEmpty);
    });
  }

  for (final replacement in ['topic', 'site', 'account']) {
    for (final oldCompletesFirst in [true, false]) {
      testWidgets(
        'tag preparation is owned across $replacement replacement, old completes ${oldCompletesFirst ? 'first' : 'last'}',
        (tester) async {
          final harness = _Harness(tags: true);
          final oldPreparation = Completer<TopicComposerCapabilities>();
          final newPreparation = Completer<TopicComposerCapabilities>();
          harness.shell.preparation = oldPreparation.future;
          await harness.pump(tester);
          final state = tester.state(harness.anchor);
          await tester.tap(find.text('Edit'));
          await tester.pump();
          expect(harness.picker, findsNothing);

          harness.rebuild(() {
            switch (replacement) {
              case 'topic':
                harness.topicId = 20;
              case 'site':
                harness.siteUrl = _siteB;
              case 'account':
                harness.shell.reconnect(_siteA);
            }
          });
          await tester.pump();
          expect(tester.state(harness.anchor), same(state));
          harness.shell.preparation = newPreparation.future;
          await tester.tap(find.text('Edit'));
          await tester.pump();
          expect(harness.shell.preparations, [_siteA, harness.siteUrl]);

          if (oldCompletesFirst) {
            oldPreparation.complete(
              const TopicComposerCapabilities(canCreateTag: true),
            );
            await tester.pumpAndSettle();
            expect(harness.picker, findsNothing);
          }

          newPreparation.complete(
            const TopicComposerCapabilities(canTagTopics: true),
          );
          await tester.pumpAndSettle();
          if (!oldCompletesFirst) {
            oldPreparation.complete(
              const TopicComposerCapabilities(canCreateTag: true),
            );
            await tester.pumpAndSettle();
          }
          expect(harness.picker, findsOneWidget);
          expect(
            tester
                .widget<TopicTagPicker>(harness.picker)
                .capabilities
                .canCreateTag,
            isFalse,
          );
          // The old finally block must not unlock the current picker.
          harness.openMenu!();
          await tester.pumpAndSettle();
          expect(harness.shell.preparations, hasLength(2));
          expect(harness.shell.searches.single.siteUrl, harness.siteUrl);

          await tester.tap(harness.option);
          await tester.pumpAndSettle();
          expect(harness.shell.saves.single.siteUrl, harness.siteUrl);
          expect(harness.shell.saves.single.topicId, harness.topicId);
        },
      );
    }
  }

  for (final change in ['topic', 'site', 'category', 'tags', 'account']) {
    testWidgets('pending tag preparation cannot reopen after $change changes', (
      tester,
    ) async {
      final harness = _Harness(tags: true);
      final pending = Completer<TopicComposerCapabilities>();
      harness.shell.preparation = pending.future;
      await harness.pump(tester);
      final state = tester.state(harness.anchor);
      await tester.tap(find.text('Edit'));
      await tester.pump();
      harness.rebuild(() {
        switch (change) {
          case 'topic':
            harness.topicId = 20;
          case 'site':
            harness.siteUrl = _siteB;
          case 'category':
            harness.categoryId = 2;
          case 'tags':
            harness.selectedTags = const [_mobile];
          case 'account':
            harness.shell.reconnect(_siteA);
        }
      });
      await tester.pump();
      pending.complete(const TopicComposerCapabilities(canTagTopics: true));
      await tester.pumpAndSettle();

      expect(tester.state(harness.anchor), same(state));
      expect(harness.picker, findsNothing);
      expect(harness.shell.searches, isEmpty);
      harness.shell.preparation = null;
      await harness.open(tester);
      expect(harness.shell.searches.single.categoryId, harness.categoryId);
      expect(harness.shell.searches.single.tags, harness.selectedTags);
    });
  }

  testWidgets('tag preparation rejects mutated tags without a rebuild', (
    tester,
  ) async {
    final harness = _Harness(tags: true);
    final pending = Completer<TopicComposerCapabilities>();
    harness.shell.preparation = pending.future;
    harness.selectedTags = [_design];
    await harness.pump(tester);
    await tester.tap(find.text('Edit'));
    await tester.pump();
    harness.selectedTags.add(_mobile);
    pending.complete(const TopicComposerCapabilities(canTagTopics: true));
    await tester.pumpAndSettle();

    expect(harness.picker, findsNothing);
    expect(harness.shell.searches, isEmpty);
    expect(harness.shell.saves, isEmpty);
  });

  testWidgets('tag navigation is available only to its originating target', (
    tester,
  ) async {
    final harness = _Harness(tags: true);
    await harness.pump(tester);
    await harness.open(tester);
    harness.rebuild(() => harness.siteUrl = _siteB);
    await tester.pump();
    final navigate = find.byKey(
      const ValueKey(('topic-tag-picker-open', 'mobile')),
    );
    await tester.tap(navigate);
    await tester.pumpAndSettle();
    expect(harness.navigations, isEmpty);
    expect(harness.shell.saves, isEmpty);

    await harness.open(tester);
    await tester.tap(
      navigate,
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    await tester.pumpAndSettle();
    expect(harness.navigations, [
      (siteUrl: _siteB, tag: _mobile, newTab: true),
    ]);
    expect(harness.shell.saves, isEmpty);
  });

  testWidgets('category roots, children, removal and path labels still work', (
    tester,
  ) async {
    final harness = _Harness(tags: false);
    harness.rootOnly = true;
    await harness.pump(tester);
    await harness.open(tester);
    expect(
      find.byKey(const ValueKey('topic-category-option-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('topic-category-option-2')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('topic-category-option-3')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('topic-category-option-1')));
    await tester.pumpAndSettle();
    expect(
      harness.shell.saves,
      isEmpty,
      reason: 'Unchanged category is a no-op',
    );

    harness.rebuild(() {
      harness.rootOnly = false;
      harness.categoryId = 3;
      harness.parentCategoryId = 2;
      harness.selectedCategoryId = 3;
      harness.removeCategoryId = 2;
    });
    await tester.pump();
    await harness.open(tester);
    expect(find.byKey(const ValueKey('topic-category-option-1')), findsNothing);
    expect(find.byKey(const ValueKey('topic-category-option-5')), findsNothing);
    expect(find.text('Support / Phones'), findsOneWidget);
    expect(
      tester
          .widget<AnchoredPickerOption>(
            find.byKey(const ValueKey('topic-category-option-3')),
          )
          .selected,
      isTrue,
    );
    expect(find.text('Remove subcategory'), findsOneWidget);
    await tester.tap(find.text('Remove subcategory'));
    await tester.pumpAndSettle();
    expect(harness.shell.saves.single.categoryId, 2);
  });
}

final class _Harness {
  _Harness({required this.tags, this.platform = TargetPlatform.macOS});

  final bool tags;
  final TargetPlatform platform;
  final _PickerShell shell = _PickerShell();
  String siteUrl = _siteA;
  int topicId = 10;
  int? categoryId = 1;
  List<TopicTag> selectedTags = const [_design];
  bool rootOnly = false;
  int? parentCategoryId;
  int? selectedCategoryId;
  int? removeCategoryId;
  late StateSetter rebuild;
  VoidCallback? openMenu;
  bool saving = false;
  final navigations = <({String siteUrl, TopicTag tag, bool newTab})>[];

  Finder get anchor =>
      find.byType(tags ? TopicTagMenuAnchor : TopicCategoryMenuAnchor);
  Finder get picker => find.byType(tags ? TopicTagPicker : TopicCategoryPicker);
  Finder get query => find.byKey(
    ValueKey(tags ? 'topic-tag-picker-query' : 'topic-category-picker-query'),
  );
  Finder get option => find.byKey(
    tags
        ? const ValueKey(('topic-tag-picker-option', 'mobile'))
        : const ValueKey('topic-category-option-2'),
  );

  Future<void> pump(WidgetTester tester) async {
    addTearDown(shell.dispose);
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light.copyWith(platform: platform),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                final navigationSite = siteUrl;
                return Align(
                  alignment: Alignment.topLeft,
                  child: tags
                      ? TopicTagMenuAnchor(
                          siteUrl: siteUrl,
                          topicId: topicId,
                          categoryId: categoryId,
                          tags: selectedTags,
                          enabled: true,
                          onTagNavigate: (tag, {newTab = false}) {
                            navigations.add((
                              siteUrl: navigationSite,
                              tag: tag,
                              newTab: newTab,
                            ));
                          },
                          builder: _button,
                        )
                      : TopicCategoryMenuAnchor(
                          siteUrl: siteUrl,
                          topicId: topicId,
                          categoryId: categoryId,
                          enabled: true,
                          rootOnly: rootOnly,
                          parentCategoryId: parentCategoryId,
                          selectedCategoryId: selectedCategoryId,
                          removeCategoryId: removeCategoryId,
                          removeLabel: 'Remove subcategory',
                          builder: _button,
                        ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(BuildContext context, VoidCallback? open, bool busy) {
    openMenu = open;
    saving = busy;
    return TextButton(onPressed: open, child: Text(busy ? 'Saving' : 'Edit'));
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(picker, findsOneWidget);
  }
}

typedef _Search = ({
  String siteUrl,
  String term,
  int? categoryId,
  List<TopicTag> tags,
});
typedef _Save = ({
  String siteUrl,
  int topicId,
  int? categoryId,
  List<TopicTag> tags,
});

final class _PickerShell extends ShellController {
  _PickerShell()
    : super(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
      );

  final preparations = <String>[];
  final searches = <_Search>[];
  final saves = <_Save>[];
  Future<TopicComposerCapabilities>? preparation;
  Future<void>? searchGate;
  Future<String?>? saveResult;

  void reconnect(String siteUrl) {
    lifecycle.invalidate(siteUrl);
    lifecycle.capture(siteUrl);
    notifyListeners();
  }

  @override
  Future<TopicComposerCapabilities> prepareTopicTagEditor(
    String siteUrl,
  ) async {
    preparations.add(siteUrl);
    return preparation ?? const TopicComposerCapabilities(canTagTopics: true);
  }

  @override
  Future<TopicTagSearch> searchTopicTagsForEditor({
    required String siteUrl,
    required int? categoryId,
    required Iterable<TopicTag> selectedTags,
    required String term,
  }) async {
    searches.add((
      siteUrl: siteUrl,
      term: term,
      categoryId: categoryId,
      tags: List.of(selectedTags),
    ));
    await searchGate;
    return const TopicTagSearch(tags: [_design, _mobile]);
  }

  @override
  Future<List<TopicCategory>> searchTopicCategoriesForEditor({
    required String siteUrl,
    required String term,
  }) async {
    searches.add((siteUrl: siteUrl, term: term, categoryId: null, tags: []));
    await searchGate;
    return _categories;
  }

  @override
  String topicCategoryPathLabel(TopicCategory category, {String? siteUrl}) {
    final parent = _categories.where((c) => c.id == category.parentCategoryId);
    return parent.isEmpty
        ? category.name
        : '${parent.single.name} / ${category.name}';
  }

  @override
  Future<String?> saveTopicCategory({
    required String siteUrl,
    required int topicId,
    required int categoryId,
  }) async {
    saves.add((
      siteUrl: siteUrl,
      topicId: topicId,
      categoryId: categoryId,
      tags: [],
    ));
    return saveResult;
  }

  @override
  Future<String?> updateTopicTagsFromSidebar({
    required String siteUrl,
    required int topicId,
    required Iterable<TopicTag> tags,
  }) async {
    saves.add((
      siteUrl: siteUrl,
      topicId: topicId,
      categoryId: null,
      tags: List.of(tags),
    ));
    return saveResult;
  }
}
