import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:timezone/timezone.dart' as tz;

import '../../plugin_api/chat_preview.dart';
import '../../shell/composer_controller.dart';
import '../../shell/markdown_highlight.dart';
import '../../shell/shell_scope.dart';
import '../../theme/d_icons.dart';
import '../site_plugin_api.dart';
import 'local_date.dart';
import 'local_date_composer_editor.dart';
import 'local_date_composer_pill.dart';
import 'local_date_composer_sheet.dart';
import 'local_date_environment.dart';
import 'local_date_widget.dart';

class LocalDatesPlugin
    implements
        ChatMessagePreviewPlugin,
        BookmarkReminderPlugin,
        ComposerShortcutPlugin,
        ComposerSyntaxPlugin,
        ComposerToolbarPlugin,
        CookedElementPlugin {
  const LocalDatesPlugin();

  @override
  String get name => 'discourse-local-dates';

  @override
  String get previewFeatureId => 'discourse-local-dates';

  @override
  String get syntaxId => 'local-dates';

  @override
  List<Object> parseComposerSyntax(String source) =>
      parseLocalDateComposerBlocks(source);

  @override
  int startOf(Object value) => (value as LocalDateComposerBlock).start;

  @override
  int endOf(Object value) => (value as LocalDateComposerBlock).end;

  @override
  String sourceOf(Object value) => (value as LocalDateComposerBlock).source;

  @override
  int caretAfter(Object value, String document) =>
      (value as LocalDateComposerBlock).end;

  @override
  TextEditingValue moveCaretAfter(Object value, TextEditingValue document) =>
      document.copyWith(
        selection: TextSelection.collapsed(offset: endOf(value)),
        composing: TextRange.empty,
      );

  @override
  bool get supportsHover => false;

  @override
  bool get protectsAdjacentDelete => false;

  @override
  bool get hidesCursorWhenSelected => false;

  @override
  TextInputFormatter? get inputFormatter => null;

  @override
  bool needsRawSource(
    Object value,
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) => localDateBlockNeedsRawSource(
    block: value as LocalDateComposerBlock,
    value: document,
    suppressCollapsedCaret: suppressCollapsedCaret,
  );

  @override
  List<InlineSpan> buildCollapsedSpans({
    required Object value,
    required TextStyle baseStyle,
    required Locale locale,
    required String? accountTimezone,
    required int maximumOptions,
    required GlobalKey pillKey,
    required bool highlighted,
    required bool hovered,
    required bool followedByLineBreak,
  }) => buildCollapsedLocalDateSpans(
    block: value as LocalDateComposerBlock,
    baseStyle: baseStyle,
    locale: locale,
    accountTimezone: accountTimezone,
    pillKey: pillKey,
    highlighted: highlighted,
  );

  @override
  Future<void> editComposerSyntax(
    BuildContext context,
    ComposerController composer,
    Object value,
  ) => openLocalDateComposer(
    context,
    composer,
    block: value as LocalDateComposerBlock,
  );

  @override
  void removeComposerSyntax(
    BuildContext context,
    ComposerController composer,
    Object value,
  ) => removeLocalDateComposer(
    context,
    composer,
    value as LocalDateComposerBlock,
  );

  @override
  Map<ShortcutActivator, VoidCallback> composerShortcuts(
    BuildContext context,
    ComposerController composer,
  ) {
    final controller = ShellScope.maybeRead(context);
    if (controller == null ||
        !controller.siteConfigFor(composer.target.siteUrl).localDatesEnabled) {
      return const {};
    }
    return {
      const SingleActivator(
        LogicalKeyboardKey.period,
        shift: true,
        meta: true,
      ): () =>
          insertCurrentLocalDate(context, composer),
      const SingleActivator(
        LogicalKeyboardKey.period,
        shift: true,
        control: true,
      ): () =>
          insertCurrentLocalDate(context, composer),
    };
  }

  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) =>
      localDateWidgetBuilder(element, siteUrl: siteUrl);

  @override
  DateTime? futureBookmarkReminder(
    String cooked, {
    required String? accountTimezone,
  }) {
    final root = dom.Element.html(cooked);
    final now = DateTime.now();
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    for (final element in root.querySelectorAll('span.discourse-local-date')) {
      final spec = LocalDateSpec.fromDataAttributes(
        element.attributes.map((key, value) => MapEntry('$key', value)),
        fallbackText: element.text,
      );
      final resolved = const LocalDateFormatter().resolve(
        spec,
        locale: locale,
        accountTimezone: accountTimezone,
        now: now,
      );
      if (resolved != null && resolved.source.isAfter(now)) {
        return resolved.source.toUtc();
      }
    }
    return null;
  }

  @override
  ChatPreviewInspection inspect(ChatPreviewRequest request) {
    final syntax = _localDateSyntaxRanges(request.raw);
    if (syntax.isEmpty) return ChatPreviewInspection();
    if (!request.siteConfig.localDatesEnabled) {
      return ChatPreviewInspection(
        blockers: [
          ChatPreviewBlocker('local dates disabled', range: syntax.first),
        ],
      );
    }

    final blocks = parseLocalDateComposerBlocks(request.raw);
    final forwardIncompatible = blocks.where(
      (block) => block.attributes.any(
        (attribute) =>
            !localDateAttributeNames.contains(attribute.normalizedName),
      ),
    );
    if (forwardIncompatible.isNotEmpty) {
      final block = forwardIncompatible.first;
      return ChatPreviewInspection(
        blockers: [
          ChatPreviewBlocker(
            'local date syntax contains unsupported options',
            range: SourceRange(block.start, block.end),
          ),
        ],
      );
    }
    for (final occurrence in syntax) {
      if (!blocks.any((block) => block.start == occurrence.start)) {
        return ChatPreviewInspection(
          blockers: [
            ChatPreviewBlocker(
              'local date syntax is malformed or unsupported',
              range: occurrence,
            ),
          ],
        );
      }
    }
    if (blocks.length != syntax.length) {
      return ChatPreviewInspection(
        blockers: const [
          ChatPreviewBlocker('local date syntax could not be accounted for'),
        ],
      );
    }

    return ChatPreviewInspection(
      claims: [
        for (final block in blocks)
          ChatPreviewClaim(
            range: SourceRange(block.start, block.end),
            node: PluginPreviewNode(
              range: SourceRange(block.start, block.end),
              featureId: previewFeatureId,
              kind: switch (block.kind) {
                LocalDateComposerKind.date => 'date',
                LocalDateComposerKind.range => 'date-range',
              },
              fallbackText: block.source,
            ),
          ),
      ],
    );
  }

  @override
  Widget? buildPreviewNode(BuildContext context, PluginPreviewNode node) {
    if (node.featureId != previewFeatureId) return null;
    final blocks = parseLocalDateComposerBlocks(node.fallbackText);
    if (blocks.length != 1 ||
        blocks.single.start != 0 ||
        blocks.single.end != node.fallbackText.length) {
      return null;
    }
    final block = blocks.single;
    if ((node.kind == 'date') != (block.kind == LocalDateComposerKind.date)) {
      return null;
    }
    return _OptimisticLocalDate(block: block);
  }

  @override
  List<ComposerToolbarContribution> composerToolbar(
    BuildContext context,
    ComposerController composer,
  ) {
    final controller = ShellScope.maybeRead(context);
    if (controller == null ||
        composer.loadingBody ||
        !controller.siteConfigFor(composer.target.siteUrl).localDatesEnabled) {
      return const [];
    }
    return [
      ComposerToolbarContribution(
        icon: DIcons.farClock,
        label: defaultTargetPlatform == TargetPlatform.macOS
            ? 'Insert date/time  ⌘⇧.'
            : 'Insert date/time  Ctrl Shift .',
        onInvoke: () => unawaited(openLocalDateComposer(context, composer)),
      ),
    ];
  }
}

