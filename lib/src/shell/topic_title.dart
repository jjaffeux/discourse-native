import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/discourse_typography.dart';
import 'emoji.dart';
import 'shell_scope.dart';
import 'site_emoji_image.dart';
import 'site_emoji_text.dart';

class TopicTitle extends StatelessWidget {
  const TopicTitle(
    this.title, {
    super.key,
    required this.siteUrl,
    this.maxLines,
    this.overflow,
    this.style,
    this.textAlign,
    this.trailing = const [],
  });

  final String title;
  final String siteUrl;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextStyle? style;
  final TextAlign? textAlign;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => SiteEmojiText.plain(
    title,
    siteUrl: siteUrl,
    maxLines: maxLines,
    overflow: overflow,
    style: style,
    textAlign: textAlign,
    trailing: trailing,
  );
}

class InlineTopicTitleEditor extends StatefulWidget {
  const InlineTopicTitleEditor({
    super.key,
    required this.title,
    required this.siteUrl,
    required this.onSave,
    this.style,
    this.maxLines = 1,
    this.showEditingFrame = false,
    this.autofocus = false,
    this.onEditingChanged,
  });

  final String title;
  final String siteUrl;
  final Future<String?> Function(String title) onSave;
  final TextStyle? style;
  final int maxLines;
  final bool showEditingFrame;

  /// Requests editing focus on insertion or when changed to true.
  final bool autofocus;

  /// Keeps the title editor available while editing or saving.
  final ValueChanged<bool>? onEditingChanged;

  @override
  State<InlineTopicTitleEditor> createState() => _InlineTopicTitleEditorState();
}

class _InlineTopicTitleEditorState extends State<InlineTopicTitleEditor> {
  late _TopicTitleEditingController _controller;
  late String _savedTitle;
  final FocusNode _focus = FocusNode(debugLabel: 'topic title editor');
  bool _saving = false;
  bool _editing = false;
  final _triggerFocus = FocusNode(debugLabel: 'edit topic title');
  bool _skipBlurSave = false;
  String? _catalogRequestSite;

  @override
  void initState() {
    super.initState();
    _savedTitle = widget.title;
    _controller = _newController();
    _focus.addListener(_focusChanged);
    if (widget.autofocus) {
      _editing = widget.showEditingFrame;
      _requestEditingFocus();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureEmojiCatalog();
  }

  @override
  void didUpdateWidget(InlineTopicTitleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autofocus && !oldWidget.autofocus) {
      _editing = widget.showEditingFrame;
      _requestEditingFocus();
    }
    if (oldWidget.siteUrl != widget.siteUrl) {
      _catalogRequestSite = null;
      final oldController = _controller;
      _savedTitle = widget.title;
      _controller = _newController();
      oldController.dispose();
      _ensureEmojiCatalog();
      return;
    }
    if (oldWidget.title == widget.title) return;
    _savedTitle = widget.title;
    if (!_editing && !_focus.hasFocus && !_saving) {
      _replaceText(widget.title);
    }
  }

  _TopicTitleEditingController _newController() =>
      _TopicTitleEditingController(text: widget.title, siteUrl: widget.siteUrl);

