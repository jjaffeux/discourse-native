import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:timezone/timezone.dart' as tz;

import '../../plugin_api/site_plugin_api.dart';
import '../../shell/markdown_highlight.dart';
import '../../theme/d_icons.dart';
import '../chat/chat_preview_contract.dart';
import 'local_date.dart';
import 'local_date_composer_editor.dart';
import 'local_date_composer_pill.dart';
import 'local_date_composer_sheet.dart';
import 'local_date_environment.dart';
import 'local_date_widget.dart';
import 'local_dates_settings.dart';

export 'local_dates_settings.dart';

const localDateComposerSyntaxKind = ComposerSyntaxKind(
  owner: PluginId('discourse-local-dates'),
  name: 'local-date',
);

class LocalDatesPlugin
    implements
        SitePlugin,
        ChatPreviewContribution,
        BookmarkReminderPlugin,
        ComposerShortcutPlugin,
        ComposerSyntaxPlugin,
        ComposerToolbarPlugin,
        CookedElementPlugin,
        SiteSettingsPlugin<LocalDatesSettings> {
  const LocalDatesPlugin();

  @override
  String get name => 'discourse-local-dates';

  @override
  PluginDataPersistenceCodec<LocalDatesSettings> get siteSettingsCodec =>
      localDatesSettingsPersistenceCodec;

  @override
  LocalDatesSettings readSiteSettings(
    Map<String, dynamic> json,
    String siteUrl,
  ) => LocalDatesSettings.fromSiteSettings(json);

  @override
  String get previewFeatureId => 'discourse-local-dates';

  @override
  ComposerSyntaxKind get composerSyntaxKind => localDateComposerSyntaxKind;

  @override
  ComposerSyntaxPolicy createComposerSyntaxPolicy(
    ComposerSyntaxPolicyContext context,
  ) {
    final initial = context.initialState;
    return LocalDateComposerSyntaxPolicy(
      settings: initial.siteSettings.localDatesSettings,
      accountTimezone: initial.accountTimezone,
      settingsReader: () => context.readState().siteSettings.localDatesSettings,
      accountTimezoneReader: () => context.readState().accountTimezone,
    );
  }

  @override
  Map<ShortcutActivator, VoidCallback> composerShortcuts(
    BuildContext context,
    ComposerEditorHost editor,
  ) {
    final policy = editor.syntaxPolicy<LocalDateComposerSyntaxPolicy>(
      localDateComposerSyntaxKind,
    );
    if (policy == null || !policy.isEnabled(editor)) {
      return const {};
    }
    return {
      const SingleActivator(
        LogicalKeyboardKey.period,
        shift: true,
        meta: true,
      ): () =>
          insertCurrentLocalDate(context, editor, policy),
      const SingleActivator(
        LogicalKeyboardKey.period,
        shift: true,
        control: true,
      ): () =>
          insertCurrentLocalDate(context, editor, policy),
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
    if (!request.siteConfig.localDatesSettings.enabled) {
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
    ComposerEditorHost editor,
  ) {
    final policy = editor.syntaxPolicy<LocalDateComposerSyntaxPolicy>(
      localDateComposerSyntaxKind,
    );
    if (policy == null || editor.loadingBody || !policy.isEnabled(editor)) {
      return const [];
    }
    return [
      ComposerToolbarContribution(
        icon: DIcons.farClock,
        label: defaultTargetPlatform == TargetPlatform.macOS
            ? 'Insert date/time  ⌘⇧.'
            : 'Insert date/time  Ctrl Shift .',
        onInvoke: () =>
            unawaited(openLocalDateComposer(context, editor, policy)),
      ),
    ];
  }
}

/// Local Dates' parser, projection state, validation inputs, and authoring
/// permissions for one open composer.
final class LocalDateComposerSyntaxPolicy implements ComposerSyntaxPolicy {
  const LocalDateComposerSyntaxPolicy({
    this.settings = const LocalDatesSettings(),
    this.accountTimezone,
    this.settingsReader,
    this.accountTimezoneReader,
  });

  final LocalDatesSettings settings;
  final String? accountTimezone;
  final LocalDatesSettings Function()? settingsReader;
  final String? Function()? accountTimezoneReader;

  @override
  ComposerSyntaxKind get kind => localDateComposerSyntaxKind;

  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    for (final block in parseLocalDateComposerBlocks(source))
      LocalDateComposerSyntaxProjection(policy: this, block: block),
  ];

  @override
  Object? get projectionState => accountTimezone;

  @override
  TextInputFormatter? get inputFormatter => null;

  LocalDatesSettings get currentSettings => settingsReader?.call() ?? settings;

  bool isEnabled(ComposerEditorHost editor) =>
      editor.isCurrent && currentSettings.enabled;

  String? get currentAccountTimezone =>
      accountTimezoneReader?.call() ?? accountTimezone;
}

/// One lossless Local Dates occurrence. Core sees only its neutral projection
/// interface; Local Dates retains the parsed block and formatting state.
final class LocalDateComposerSyntaxProjection
    implements ComposerSyntaxProjection, LocalDateComposerProjectionData {
  const LocalDateComposerSyntaxProjection({
    required this.policy,
    required this.block,
  });

  final LocalDateComposerSyntaxPolicy policy;
  final LocalDateComposerBlock block;

  @override
  LocalDateComposerBlock get localDateBlock => block;

  @override
  int get start => block.start;

  @override
  int get end => block.end;

  @override
  String get source => block.source;

  @override
  bool needsRawSource(
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) => localDateBlockNeedsRawSource(
    block: block,
    value: document,
    suppressCollapsedCaret: suppressCollapsedCaret,
  );

  @override
  int caretAfter(String document) => end;

  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) =>
      document.copyWith(
        selection: TextSelection.collapsed(offset: end),
        composing: TextRange.empty,
      );

  @override
  bool get supportsHover => false;

  @override
  bool get protectsAdjacentDelete => false;

  @override
  bool get hidesCursorWhenSelected => false;

  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) =>
      buildCollapsedLocalDateSpans(
        block: block,
        baseStyle: context.baseStyle,
        locale: context.locale,
        accountTimezone: policy.accountTimezone,
        pillKey: context.pillKey,
        highlighted: context.highlighted,
      );

  @override
  Future<void> edit(BuildContext context, ComposerEditorHost editor) =>
      openLocalDateComposer(context, editor, policy, block: block);

  @override
  void remove(BuildContext context, ComposerEditorHost editor) =>
      removeLocalDateComposer(context, editor, block);
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
  ComposerEditorHost editor,
  LocalDateComposerSyntaxPolicy policy, {
  LocalDateComposerBlock? block,
}) async {
  if (!editor.isCurrent || (block == null && !policy.isEnabled(editor))) {
    return;
  }
  final expectedValue = editor.value;
  final expectedDocument = expectedValue.text;
  final expectedSelection = expectedValue.selection;
  final environment = LocalDateEnvironment.instance;
  final accountTimezone = policy.currentAccountTimezone;
  final sourceTimezone = environment.readerTimezone(accountTimezone);
  final location = environment.location(sourceTimezone)!;
  final wallNow = tz.TZDateTime.from(DateTime.now(), location);
  final draft = block == null
      ? LocalDateComposerDraft.newDate(now: wallNow, timezone: sourceTimezone)
      : LocalDateComposerDraft.fromBlock(block);

  bool stillCurrent() =>
      context.mounted &&
      editor.isCurrent &&
      editor.value.text == expectedDocument &&
      (block != null || policy.isEnabled(editor));

  final action = await showLocalDateComposerSheet(
    context: context,
    draft: draft,
    siteFormats: policy.currentSettings.formats,
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
        editor.requestFocus();
        return;
      }
      mutation = block == null
          ? insertVerifiedLocalDate(
              current: editor.value,
              expectedDocument: expectedDocument,
              expectedSelection: expectedSelection,
              markup: replacement,
            )
          : replaceVerifiedLocalDate(
              current: editor.value,
              expectedDocument: expectedDocument,
              expectedBlock: block,
              replacement: replacement,
            );
    case LocalDateComposerSheetActionType.remove:
      if (block == null) return;
      mutation = removeVerifiedLocalDate(
        current: editor.value,
        expectedDocument: expectedDocument,
        expectedBlock: block,
      );
  }
  if (!mutation.applied) {
    _message(context, mutation.message!);
    return;
  }
  if (!editor.commit(expectedValue: expectedValue, value: mutation.value)) {
    _message(
      context,
      'The composer changed while this date was open. Nothing was changed.',
    );
    return;
  }
  editor.requestFocus();
}