/// The app-bundled Local Dates claim, rendered from the same conservative
/// composer model and formatter as canonical cooked Local Dates.
class _OptimisticLocalDate extends StatelessWidget {
  const _OptimisticLocalDate({required this.block});

  final LocalDateComposerBlock block;

  @override
  Widget build(BuildContext context) {
    final draft = LocalDateComposerDraft.fromBlock(block);
    LocalDateSpec spec({required String date, String? time, String? range}) =>
        LocalDateSpec(
          date: date,
          time: time,
          timezone: draft.timezone,
          range: range,
          format: draft.format,
          calendar: draft.calendar,
          recurring: range == null ? draft.recurring : null,
          countdown: range == null && draft.countdown,
          displayedTimezone: draft.displayedTimezone,
          timezones: draft.previewTimezones,
          fallbackText: block.source,
        );

    final start = spec(
      date: draft.startDate,
      time: draft.startTime,
      range: draft.isRange ? 'from' : null,
    );
    if (!draft.isRange) return LocalDateInline(spec: start);
    final end = spec(date: draft.endDate!, time: draft.endTime, range: 'to');
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        LocalDateInline(spec: start, to: end),
        const Text(' → '),
        LocalDateInline(spec: end, from: start),
      ],
    );
  }
}

List<SourceRange> _localDateSyntaxRanges(String source) {
  final code = CodeRanges.of(scanMarkdown(source));
  return [
    for (final match in _localDateOpening.allMatches(source))
      if (!code.contains(match.start)) SourceRange(match.start, match.end),
  ];
}

