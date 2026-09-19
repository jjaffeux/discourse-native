import 'package:discourse_cooking/discourse_cooking.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/discourse_events/discourse_events_module.dart';
import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/poll_card.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

Widget _body(Widget child, {PluginRegistry? registry}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: SingleChildScrollView(
      child: PluginRegistryScope(
        registry: registry ?? PluginRegistry.empty,
        child: child,
      ),
    ),
  ),
);

String _semanticsTree(WidgetTester tester) => tester
    .binding
    .renderViews
    .single
    .owner!
    .semanticsOwner!
    .rootSemanticsNode!
    .toStringDeep();

Future<void> _withSemantics(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final handle = tester.ensureSemantics();
  try {
    await body();
  } finally {
    handle.dispose();
  }
}

void main() {
  late String cooked;
  late String title;
  late String optionHtml;
  setUpAll(() async {
    final service = OfflineCookingService();
    try {
      final result = await service.cook(
        CookingRequest(
          raw:
              '[poll]\n# Visible [spoiler]SECRET TITLE[/spoiler]\n* A\n* B\n[/poll]',
          configuration: CookingConfiguration(
            modules: [
              CookingModule(id: 'poll', owner: 'poll', version: '1'),
              CookingModule.spoiler,
            ],
          ),
          snapshot: CookingSnapshot(
            siteId: 'test-site',
            accountId: 'test-account',
            pluginContext: {
              'poll': {
                'settings': {'poll_enabled': true},
              },
            },
          ),
        ),
      );
      expect(result.failure, isNull);
      cooked = result.html;
      title = html_parser
          .parseFragment(cooked)
          .querySelector('.poll-title')!
          .innerHtml;
      expect(title, 'Visible <span class="spoiler">SECRET TITLE</span>');
      final optionResult = await service.cook(
        CookingRequest(
          raw:
              '[poll]\n* Visible [spoiler]SECRET OPTION[/spoiler]\n* B\n[/poll]',
          configuration: CookingConfiguration(
            modules: [
              CookingModule(id: 'poll', owner: 'poll', version: '1'),
              CookingModule.spoiler,
            ],
          ),
          snapshot: CookingSnapshot(
            siteId: 'test-site',
            accountId: 'test-account',
            pluginContext: {
              'poll': {
                'settings': {'poll_enabled': true},
              },
            },
          ),
        ),
      );
      expect(optionResult.failure, isNull);
      optionHtml = html_parser
          .parseFragment(optionResult.html)
          .querySelector('li[data-poll-option-id]')!
          .innerHtml;
      expect(optionHtml, 'Visible <span class="spoiler">SECRET OPTION</span>');
    } finally {
      await service.dispose();
    }
  });

  for (final canonical in [false, true]) {
    final kind = canonical ? 'canonical' : 'fallback';
    testWidgets(
      '$kind poll title enters semantics only after spoiler reveal',
      (tester) => _withSemantics(tester, () async {
        final card = canonical
            ? PollCard(
                poll: Poll(
                  name: 'poll',
                  title: title,
                  options: const [
                    PollOption(id: 'a', html: 'A'),
                    PollOption(id: 'b', html: 'B'),
                  ],
                ),
                signedIn: true,
                archived: false,
              )
            : PollFallbackCard.fromCooked(
                html_parser.parseFragment(cooked).querySelector('.poll')!,
              );
        await tester.pumpWidget(_body(card));
        await tester.pumpAndSettle();
        expect(_semanticsTree(tester), contains('Visible'));
        expect(_semanticsTree(tester), isNot(contains('SECRET TITLE')));
        expect(
          find.bySemanticsLabel(canonical ? 'Poll' : 'Poll, read only'),
          findsOneWidget,
        );
        await tester.tap(find.text('Spoiler'));
        await tester.pumpAndSettle();
        expect(_semanticsTree(tester), contains('SECRET TITLE'));
        await tester.tap(find.text('Spoiler'));
        await tester.pumpAndSettle();
        expect(_semanticsTree(tester), isNot(contains('SECRET TITLE')));
        await tester.pumpWidget(const SizedBox.shrink());
      }),
    );

    testWidgets(
      '$kind cached poll title never exposes hidden event text to semantics',
      (tester) => _withSemantics(tester, () async {
        final installed = PluginInstaller.install(
          const PluginManifest([discourseEventsModule]),
        );
        addTearDown(installed.close);
        const hiddenTitle =
            'Visible <span class="hidden">PRIVATE SPAN</span><div class="hidden">PRIVATE DIV</div>';
        final card = canonical
            ? const PollCard(
                poll: Poll(name: 'poll', title: hiddenTitle),
                signedIn: false,
                archived: false,
              )
            : const PollFallbackCard(title: hiddenTitle, options: ['A', 'B']);
        await tester.pumpWidget(_body(card, registry: installed.registry));
        await tester.pumpAndSettle();
        expect(_semanticsTree(tester), contains('Visible'));
        expect(_semanticsTree(tester), isNot(contains('PRIVATE')));
        expect(
          find.textContaining('PRIVATE', findRichText: true),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }),
    );
  }

  for (final multiple in [false, true]) {
    testWidgets(
      '${multiple ? 'multiple' : 'single'} choice disclosure is separate from voting and safe labels',
      (tester) => _withSemantics(tester, () async {
        final installed = PluginInstaller.install(
          const PluginManifest([discourseEventsModule]),
        );
        addTearDown(installed.close);
        var votes = 0;
        await tester.pumpWidget(
          _body(
            PollCard(
              poll: Poll(
                name: 'poll',
                type: multiple ? PollType.multiple : PollType.regular,
                voters: 2,
                options: [
                  PollOption(
                    id: 'a',
                    html:
                        '$optionHtml<span class="hidden">PRIVATE OPTION</span>',
                    votes: 2,
                  ),
                  const PollOption(id: 'b', html: 'B', votes: 0),
                ],
              ),
              signedIn: true,
              archived: false,
              onVote: (_, _) => votes++,
            ),
            registry: installed.registry,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          _semanticsTree(tester),
          contains('Visible Spoiler, 2 votes, 100 percent'),
        );
        expect(_semanticsTree(tester), isNot(contains('SECRET OPTION')));
        expect(_semanticsTree(tester), isNot(contains('PRIVATE OPTION')));
        await tester.tap(find.text('Spoiler'));
        await tester.pumpAndSettle();
        expect(_semanticsTree(tester), contains('SECRET OPTION'));
        expect(_semanticsTree(tester), isNot(contains('PRIVATE OPTION')));
        expect(votes, 0);
        if (multiple) {
          expect(
            tester.widget<DCheckbox>(find.byType(DCheckbox).first).value,
            isFalse,
          );
        }
        await tester.tap(find.text('Spoiler'));
        await tester.pumpAndSettle();
        expect(_semanticsTree(tester), isNot(contains('SECRET OPTION')));
        final choice = multiple
            ? find.byType(DCheckbox).first
            : find.byType(DRadioGroupItem<String>).first;
        final pointerTarget = multiple
            ? choice
            : find
                  .descendant(
                    of: choice,
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is DecoratedBox &&
                          widget.decoration is BoxDecoration &&
                          (widget.decoration as BoxDecoration).shape ==
                              BoxShape.circle,
                    ),
                  )
                  .first;
        await tester.tap(pointerTarget);
        await tester.pumpAndSettle();
        if (multiple) {
          expect(tester.widget<DCheckbox>(choice).value, isTrue);
          expect(votes, 0);
        } else {
          expect(votes, 1);
          tester
              .widget<RawRadio<String>>(
                find.descendant(
                  of: choice,
                  matching: find.byType(RawRadio<String>),
                ),
              )
              .focusNode
              .requestFocus();
        }
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        if (multiple) {
          expect(tester.widget<DCheckbox>(choice).value, isFalse);
          expect(votes, 0);
        } else {
          expect(votes, 2);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }),
    );
  }

  for (final tied in [false, true]) {
    testWidgets(
      '${tied ? 'tied' : 'winning'} ranked labels preserve concealed candidate privacy',
      (tester) => _withSemantics(tester, () async {
        final installed = PluginInstaller.install(
          const PluginManifest([discourseEventsModule]),
        );
        addTearDown(installed.close);
        final html = '$optionHtml<span class="hidden">PRIVATE CANDIDATE</span>';
        final candidate = PollRankedCandidate(digest: 'a', html: html);
        await tester.pumpWidget(
          _body(
            PollCard(
              poll: Poll(
                name: 'poll',
                type: PollType.rankedChoice,
                options: [PollOption(id: 'a', html: html)],
                rankedChoiceOutcome: RankedChoiceOutcome(
                  winner: !tied,
                  tied: tied,
                  winningCandidate: tied ? null : candidate,
                  tiedCandidates: tied ? [candidate] : const [],
                ),
              ),
              signedIn: false,
              archived: false,
            ),
            registry: installed.registry,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          _semanticsTree(tester),
          contains('${tied ? 'Tie between' : 'Winner'} Visible Spoiler'),
        );
        expect(_semanticsTree(tester), isNot(contains('SECRET OPTION')));
        expect(_semanticsTree(tester), isNot(contains('PRIVATE CANDIDATE')));
        expect(find.text('Spoiler'), findsNWidgets(2));
        await tester.tap(find.text('Spoiler').first);
        await tester.pumpAndSettle();
        expect(_semanticsTree(tester), contains('SECRET OPTION'));
        expect(_semanticsTree(tester), isNot(contains('PRIVATE CANDIDATE')));
        await tester.tap(find.text('Spoiler').first);
        await tester.pumpAndSettle();
        expect(_semanticsTree(tester), isNot(contains('SECRET OPTION')));
        await tester.tap(find.text('Spoiler').last);
        await tester.pumpAndSettle();
        expect(_semanticsTree(tester), contains('SECRET OPTION'));
        await tester.pumpWidget(const SizedBox.shrink());
      }),
    );
  }

  testWidgets(
    'initially open details do not leave body text in cached option labels',
    (tester) => _withSemantics(tester, () async {
      await tester.pumpWidget(
        _body(
          const PollCard(
            poll: Poll(
              name: 'poll',
              type: PollType.multiple,
              options: [
                PollOption(
                  id: 'a',
                  html:
                      '<details open><summary>More</summary>SECRET DETAIL</details>',
                ),
              ],
            ),
            signedIn: false,
            archived: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<DCheckbox>(find.byType(DCheckbox)).semanticLabel,
        'More',
      );
      expect(_semanticsTree(tester), contains('SECRET DETAIL'));
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(_semanticsTree(tester), isNot(contains('SECRET DETAIL')));
      expect(
        tester.widget<DCheckbox>(find.byType(DCheckbox)).semanticLabel,
        'More',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }),
  );
}