void removeLocalDateComposer(
  BuildContext context,
  ComposerEditorHost editor,
  LocalDateComposerBlock block,
) {
  if (!editor.isCurrent) return;
  final expectedValue = editor.value;
  final expectedDocument = expectedValue.text;
  final mutation = removeVerifiedLocalDate(
    current: editor.value,
    expectedDocument: expectedDocument,
    expectedBlock: block,
  );
  if (!mutation.applied) {
    _message(context, mutation.message!);
    return;
  }
  if (!editor.commit(expectedValue: expectedValue, value: mutation.value)) {
    _message(
      context,
      'The composer changed before this date could be removed. Nothing was changed.',
    );
    return;
  }
  editor.requestFocus();
}

void insertCurrentLocalDate(
  BuildContext context,
  ComposerEditorHost editor,
  LocalDateComposerSyntaxPolicy policy, {
  DateTime? now,
}) {
  if (!policy.isEnabled(editor)) return;
  final expectedValue = editor.value;
  final environment = LocalDateEnvironment.instance;
  final timezone = environment.readerTimezone(policy.currentAccountTimezone);
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
    current: expectedValue,
    expectedDocument: expectedValue.text,
    expectedSelection: expectedValue.selection,
    markup: draft.serialize(),
  );
  if (!mutation.applied) return;
  if (!policy.isEnabled(editor) ||
      !editor.commit(expectedValue: expectedValue, value: mutation.value)) {
    return;
  }
  editor.requestFocus();
}

void _message(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}
