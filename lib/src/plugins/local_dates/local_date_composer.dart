import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import 'local_date.dart';
import 'local_date_composer_component.dart';
import 'local_date_composer_editor.dart';
import 'local_date_composer_pill.dart';
import 'local_date_composer_sheet.dart';
import 'local_date_environment.dart';
import 'local_dates_settings.dart';

ComposerSyntaxKind get localDateComposerSyntaxKind => ComposerSyntaxKind(
  owner: const PluginId('discourse-local-dates'),
  name: 'local-date',
  label: appL10n.localDate,
);

LocalDateComposerSyntaxPolicy createLocalDateComposerSyntaxPolicy(
  ComposerSyntaxPolicyContext context,
  LocalDateEnvironment environment,
) {
  final initial = context.initialState;
  return LocalDateComposerSyntaxPolicy(
    environment: environment,
    settings: initial.siteSettings.localDatesSettings,
    accountTimezone: initial.accountTimezone,
    settingsReader: () => context.readState().siteSettings.localDatesSettings,
    accountTimezoneReader: () => context.readState().accountTimezone,
  );
}

Map<ShortcutActivator, VoidCallback> localDateComposerShortcuts(
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

List<ComposerToolbarContribution> localDateComposerToolbar(
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
      label: appL10n.insertDateTime,
      shortcut: SingleActivator(
        LogicalKeyboardKey.period,
        shift: true,
        meta:
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.iOS,
        control:
            defaultTargetPlatform != TargetPlatform.macOS &&
            defaultTargetPlatform != TargetPlatform.iOS,
      ),
      onInvoke: () => unawaited(openLocalDateComposer(context, editor, policy)),
    ),
  ];
}

final class LocalDateComposerSyntaxPolicy implements ComposerSyntaxPolicy {
  LocalDateComposerSyntaxPolicy({
    required this.environment,
    this.settings = const LocalDatesSettings(),
    this.accountTimezone,
    this.settingsReader,
    this.accountTimezoneReader,
  }) : formatter = LocalDateFormatter(environment: environment);

  final LocalDateEnvironment environment;
  final LocalDateFormatter formatter;
  final LocalDatesSettings settings;
  final String? accountTimezone;
  final LocalDatesSettings Function()? settingsReader;
  final String? Function()? accountTimezoneReader;

  @override
  ComposerSyntaxKind get kind => localDateComposerSyntaxKind;

  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    for (final block in parseLocalDateComposerBlocks(
      source,
      environment: environment,
    ))
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

ComposerComponent<LocalDateComposerBlock> localDateComposerComponent(
  LocalDateComposerSyntaxPolicy policy,
) => buildLocalDateComposerComponent(
  kind: localDateComposerSyntaxKind,
  environment: policy.environment,
  formatter: policy.formatter,
  accountTimezone: () => policy.currentAccountTimezone,
  onEdit: (context, editor, component) =>
      openLocalDateComposer(context, editor, policy, block: component.value),
  onRemove: (context, editor, component) =>
      removeLocalDateComposer(context, editor, component.value),
);

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
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) =>
      buildCollapsedLocalDateSpans(
        block: block,
        formatter: policy.formatter,
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

Future<void> openLocalDateComposer(
  BuildContext context,
  ComposerEditorHost editor,
  LocalDateComposerSyntaxPolicy policy, {
  LocalDateComposerBlock? block,
}) async {
  if (!editor.isCurrent ||
      !editor.isEditing ||
      (block == null && !policy.isEnabled(editor))) {
    return;
  }
  final expectedValue = editor.value;
  final expectedDocument = expectedValue.text;
  final expectedSelection = expectedValue.selection;
  final environment = policy.environment;
  final accountTimezone = policy.currentAccountTimezone;
  final sourceTimezone = environment.readerTimezone(accountTimezone);
  final location = environment.location(sourceTimezone)!;
  final wallNow = tz.TZDateTime.from(DateTime.now(), location);
  final draft = block == null
      ? LocalDateComposerDraft.newDate(
          now: wallNow,
          timezone: sourceTimezone,
          environment: environment,
        )
      : LocalDateComposerDraft.fromBlock(block);

  bool stillCurrent() =>
      context.mounted &&
      editor.isCurrent &&
      editor.isEditing &&
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
      appL10n.theComposerChangedWhileThisDateWasOpenNothingWasChanged,
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
      appL10n.theComposerChangedWhileThisDateWasOpenNothingWasChanged,
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
  if (!editor.isCurrent || !editor.isEditing) return;
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
      appL10n.theComposerChangedBeforeThisDateCouldBeRemovedNothingWas,
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
  if (!editor.isEditing || !policy.isEnabled(editor)) return;
  final expectedValue = editor.value;
  final environment = policy.environment;
  final timezone = environment.readerTimezone(policy.currentAccountTimezone);
  final wall = tz.TZDateTime.from(
    now ?? DateTime.now(),
    environment.location(timezone)!,
  );
  final draft =
      LocalDateComposerDraft.newDate(
        now: wall,
        timezone: timezone,
        environment: environment,
      ).copyWith(
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
  DToast.show(context, message);
}
