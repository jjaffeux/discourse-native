import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'emoji.dart';
import 'shell_scope.dart';
import 'site_emoji_image.dart';
import 'site_emoji_text.dart';

/// A topic title with Discourse emoji shortcodes drawn as site emoji.
///
/// Topic payloads deliberately use the plain `title` rather than the HTML
/// `fancy_title`, so entities remain text a native widget can understand. The
/// plain title keeps emoji as `:shortcodes:`, though, and those need the same
/// site-aware artwork resolution as emoji in cooked posts.
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

/// A topic title that becomes an undecorated one-line editor on focus.
///
/// The ordinary [TopicTitle] stays in the tree as both the visual and sizing
/// layer. An invisible field underneath it receives the first pointer event,
/// so Flutter can put the caret at the character that was actually clicked;
/// once focused, the two layers exchange opacity without changing geometry.
class InlineTopicTitleEditor extends StatefulWidget {
  const InlineTopicTitleEditor({
    super.key,
    required this.title,
    required this.siteUrl,
    required this.onSave,
    this.style,
  });

  final String title;
  final String siteUrl;
  final Future<String?> Function(String title) onSave;
  final TextStyle? style;

  @override
  State<InlineTopicTitleEditor> createState() => _InlineTopicTitleEditorState();
}

class _InlineTopicTitleEditorState extends State<InlineTopicTitleEditor> {
  late _TopicTitleEditingController _controller;
  late String _savedTitle;
  final FocusNode _focus = FocusNode(debugLabel: 'topic title editor');
  bool _saving = false;
  bool _skipBlurSave = false;
  String? _catalogRequestSite;

  @override
  void initState() {
    super.initState();
    _savedTitle = widget.title;
    _controller = _newController();
    _focus.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureEmojiCatalog();
  }

  @override
  void didUpdateWidget(InlineTopicTitleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    if (!_focus.hasFocus && !_saving) {
      _replaceText(widget.title);
    }
  }

  _TopicTitleEditingController _newController() =>
      _TopicTitleEditingController(text: widget.title, siteUrl: widget.siteUrl);

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

  Future<void> _save() async {
    if (_saving) return;
    final title = _controller.text.trim();
    if (title == _savedTitle.trim()) {
      if (_controller.text != _savedTitle) _replaceText(_savedTitle);
      return;
    }

    setState(() => _saving = true);
    final error = await widget.onSave(title);
    if (!mounted) return;
    if (error == null) {
      _savedTitle = title;
      if (_controller.text != title) _replaceText(title);
      setState(() => _saving = false);
      return;
    }

    setState(() => _saving = false);
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(error)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _cancel() {
    if (_saving) return;
    _skipBlurSave = true;
    _replaceText(_savedTitle);
    _focus.unfocus();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controller,
        builder: (context, value, _) {
          final focused = _focus.hasFocus;
          final displayedTitle = value.text.isEmpty ? ' ' : value.text;
          return MouseRegion(
            key: const ValueKey('topic-header-title-pointer'),
            cursor: SystemMouseCursors.text,
            child: Tooltip(
              message: value.text.isEmpty ? _savedTitle : value.text,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 12),
                    child: Opacity(
                      opacity: focused ? 0 : 1,
                      child: ExcludeSemantics(
                        child: TopicTitle(
                          displayedTitle,
                          siteUrl: widget.siteUrl,
                          maxLines: 1,
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
                        child: TextField(
                          key: const ValueKey('topic-header-title-field'),
                          controller: _controller,
                          focusNode: _focus,
                          readOnly: _saving,
                          maxLines: 1,
                          textInputAction: TextInputAction.done,
                          textCapitalization: TextCapitalization.sentences,
                          style: widget.style,
                          strutStyle: StrutStyle.fromTextStyle(
                            widget.style ?? DefaultTextStyle.of(context).style,
                          ),
                          scrollPadding: EdgeInsets.zero,
                          decoration: const InputDecoration.collapsed(
                            hintText: '',
                          ),
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
        },
      );
}

/// Paints registered site emoji inside an editable without changing offsets.
///
/// A widget span occupies one code unit, so all but the shortcode's last code
/// unit stay in the span tree as zero-width transparent text. Caret positions,
/// selection, undo and the source string therefore keep referring to the same
/// offsets even though the shortcode is drawn as artwork.
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
              size: (style?.fontSize ?? 14) * emojiScale,
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