  void _requestEditingFocus() {
    // A title click must take focus even when its scope already has a focused
    // control, which TextField.autofocus deliberately leaves alone.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.autofocus) _focus.requestFocus();
    });
  }

  void _replaceText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _ensureEmojiCatalog() {
    if (!SiteEmojiText.shortcodePattern.hasMatch(_controller.text) ||
        _catalogRequestSite == widget.siteUrl) {
      return;
    }
    _catalogRequestSite = widget.siteUrl;
    final shell = ShellScope.read(context);
    unawaited(
      shell.ensureEmojiCatalog(widget.siteUrl).then((_) {
        if (mounted) _controller.artworkArrived();
      }),
    );
  }

  void _focusChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.showEditingFrame) {
      if (_focus.hasFocus) {
        _ensureEmojiCatalog();
      } else if (_skipBlurSave) {
        _skipBlurSave = false;
      } else if (_editing) {
        unawaited(_submitFramed(restoreFocus: false));
      }
      return;
    }
    widget.onEditingChanged?.call(_focus.hasFocus || _saving);
    if (_focus.hasFocus) {
      _ensureEmojiCatalog();
      return;
    }
    if (_skipBlurSave) {
      _skipBlurSave = false;
      return;
    }
    unawaited(_save());
  }

  Future<bool> _save() async {
    if (_saving) return false;
    final title = _controller.text.trim();
    if (title == _savedTitle.trim()) {
      if (_controller.text != _savedTitle) _replaceText(_savedTitle);
      return true;
    }

    setState(() => _saving = true);
    widget.onEditingChanged?.call(true);
    final error = await widget.onSave(title);
    if (!mounted) return false;
    if (error == null) {
      _savedTitle = title;
      if (_controller.text != title) _replaceText(title);
      setState(() => _saving = false);
      if (!widget.showEditingFrame) {
        widget.onEditingChanged?.call(_focus.hasFocus);
      }
      return true;
    }

    setState(() => _saving = false);
    DToast.show(context, error, type: DToastType.error);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    return false;
  }

  void _cancel() {
    if (_saving) return;
    _skipBlurSave = true;
    _replaceText(_savedTitle);
    _focus.unfocus();
    if (widget.showEditingFrame) _finishFramedEditing();
  }

  void _beginFramedEditing() {
    _skipBlurSave = false;
    setState(() => _editing = true);
    widget.onEditingChanged?.call(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing) _focus.requestFocus();
    });
  }

  void _finishFramedEditing({bool restoreFocus = true}) {
    setState(() => _editing = false);
    _focus.unfocus();
    widget.onEditingChanged?.call(false);
    if (restoreFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _triggerFocus.canRequestFocus) {
          _triggerFocus.requestFocus();
        }
      });
    }
  }

  Future<void> _submitFramed({bool restoreFocus = true}) async {
    if (await _save() && mounted) {
      _finishFramedEditing(restoreFocus: restoreFocus && _focus.hasFocus);
    }
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      if (!HardwareKeyboard.instance.isShiftPressed &&
          _controller.value.composing.isCollapsed) {
        if (widget.showEditingFrame) {
          unawaited(_submitFramed());
        } else {
          _focus.unfocus();
        }
        return KeyEventResult.handled;
      }
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
    _controller.dispose();
    _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controller,
        builder: (context, value, _) {
          if (widget.showEditingFrame) return _buildFramedEditor();
          final focused = _focus.hasFocus;
          final displayedTitle = value.text.isEmpty ? ' ' : value.text;
          final editor = MouseRegion(
            key: const ValueKey('topic-header-title-pointer'),
            cursor: SystemMouseCursors.text,
            child: DTooltip(
              message: 'Edit topic title',
              // Hide the editing hint while the editor owns keyboard focus.
              disabled: focused || _saving,
              child: Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.hardEdge,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 12),
                    child: Opacity(
                      opacity: focused ? 0 : 1,
                      child: ExcludeSemantics(
                        child: TopicTitle(
                          displayedTitle,
                          siteUrl: widget.siteUrl,
                          maxLines: widget.maxLines,
                          overflow: TextOverflow.ellipsis,
                          style: widget.style,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Opacity(
                      opacity: focused ? 1 : 0,
                      alwaysIncludeSemantics: true,
                      child: Focus(
                        onKeyEvent: _handleKey,
                        child: DInput(
                          borderless: true,
                          semanticLabel: 'Topic title',
                          key: const ValueKey('topic-header-title-field'),
                          controller: _controller,
                          focusNode: _focus,
                          readOnly: _saving,
                          maxLines: widget.maxLines,
                          textInputAction: TextInputAction.done,
                          textCapitalization: TextCapitalization.sentences,
                          style: widget.style,
                          onChanged: (_) => _ensureEmojiCatalog(),
                          onSubmitted: (_) => _focus.unfocus(),
                          onTapOutside: (_) => _focus.unfocus(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          return editor;
        },
      );

  Widget _buildFramedEditor() {
    if (!_editing) {
      return DButton(
        key: const ValueKey('topic-header-title-field'),
        variant: DButtonVariant.ghost,
        size: DButtonSize.small,
        alignment: AlignmentDirectional.centerStart,
        focusNode: _triggerFocus,
        semanticLabel: 'Edit topic title',
        tooltip: _savedTitle,
        onPressed: _beginFramedEditing,
        label: TopicTitle(
          _savedTitle,
          key: const ValueKey('topic-header-compact-title'),
          siteUrl: widget.siteUrl,
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis,
          style: widget.style,
        ),
      );
    }
    return Focus(
      key: const ValueKey('topic-header-title-edit-frame'),
      onKeyEvent: _handleKey,
      child: DInput(
        key: const ValueKey('topic-header-title-field'),
        controller: _controller,
        focusNode: _focus,
        semanticLabel: 'Topic title',
        readOnly: _saving,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onChanged: (_) => _ensureEmojiCatalog(),
        onTapOutside: (_) => _focus.unfocus(),
        onEditingComplete: () => unawaited(_submitFramed()),
      ),
    );
  }
}

class _TopicTitleEditingController extends TextEditingController {
  _TopicTitleEditingController({required super.text, required this.siteUrl});

  final String siteUrl;
  bool _disposed = false;

  void artworkArrived() {
    if (!_disposed) notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final source = text;
    if (source.isEmpty || !SiteEmojiText.shortcodePattern.hasMatch(source)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final shell = ShellScope.read(context);
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final spans = <InlineSpan>[];
    var offset = 0;

    void appendText(int end) {
      if (offset >= end) return;
      if (composing.isCollapsed ||
          composing.end <= offset ||
          composing.start >= end) {
        spans.add(TextSpan(text: source.substring(offset, end)));
        offset = end;
        return;
      }
      final composingStart = composing.start.clamp(offset, end);
      final composingEnd = composing.end.clamp(offset, end);
      if (offset < composingStart) {
        spans.add(TextSpan(text: source.substring(offset, composingStart)));
      }
      spans.add(
        TextSpan(
          text: source.substring(composingStart, composingEnd),
          style: const TextStyle(decoration: TextDecoration.underline),
        ),
      );
      if (composingEnd < end) {
        spans.add(TextSpan(text: source.substring(composingEnd, end)));
      }
      offset = end;
    }

    for (final match in SiteEmojiText.shortcodePattern.allMatches(source)) {
      final name = shell.emojiNameFor(siteUrl, match.group(1)!);
      final selectionTouches =
          value.selection.isValid &&
          value.selection.start < match.end &&
          value.selection.end > match.start;
      final composingTouches =
          !composing.isCollapsed &&
          composing.start < match.end &&
          composing.end > match.start;
      if (name == null || selectionTouches || composingTouches) continue;

      appendText(match.start);
      spans.add(
        TextSpan(
          text: source.substring(match.start, match.end - 1),
          style: _hidden,
        ),
      );
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          style: style,
          child: IgnorePointer(
            child: SiteEmojiImage(
              siteUrl: siteUrl,
              name: name,
              size: (style?.fontSize ?? DiscourseTypography.sm) * emojiScale,
              alt: '',
              style: style,
            ),
          ),
        ),
      );
      offset = match.end;
    }
    appendText(source.length);

    final span = TextSpan(style: style, children: spans);
    assert(
      span.toPlainText(includeSemanticsLabels: false).length == source.length,
      'the editable topic title drifted from its source',
    );
    return span;
  }

  static const TextStyle _hidden = TextStyle(
    fontSize: 0,
    color: Color(0x00000000),
    letterSpacing: 0,
    wordSpacing: 0,
  );

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
