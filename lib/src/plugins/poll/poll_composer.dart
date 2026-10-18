import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'poll.dart';
import 'poll_composer_editor.dart';
import 'poll_composer_pill.dart';
import 'poll_composer_sheet.dart';
import 'poll_data.dart';

ComposerSyntaxKind get pollComposerSyntaxKind => ComposerSyntaxKind(
  owner: const PluginId('poll'),
  name: 'poll',
  label: appL10n.poll,
);

PollComposerSyntaxPolicy createPollComposerSyntaxPolicy(
  ComposerSyntaxPolicyContext context,
) {
  final initial = context.initialState;
  return PollComposerSyntaxPolicy(
    settings: initial.siteSettings.pollSettings,
    settingsReader: () => context.readState().siteSettings.pollSettings,
    freshUserReader: () => context.readState().freshCurrentUser.pollCurrentUser,
    freshUserIsStaffReader: () => context.readState().freshCurrentUserIsStaff,
    editingPollsReader: () => context.readState().editingPost.polls,
  );
}

List<ComposerToolbarContribution> pollComposerToolbar(
  BuildContext context,
  ComposerEditorHost editor,
) {
  final policy = editor.syntaxPolicy<PollComposerSyntaxPolicy>(
    pollComposerSyntaxKind,
  );
  if (policy == null || editor.loadingBody || !policy.canCreate(editor)) {
    return const [];
  }
  return [
    ComposerToolbarContribution(
      icon: DIcons.list,
      label: appL10n.addPoll,
      onInvoke: () => unawaited(openPollComposer(context, editor, policy)),
    ),
  ];
}

final class PollComposerSyntaxPolicy implements ComposerSyntaxPolicy {
  const PollComposerSyntaxPolicy({
    this.settings = const PollSettings(),
    this.settingsReader,
    this.freshUserReader,
    this.freshUserIsStaffReader,
    this.editingPollsReader,
  });

  final PollSettings settings;
  final PollSettings Function()? settingsReader;
  final PollCurrentUser? Function()? freshUserReader;
  final bool Function()? freshUserIsStaffReader;
  final Polls? Function()? editingPollsReader;

  @override
  ComposerSyntaxKind get kind => pollComposerSyntaxKind;

  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    if (currentSettings.enabled)
      for (final block in parsePollComposerBlocks(source))
        PollComposerSyntaxProjection(policy: this, block: block),
  ];

  @override
  Object get projectionState =>
      (currentSettings.enabled, currentSettings.maximumOptions);

  @override
  TextInputFormatter get inputFormatter => const PollComposerInputFormatter();

  PollSettings get currentSettings => settingsReader?.call() ?? settings;

  /// Only a refreshed session may authorize creation.
  bool canCreate(ComposerEditorHost editor) =>
      editor.isCurrent &&
      currentSettings.enabled &&
      freshUserReader?.call()?.canCreatePoll == true;

  bool get freshUserIsStaff => freshUserIsStaffReader?.call() == true;

  int? voterCount(ComposerEditorHost editor, PollComposerBlock block) =>
      editingPollsReader?.call()?[block.name]?.voters;
}

final class PollComposerSyntaxProjection
    implements ComposerBlockSyntaxProjection, PollComposerProjectionData {
  const PollComposerSyntaxProjection({
    required this.policy,
    required this.block,
  });

  final PollComposerSyntaxPolicy policy;
  final PollComposerBlock block;

  @override
  PollComposerBlock get pollBlock => block;

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
  }) => pollBlockNeedsRawSource(
    block: block,
    value: document,
    suppressCollapsedCaret: suppressCollapsedCaret,
  );

  @override
  int caretAfter(String document) {
    if (end >= document.length) return end;
    if (document.codeUnitAt(end) == 0x0D &&
        end + 1 < document.length &&
        document.codeUnitAt(end + 1) == 0x0A) {
      return end + 2;
    }
    return document.codeUnitAt(end) == 0x0A ? end + 1 : end;
  }

  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) {
    final mutation = replaceVerifiedPoll(
      current: document,
      expectedDocument: document.text,
      expectedBlock: block,
      replacement: block.source,
    );
    return mutation.applied ? mutation.value : document;
  }

  @override
  bool get supportsHover => true;

  @override
  bool get protectsAdjacentDelete => true;

  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) =>
      buildCollapsedPollSpans(
        block: block,
        baseStyle: context.baseStyle,
        pillKey: context.pillKey,
        maximumOptions: policy.currentSettings.maximumOptions,
        highlighted: context.highlighted,
        hovered: context.hovered,
        followedByLineBreak: context.followedByLineBreak,
      );

  @override
  Future<void> edit(BuildContext context, ComposerEditorHost editor) =>
      openPollComposer(context, editor, policy, block: block);

  @override
  Future<void> remove(BuildContext context, ComposerEditorHost editor) =>
      removePollComposer(context, editor, policy, block);
}

