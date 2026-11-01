import 'dart:async';
import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'policy_builder.dart';
import 'policy_data.dart';
import 'policy_definition.dart';
import 'policy_groups.dart';

const policyComposerKind = ComposerSyntaxKind(
  owner: PluginId('discourse-policy'),
  name: 'policy',
);
const policyGroupsService = PluginServiceKey<PolicyGroups>(
  owner: PluginId('discourse-policy'),
  name: 'groups',
);

class PolicyComposerPolicy implements ComposerSyntaxPolicy {
  const PolicyComposerPolicy(this.context);
  final ComposerSyntaxPolicyContext context;
  @override
  ComposerSyntaxKind get kind => policyComposerKind;
  @override
  Object? get projectionState => (
    context.readState().siteSettings.policySettings?.enabled,
    context.readState().freshCurrentUser.policyCurrentUser?.canCreate,
  );
  @override
  TextInputFormatter? get inputFormatter => null;
  bool canAuthor(ComposerEditorHost editor) =>
      editor.isCurrent &&
      editor.isEditing &&
      !editor.isPluginTarget &&
      context.readState().siteSettings.policySettings?.enabled == true &&
      context.readState().freshCurrentUser.policyCurrentUser?.canCreate == true;
  @override
  List<ComposerSyntaxProjection> parse(String source) =>
      context.readEditor == null ||
          context.readState().siteSettings.policySettings?.enabled != true
      ? const []
      : [
          for (final block in const PolicySourceCodec().find(source))
            _PolicyProjection(this, block),
        ];
}

List<ComposerToolbarContribution> policyComposerToolbar(
  BuildContext context,
  ComposerEditorHost editor,
) {
  final policy = editor.syntaxPolicy<PolicyComposerPolicy>(policyComposerKind);
  if (policy == null || !policy.canAuthor(editor) || editor.loadingBody) {
    return const [];
  }
  return [
    ComposerToolbarContribution(
      icon: DIcons.fileLines,
      label: context.l10n.policyCreate,
      onInvoke: () => unawaited(editPolicyDefinition(context, editor, policy)),
    ),
  ];
}

Future<void> editPolicyDefinition(
  BuildContext context,
  ComposerEditorHost editor,
  PolicyComposerPolicy policy, [
  PolicySourceOccurrence? occurrence,
]) async {
  if (!policy.canAuthor(editor)) return;
  final groups = PluginUiScope.maybe(context, policyGroupsService);
  if (groups == null) return;
  final before = editor.value;
  final definition = await showPolicyBuilder(
    context,
    initial:
        occurrence?.definition ?? PolicyDefinition(audienceGroups: const []),
    insert: occurrence == null,
    persistedDefinition:
        occurrence != null &&
            editor.isEdit &&
            const PolicySourceCodec().find(before.text).firstOrNull?.range ==
                occurrence.range
        ? const PolicySourceCodec()
              .find(editor.originalRaw ?? '')
              .firstOrNull
              ?.definition
        : null,
    loadGroups: () => groups.load(editor.siteUrl),
    isCurrent: () =>
        policy.canAuthor(editor) && editor.value.text == before.text,
  );
  if (definition == null || !context.mounted) return;
  if (!policy.canAuthor(editor) || editor.value.text != before.text) {
    DToast.show(
      context,
      context.l10n.policySourceChanged,
      type: DToastType.error,
    );
    return;
  }
  const codec = PolicySourceCodec();
  if (occurrence == null) {
    editor.insertBlock(
      expectedValue: editor.value,
      markdown:
          '${codec.openingTag(definition)}\n${context.l10n.policyBodyPlaceholder}\n[/policy]',
    );
  } else {
    final value = codec.replaceSettings(
      document: editor.value,
      occurrence: occurrence,
      replacement: definition,
    );
    editor.commitText(expectedText: before.text, value: value);
  }
  editor.requestFocus();
}

