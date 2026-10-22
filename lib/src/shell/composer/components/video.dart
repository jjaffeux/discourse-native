import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_plugin_api/discourse_plugin_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../plugin_api/composer_syntax.dart';
import '../../inline_video.dart';
import '../../skeleton_fill.dart';
import '../block_selection.dart';
import 'image_source.dart';

final class ComposerVideoPolicy implements ComposerSyntaxPolicy {
  const ComposerVideoPolicy();

  @override
  ComposerSyntaxKind get kind => ComposerSyntaxKind(
    owner: const PluginId('core'),
    name: 'video',
    label: appL10n.video,
  );

  @override
  Object? get projectionState => null;

  @override
  TextInputFormatter? get inputFormatter => null;

  @override
  List<ComposerSyntaxProjection> parse(String source) => [
    for (final video in parseComposerVideos(source)) _VideoProjection(video),
  ];
}

final class _VideoProjection implements ComposerAtomicSelectionProjection {
  const _VideoProjection(this.video);

  final ComposerVideoBlock video;

  @override
  int get start => video.start;
  @override
  int get end => video.end;
  @override
  String get source => video.source;
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
  TextEditingValue moveCaretAfter(
    TextEditingValue document,
  ) => document.copyWith(
    text: end == document.text.length ? '${document.text}\n' : document.text,
    selection: TextSelection.collapsed(
      offset: end == document.text.length ? end + 1 : caretAfter(document.text),
    ),
    composing: TextRange.empty,
  );

  @override
  List<InlineSpan> buildCollapsedSpans(ComposerSyntaxRenderContext context) {
    final url =
        context.resolveUploadUrl?.call(video.url) ??
        (video.url.startsWith('upload://') ? null : video.url);
    final data = url == null
        ? null
        : InlineVideoData.fromUpload(
            url: url,
            title: video.title,
            siteUrl: context.siteUrl ?? '',
          );
    final hiddenEnd = source.length - (context.followedByLineBreak ? 0 : 1);
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.top,
        style: context.baseStyle,
        child: LayoutBuilder(
          builder: (widgetContext, constraints) {
            final caretMargin =
                (widgetContext
                        .findAncestorWidgetOfExactType<EditableText>()
                        ?.cursorWidth ??
                    2) +
                1;
            return SizedBox(
              width: math.min(
                (constraints.maxWidth - caretMargin).clamp(0, double.infinity),
                190 * (data?.aspectRatio ?? 16 / 9),
              ),
              child: MediaQuery.withNoTextScaling(
                child: ComposerBlockSelection(
                  key: context.pillKey,
                  selected: context.highlighted,
                  child: data == null
                      ? DSkeletonRegion(
                          semanticsLabel: widgetContext.l10n.loading,
                          color: skeletonFill(widgetContext),
                          child: const DSkeleton(height: 190),
                        )
                      : InlineVideo(
                          data: data,
                          siteUrl: context.siteUrl,
                          maximumHeight: 190,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                        ),
                ),
              ),
            );
          },
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
  void edit(BuildContext context, ComposerEditorHost editor) {}

  @override
  void remove(BuildContext context, ComposerEditorHost editor) {
    if (!editor.isCurrent || !editor.isEditing) return;
    final current = editor.value;
    if (end > current.text.length ||
        current.text.substring(start, end) != source) {
      return;
    }
    editor.commitText(
      expectedText: current.text,
      value: TextEditingValue(
        text: current.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      ),
    );
  }
}