Future<void> openPollComposer(
  BuildContext context,
  ComposerEditorHost editor,
  PollComposerSyntaxPolicy policy, {
  PollComposerBlock? block,
}) async {
  if (!editor.isCurrent ||
      !editor.isEditing ||
      !policy.currentSettings.enabled ||
      (block == null && !policy.canCreate(editor))) {
    return;
  }

  final expectedValue = editor.value;
  final expectedDocument = expectedValue.text;
  final expectedSelection = expectedValue.selection;
  final settings = policy.currentSettings;
  final draft = block == null
      ? PollComposerDraft.newPoll(
          name: nextPollName(expectedDocument),
          defaultPublic: settings.defaultPublic,
        )
      : PollComposerDraft.fromBlock(
          block,
          maximumOptions: settings.maximumOptions,
        );

  final originalPollNames = {
    for (final original in parsePollComposerBlocks(editor.originalRaw ?? ''))
      original.name,
  };
  final published =
      block != null && editor.isEdit && originalPollNames.contains(block.name);
  final voters = block == null ? null : policy.voterCount(editor, block);

  bool stillCurrent() =>
      context.mounted &&
      editor.isCurrent &&
      editor.isEditing &&
      policy.currentSettings.enabled &&
      editor.value.text == expectedDocument &&
      (block != null || policy.canCreate(editor));

  final action = await showPollComposerSheet(
    context: context,
    draft: draft,
    maximumOptions: settings.maximumOptions,
    isStaff: policy.freshUserIsStaff,
    isPublished: published,
    voterCount: voters,
    isCurrent: stillCurrent,
  );
  if (action == null || !context.mounted) return;
  if (!stillCurrent()) {
    _pollComposerMessage(
      context,
      appL10n.theComposerChangedWhileThisPollWasOpenNothingWasChanged,
    );
    return;
  }

  final PollComposerMutation mutation;
  switch (action.type) {
    case PollComposerSheetActionType.apply:
      final replacement = action.draft!.serialize();
      if (block != null && replacement == block.source) {
        editor.requestFocus();
        return;
      }
      mutation = block == null
          ? insertVerifiedPoll(
              current: editor.value,
              expectedDocument: expectedDocument,
              expectedSelection: expectedSelection,
              markup: replacement,
            )
          : replaceVerifiedPoll(
              current: editor.value,
              expectedDocument: expectedDocument,
              expectedBlock: block,
              replacement: replacement,
            );
    case PollComposerSheetActionType.remove:
      if (block == null) return;
      mutation = removeVerifiedPoll(
        current: editor.value,
        expectedDocument: expectedDocument,
        expectedBlock: block,
      );
  }

  if (!mutation.applied) {
    _pollComposerMessage(context, mutation.message!);
    return;
  }
  if (!editor.commit(expectedValue: expectedValue, value: mutation.value)) {
    _pollComposerMessage(
      context,
      appL10n.theComposerChangedWhileThisPollWasOpenNothingWasChanged,
    );
    return;
  }
  editor.requestFocus();
}

Future<void> removePollComposer(
  BuildContext context,
  ComposerEditorHost editor,
  PollComposerSyntaxPolicy policy,
  PollComposerBlock block,
) async {
  if (!editor.isCurrent ||
      !editor.isEditing ||
      !policy.currentSettings.enabled) {
    return;
  }

  final expectedValue = editor.value;
  final expectedDocument = expectedValue.text;
  final originalPollNames = {
    for (final original in parsePollComposerBlocks(editor.originalRaw ?? ''))
      original.name,
  };
  final published = editor.isEdit && originalPollNames.contains(block.name);
  final voters = policy.voterCount(editor, block);

  bool stillCurrent() =>
      context.mounted &&
      editor.isCurrent &&
      editor.isEditing &&
      policy.currentSettings.enabled &&
      editor.value.text == expectedDocument;

  if (published) {
    final confirmed = await confirmPublishedPollRemoval(
      context,
      voterCount: voters,
    );
    if (!confirmed) return;
  }
  if (!stillCurrent()) {
    if (context.mounted) {
      _pollComposerMessage(
        context,
        appL10n.theComposerChangedBeforeThisPollCouldBeRemovedNothingWas,
      );
    }
    return;
  }
  if (!context.mounted) return;

  final mutation = removeVerifiedPoll(
    current: editor.value,
    expectedDocument: expectedDocument,
    expectedBlock: block,
  );
  if (!mutation.applied) {
    _pollComposerMessage(context, mutation.message!);
    return;
  }
  if (!editor.commit(expectedValue: expectedValue, value: mutation.value)) {
    _pollComposerMessage(
      context,
      appL10n.theComposerChangedBeforeThisPollCouldBeRemovedNothingWas,
    );
    return;
  }
  editor.requestFocus();
}

void _pollComposerMessage(BuildContext context, String message) {
  DToast.show(context, message);
}