final RegExp _localDateOpening = RegExp(
  r'\[(?:date-range|date)(?==|\s|\])',
  caseSensitive: false,
);

Future<void> openLocalDateComposer(
  BuildContext context,
  ComposerController composer, {
  LocalDateComposerBlock? block,
}) async {
  final controller = ShellScope.maybeRead(context);
  if (controller == null ||
      !identical(controller.visibleComposer, composer) ||
      (block == null &&
          !controller
              .siteConfigFor(composer.target.siteUrl)
              .localDatesEnabled)) {
    return;
  }
  final expectedDocument = composer.text.text;
  final expectedSelection = composer.text.selection;
  final environment = LocalDateEnvironment.instance;
  final accountTimezone = controller
      .currentUserFor(composer.target.siteUrl)
      ?.timezone;
  final sourceTimezone = environment.readerTimezone(accountTimezone);
  final location = environment.location(sourceTimezone)!;
  final wallNow = tz.TZDateTime.from(DateTime.now(), location);
  final draft = block == null
      ? LocalDateComposerDraft.newDate(now: wallNow, timezone: sourceTimezone)
      : LocalDateComposerDraft.fromBlock(block);

  bool stillCurrent() =>
      context.mounted &&
      identical(ShellScope.maybeRead(context), controller) &&
      identical(controller.visibleComposer, composer) &&
      composer.text.text == expectedDocument;

  final action = await showLocalDateComposerSheet(
    context: context,
    draft: draft,
    siteFormats: controller
        .siteConfigFor(composer.target.siteUrl)
        .localDateFormats,
    isCurrent: stillCurrent,
  );
  if (action == null || !context.mounted) return;
  if (!stillCurrent()) {
    _message(
      context,
      'The composer changed while this date was open. Nothing was changed.',
    );
    return;
  }
  final LocalDateComposerMutation mutation;
  switch (action.type) {
    case LocalDateComposerSheetActionType.apply:
      final replacement = action.draft!.serialize();
      if (block != null && replacement == block.source) {
        composer.focus.requestFocus();
        return;
      }
      mutation = block == null
          ? insertVerifiedLocalDate(
              current: composer.text.value,
              expectedDocument: expectedDocument,
              expectedSelection: expectedSelection,
              markup: replacement,
            )
          : replaceVerifiedLocalDate(
              current: composer.text.value,
              expectedDocument: expectedDocument,
              expectedBlock: block,
              replacement: replacement,
            );
    case LocalDateComposerSheetActionType.remove:
      if (block == null) return;
      mutation = removeVerifiedLocalDate(
        current: composer.text.value,
        expectedDocument: expectedDocument,
        expectedBlock: block,
      );
  }
  if (!mutation.applied) {
    _message(context, mutation.message!);
    return;
  }
  composer.text.value = mutation.value;
  composer.focus.requestFocus();
}

void removeLocalDateComposer(
  BuildContext context,
  ComposerController composer,
  LocalDateComposerBlock block,
) {
  final controller = ShellScope.maybeRead(context);
  if (controller == null || !identical(controller.visibleComposer, composer)) {
    return;
  }
  final expectedDocument = composer.text.text;
  final mutation = removeVerifiedLocalDate(
    current: composer.text.value,
    expectedDocument: expectedDocument,
    expectedBlock: block,
  );
  if (!mutation.applied) {
    _message(context, mutation.message!);
    return;
  }
  composer.text.value = mutation.value;
  composer.focus.requestFocus();
}

void insertCurrentLocalDate(
  BuildContext context,
  ComposerController composer, {
  DateTime? now,
}) {
  final controller = ShellScope.maybeRead(context);
  if (controller == null ||
      !identical(controller.visibleComposer, composer) ||
      !controller.siteConfigFor(composer.target.siteUrl).localDatesEnabled) {
    return;
  }
  final environment = LocalDateEnvironment.instance;
  final timezone = environment.readerTimezone(
    controller.currentUserFor(composer.target.siteUrl)?.timezone,
  );
  final wall = tz.TZDateTime.from(
    now ?? DateTime.now(),
    environment.location(timezone)!,
  );
  final draft = LocalDateComposerDraft.newDate(now: wall, timezone: timezone)
      .copyWith(
        startTime:
            '${wall.hour.toString().padLeft(2, '0')}:'
            '${wall.minute.toString().padLeft(2, '0')}:'
            '${wall.second.toString().padLeft(2, '0')}',
      );
  final mutation = insertVerifiedLocalDate(
    current: composer.text.value,
    expectedDocument: composer.text.text,
    expectedSelection: composer.text.selection,
    markup: draft.serialize(),
  );
  if (!mutation.applied) return;
  composer.text.value = mutation.value;
  composer.focus.requestFocus();
}

void _message(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}