class _PolicyProjection
    implements
        ComposerInteractiveSyntaxProjection,
        ComposerEmbeddedDocumentProjection,
        ComposerParagraphSpacingProjection {
  _PolicyProjection(this.policy, this.block);
  final PolicyComposerPolicy policy;
  final PolicySourceOccurrence block;
  @override
  int get start => block.start;
  @override
  int get end => block.end;
  @override
  String get source => block.source;
  @override
  TextRange get bodyRange {
    final openingEnd = block.openingTagRange.end - start;
    final bodyStart = source.indexOf('\n', openingEnd) + 1;
    final closingLine =
        source.lastIndexOf('\n', block.bodyRange.end - start - 1) + 1;
    var bodyEnd = closingLine > bodyStart ? closingLine - 1 : bodyStart;
    if (bodyEnd > bodyStart && source[bodyEnd - 1] == '\r') bodyEnd--;
    return TextRange(start: start + bodyStart, end: start + bodyEnd);
  }

  @override
  String replaceBody(String body, {bool multiline = false}) {
    final range = bodyRange;
    final newline = source.contains('\r\n') ? '\r\n' : '\n';
    final replacement = body.replaceAll(RegExp(r'\r\n?|\n'), newline);
    final suffix = source.substring(range.end - start);
    final separatorLength = suffix.startsWith('\r\n')
        ? 2
        : suffix.startsWith('\n')
        ? 1
        : 0;
    final separator = separatorLength > 0 || replacement.isNotEmpty
        ? newline
        : '';
    return '${source.substring(0, range.start - start)}$replacement$separator${suffix.substring(separatorLength)}';
  }

  @override
  bool get supportsHover => false;
  @override
  bool get protectsAdjacentDelete => true;
  @override
  bool needsRawSource(
    TextEditingValue document, {
    required bool suppressCollapsedCaret,
  }) =>
      document.isComposingRangeValid &&
      !document.composing.isCollapsed &&
      document.composing.start < end &&
      document.composing.end > start;
  @override
  int caretAfter(String document) => document.startsWith('\r\n', end)
      ? end + 2
      : document.startsWith('\n', end)
      ? end + 1
      : end;
  @override
  TextEditingValue moveCaretAfter(TextEditingValue document) {
    final text = end == document.text.length
        ? '${document.text}\n'
        : document.text;
    return document.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: caretAfter(text)),
      composing: TextRange.empty,
    );
  }

  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) {
    final editor = context.editor ?? policy.context.readEditor!();
    final document = editor.value.text;
    final matchesSource =
        end <= document.length && document.substring(start, end) == source;
    final hiddenEnd = source.length - (context.followedByLineBreak ? 0 : 1);
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.top,
        style: context.baseStyle,
        child: LayoutBuilder(
          builder: (buildContext, constraints) => SizedBox(
            width: (constraints.maxWidth - 3).clamp(0, double.infinity),
            child: ComposerBlockSelection(
              selected: context.highlighted,
              child: MediaQuery.withNoTextScaling(
                child: DCard(
                  key: context.pillKey,
                  variant: DCardVariant.well,
                  children: [
                    DCardHeader(
                      title: DCardTitle(
                        child: Text(buildContext.l10n.policyTitle),
                      ),
                      description: DCardDescription(
                        child: Text(
                          buildContext.l10n.policyVersionGroups(
                            block.definition.version,
                            block.definition.audienceGroups.join(', '),
                          ),
                        ),
                      ),
                      action: policy.canAuthor(editor)
                          ? DCardAction(
                              child: DButton.iconOnly(
                                icon: const Icon(
                                  Icons.settings_outlined,
                                  size: 16,
                                ),
                                tooltip: buildContext.l10n.policyEditSettings,
                                variant: DButtonVariant.ghost,
                                onPressed: () => unawaited(
                                  editPolicyDefinition(
                                    buildContext,
                                    editor,
                                    policy,
                                    block,
                                  ),
                                ),
                              ),
                            )
                          : null,
                    ),
                    DCardContent(
                      child:
                          (matchesSource
                              ? editor.buildEmbeddedDocument(
                                  buildContext,
                                  kind: policyComposerKind,
                                  identity: context.pillKey,
                                  sourceRange: block.range,
                                  expectedText: document,
                                  semanticLabel: buildContext.l10n.policyBody,
                                )
                              : null) ??
                          Text(block.body),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      TextSpan(
        text: source.substring(1, hiddenEnd),
        semanticsLabel: '\u200B' * (hiddenEnd - 1),
        style: const TextStyle(
          fontSize: 0,
          height: 0,
          letterSpacing: 0,
          color: Colors.transparent,
        ),
      ),
      if (!context.followedByLineBreak)
        TextSpan(
          text: '\n',
          style: context.baseStyle.copyWith(color: Colors.transparent),
        ),
    ];
  }

  @override
  Future<void> edit(BuildContext context, ComposerEditorHost editor) =>
      editPolicyDefinition(context, editor, policy, block);
  @override
  void remove(BuildContext context, ComposerEditorHost editor) {
    if (!policy.canAuthor(editor)) return;
    final value = editor.value;
    if (block.end > value.text.length ||
        value.text.substring(block.start, block.end) != source) {
      return;
    }
    editor.commitText(
      expectedText: value.text,
      value: value.copyWith(
        text: value.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
        composing: TextRange.empty,
      ),
    );
  }
}
