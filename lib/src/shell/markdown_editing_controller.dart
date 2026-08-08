import 'dart:async';

import 'package:flutter/material.dart';

import '../data/emoji_cache.dart';
import '../plugins/poll/poll_composer_parser.dart';
import '../plugins/poll/poll_composer_pill.dart';
import '../theme/app_theme.dart';
import 'code_block.dart';
import 'composer_pills.dart';
import 'emoji.dart';
import 'hashtag.dart';
import 'markdown_highlight.dart';
import 'mention.dart';

/// A field controller that draws markdown as what it means.
///
/// The text is never touched. `buildTextSpan` is the one hook Flutter offers
/// for deciding how an editable's contents are *painted*, and everything here
/// goes through it — so `text` stays the exact string that will be posted, and
/// drafts, the typing clock and the send button never learn that anything is
/// being drawn differently.
///
/// Markers are dimmed rather than hidden. Hiding them is where an editor starts
/// lying about what will be posted, which is the whole reason the document-model
/// composer was taken out.
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({
    super.text,
    this.resolveEmoji,
    this.pills,
    this.pollMaximumOptions = 20,
  });

  /// Where the artwork for `smile` lives on the site being written to.
  ///
  /// Injected rather than reached for, because the shell owns the site and its
  /// custom emoji — see `ShellController.emojiUrlFor`. Null leaves every
  /// shortcode as text, which is what the tests and a composer with no site
  /// behind it get.
  final String Function(String name)? resolveEmoji;

  /// What a `#ref` and an `@name` turn out to be, and how to go and find out.
  ///
  /// Null leaves both as text — which is what the tests and a composer with no
  /// site behind it get, exactly as for [resolveEmoji].
  final ComposerPills? pills;

  final int pollMaximumOptions;

  String? _pollScanned;
  List<PollComposerBlock> _pollBlocks = const [];
  final PollRawExpansion _rawPoll = PollRawExpansion();
  int? _suppressedPollStart;
  int? _suppressedPollCaret;
  Set<int> _collapsedPollStarts = const {};
  final Map<int, GlobalKey> _pollPillKeys = {};

  /// Safely projectable poll occurrences in the current raw document.
  List<PollComposerBlock> get pollBlocks =>
      List.unmodifiable(_pollBlocksFor(text));

  PollComposerBlock? pollAtOffset(int offset) =>
      pollBlockAtComposerOffset(_pollBlocksFor(text), offset);

  bool isPollExpanded(PollComposerBlock block) => _rawPoll.contains(block);

  bool isPollCollapsed(PollComposerBlock block) =>
      _collapsedPollStarts.contains(block.start);

  /// The collapsed poll whose visible pill contains [globalPosition].
  ///
  /// EditableText deliberately keeps embedded widgets out of pointer hit
  /// testing. Their render boxes still have truthful geometry, so the field
  /// routes taps and hover through these exact rectangles instead of guessing
  /// from the caret Flutter selected.
  PollComposerBlock? collapsedPollAtGlobalPosition(Offset globalPosition) {
    for (final block in _pollBlocksFor(text)) {
      if (!isPollCollapsed(block)) continue;
      final rect = collapsedPollGlobalRect(block);
      if (rect?.contains(globalPosition) == true) return block;
    }
    return null;
  }

  Rect? collapsedPollGlobalRect(PollComposerBlock block) {
    if (!isPollCollapsed(block)) return null;
    final renderObject = _pollPillKeys[block.start]?.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  void suppressCollapsedCaretFor(PollComposerBlock block) {
    _suppressedPollStart = block.start;
    _suppressedPollCaret = value.selection.extentOffset;
    artworkArrived();
  }

  void expandPollAsRaw(PollComposerBlock block) {
    _suppressedPollStart = null;
    _suppressedPollCaret = null;
    _rawPoll.expand(block);
    value = value.copyWith(
      selection: TextSelection.collapsed(
        offset: (block.start + 1).clamp(block.start, block.end),
      ),
    );
  }

  List<PollComposerBlock> _pollBlocksFor(String source) {
    if (_pollScanned == source) return _pollBlocks;
    _pollScanned = source;
    _suppressedPollStart = null;
    _suppressedPollCaret = null;
    _rawPoll.clear();
    _pollPillKeys.clear();
    return _pollBlocks = parsePollComposerBlocks(source);
  }

  /// How many pieces of artwork have arrived, so the span cache knows the
  /// answer changed when nothing about the text did.
  int _artwork = 0;

  /// Urls currently being loaded, so a shortcode that is being typed does not
  /// queue a fetch per keystroke.
  ///
  /// Completed requests are removed. [EmojiCache] owns the longer-lived
  /// success, permanent-failure and transient-failure state; keeping a second
  /// permanent record here would prevent its cooldown retry from ever running.
  final Set<String> _loadingEmoji = {};

  bool _disposed = false;

  List<MarkdownRun>? _runs;
  String? _scanned;

  _CachedMarkdownSpan? _cachedSpan;

  /// How many times the source has actually been read, so a test can hold the
  /// memoisation to account rather than trusting it.
  @visibleForTesting
  int scans = 0;

  /// [buildTextSpan] is called on every keystroke, every caret move and every
  /// frame of a selection drag, while the scan only depends on the text. A
  /// fenced block is tokenized by `highlightLines`, which is expensive enough
  /// that `syntax.dart` refuses to run it past 20k characters — rescanning per
  /// caret move would spend that on nothing.
  List<MarkdownRun> _runsFor(String source) {
    if (_scanned == source) return _runs!;
    scans++;
    _scanned = source;
    return _runs = scanMarkdown(source);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final source = value.text;
    if (source.isEmpty) return TextSpan(style: style);

    final theme = Theme.of(context);
    final base = style ?? const TextStyle();

    // The range an IME is still deciding about. Honoured rather than dropped:
    // without it a dead key on macOS and every CJK keystroke lose the underline
    // that says the character is not committed yet.
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : null;

    final runs = _runsFor(source);

    final pollBlocks = _pollBlocksFor(source);
    _rawPoll.updateSelection(value.selection);
    if (_suppressedPollCaret != value.selection.extentOffset) {
      _suppressedPollStart = null;
      _suppressedPollCaret = null;
    }
    final collapsedPolls = [
      for (final block in pollBlocks)
        if (!pollBlockNeedsRawSource(
          block: block,
          value: value,
          explicitlyRaw: _rawPoll.contains(block),
          suppressCollapsedCaret: _suppressedPollStart == block.start,
        ))
          block,
    ];
    _collapsedPollStarts = {for (final block in collapsedPolls) block.start};
    final pollProjection = Object.hash(
      pollMaximumOptions,
      Object.hashAll(
        collapsedPolls.map((block) => Object.hash(block.start, block.end)),
      ),
    );

    // Which token, if any, the caret is in — the one thing about the selection
    // that changes what is drawn. Summarised rather than keyed on the
    // selection itself, so the ordinary caret move still costs nothing.
    final revealed = _revealedPill(runs, value.selection);

    // Moving the caret changes none of the rest, and returning the *same* span
    // rather than an equal one is what makes that free: `RenderEditable`'s
    // `text` setter compares by identity first and skips the relayout.
    final cached = _cachedSpan;
    if (cached != null &&
        cached.matches(
          source: source,
          style: base,
          theme: theme,
          composing: composing,
          revealed: revealed,
          artwork: _artwork,
          pollProjection: pollProjection,
        )) {
      return cached.span;
    }

    // What a repaint found it could not draw yet, asked about once at the end
    // rather than once per run — a paragraph pasted with forty hashtags is one
    // request, not forty.
    final unresolvedRefs = <String>{};
    final unresolvedNames = <String>{};

    final children = <InlineSpan>[];

    void appendRun(MarkdownRun run) {
      // A run the IME is still deciding about is never substituted: the
      // artwork path skips [_splitAt] entirely, so a placeholder over a
      // composing range would take its underline away and paint the
      // uncommitted characters invisibly.
      final artwork =
          run.start == revealed || _overlapsComposing(run, composing)
          ? null
          : _artworkFor(run, base, theme, unresolvedRefs, unresolvedNames);
      if (artwork != null) {
        children.addAll(artwork);
        return;
      }
      for (final piece in _splitAt(run, composing)) {
        children.add(
          TextSpan(
            text: source.substring(piece.start, piece.end),
            style: _styleFor(piece, base, theme, composing),
          ),
        );
      }
    }

    void appendMarkdown(int start, int end) {
      if (start >= end) return;
      for (final run in runs) {
        if (run.end <= start) continue;
        if (run.start >= end) break;
        appendRun(
          MarkdownRun(
            run.start < start ? start : run.start,
            run.end > end ? end : run.end,
            run.mask,
            run.detail,
            run.token,
          ),
        );
      }
    }

    var sourceOffset = 0;
    for (final block in collapsedPolls) {
      appendMarkdown(sourceOffset, block.start);
      children.addAll(
        buildCollapsedPollSpans(
          block: block,
          baseStyle: base,
          pillKey: _pollPillKeys.putIfAbsent(
            block.start,
            () => GlobalKey(debugLabel: 'poll-pill-${block.start}'),
          ),
          maximumOptions: pollMaximumOptions,
        ),
      );
      sourceOffset = block.end;
    }
    appendMarkdown(sourceOffset, source.length);

    final span = TextSpan(style: base, children: children);
    // The one thing that must never drift.
    //
    // Length, not contents: a WidgetSpan flattens to one `0xFFFC` where the
    // source has its own character, so the two strings differ exactly at the
    // placeholders and nowhere else. What everything downstream depends on —
    // the caret, hit testing, word boundaries, select-all — is that an offset
    // means the same position in both, and Flutter neither asserts that nor
    // converts between them when it stops being true.
    assert(
      span.toPlainText(includeSemanticsLabels: false).length == source.length,
      'the painted text drifted from the source',
    );

    // After the span is built, not during: asking is a side effect, and the
    // answer arrives through [_artwork] and a repaint rather than here.
    if (unresolvedRefs.isNotEmpty || unresolvedNames.isNotEmpty) {
      pills?.resolve(unresolvedRefs, unresolvedNames);
    }

    _cachedSpan = _CachedMarkdownSpan(
      source: source,
      style: base,
      theme: theme,
      composing: composing,
      revealed: revealed,
      artwork: _artwork,
      pollProjection: pollProjection,
      span: span,
    );
    return span;
  }

  /// Something a run was waiting on has landed: repaint.
  ///
  /// Notifying with the value unchanged is what redraws the field, and it is
  /// inert everywhere else that listens: `UndoHistory` returns early when the
  /// value has not changed (`undo_history.dart:185`), and `ComposerController`
  /// guards on the text being different — so an answer arriving is not read as
  /// a keystroke by the typing clock or the draft timer.
  void artworkArrived() {
    if (_disposed) return;
    _artwork++;
    notifyListeners();
  }

  /// A shortcode drawn as its artwork, or null to draw it as text.
  ///
  /// The one thing this may not do is change how many characters the paragraph
  /// has. A `WidgetSpan` is worth exactly one code unit of the laid-out text
  /// (`PlaceholderSpan.placeholderCodeUnit`), and `RenderEditable` measures the
  /// caret, hit testing, word boundaries and select-all against that same
  /// string while handing the answers back as offsets into [text]. One
  /// placeholder standing in for the seven characters of `:smile:` would put
  /// every later offset out by six, silently.
  ///
  /// So the run is split: `:smile` stays as real text drawn at zero size and
  /// full transparency — six characters occupying six offsets and no pixels —
  /// and only the closing colon becomes the placeholder. Seven characters in,
  /// seven code units out, and the caret keeps meaning what it says.
  List<InlineSpan>? _artworkFor(
    MarkdownRun run,
    TextStyle base,
    ThemeData theme,
    Set<String> unresolvedRefs,
    Set<String> unresolvedNames,
  ) {
    final token = run.token;
    if (token == null || run.length < 2) return null;

    if (run.has(Md.hashtag)) {
      return _hashtagPill(run, token, base, unresolvedRefs);
    }
    if (run.has(Md.mention)) {
      return _mentionPill(run, token, base, unresolvedNames);
    }

    final resolve = resolveEmoji;
    if (resolve == null || !run.has(Md.emoji)) return null;

    final url = resolve(token);
    final cache = EmojiCache.instance;

    // Only ever substituted once the bytes are here, so the placeholder is
    // created at its final size and nothing reflows under the caret mid-word.
    // A name the site does not have 404s once, is remembered as a failure, and
    // stays text forever at no further cost.
    if (!cache.isCached(url)) {
      if (_loadingEmoji.add(url)) {
        unawaited(
          cache.load(url).then((_) {
            _loadingEmoji.remove(url);
            if (_disposed) return;
            artworkArrived();
            // Notifying with the value unchanged is what repaints the field,
            // and it is inert everywhere else that listens: `UndoHistory`
            // returns early when the value has not changed
            // (`undo_history.dart:185`), and `ComposerController`'s own
            // listener guards on the text being different, so an image
            // arriving is not read as a keystroke by the typing clock or the
            // draft timer.
          }),
        );
      }
      return null;
    }
    if (cache.cached(url) == null) return null;

    final size = (base.fontSize ?? 14) * emojiScale;
    return [
      TextSpan(text: text.substring(run.start, run.end - 1), style: _hidden),
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        style: base,
        child: EmojiImage(url: url, size: size, alt: ''),
      ),
    ];
  }

  /// A `#ref` drawn as its pill, or null to draw it as text.
  ///
  /// The same split [_artworkFor] describes, and the same contract: nothing is
  /// substituted until the site has answered, so a chip never appears under
  /// the caret half way through a word. A ref the site does not have — or will
  /// not show this reader — is remembered as a failure and stays text.
  List<InlineSpan>? _hashtagPill(
    MarkdownRun run,
    String ref,
    TextStyle base,
    Set<String> unresolved,
  ) {
    final found = pills?.hashtag(ref);
    if (found == null) {
      if (pills != null) unresolved.add(ref);
      return null;
    }

    final kind = found.type == 'category'
        ? HashtagKind.category
        : HashtagKind.tag;

    return _placeholder(
      run,
      base,
      HashtagPill(
        // The characters that are actually in the field, not the site's own
        // `Parent > Child`. What the composer draws is what will be posted;
        // the cooked post is where the real name belongs.
        label: text.substring(run.start, run.end),
        baseStyle: base,
        kind: kind,
        style: HashtagStyle.parse(found.styleType),
        icon: found.icon,
        emoji: found.emoji,
        colorValues: found.colorValues,
      ),
    );
  }

  /// An `@name` drawn as its pill, or null to draw it as text.
  List<InlineSpan>? _mentionPill(
    MarkdownRun run,
    String username,
    TextStyle base,
    Set<String> unresolved,
  ) {
    final real = pills?.mention(username);
    if (real == null) {
      if (pills != null) unresolved.add(username);
      return null;
    }
    // Nobody by that name. The post will cook it as plain text, so the field
    // says so too.
    if (!real) return null;

    return _placeholder(
      run,
      base,
      MentionPill(label: text.substring(run.start, run.end), baseStyle: base),
    );
  }

  /// The span pair every pill is made of.
  ///
  /// All but the last character stay as real text at zero size and full
  /// transparency, and only the last becomes the placeholder — see
  /// [_artworkFor] for why the count has to come out the same.
  ///
  /// The widget is inert: [IgnorePointer] so the chip cannot swallow a tap
  /// meant for the caret behind it.
  List<InlineSpan> _placeholder(MarkdownRun run, TextStyle base, Widget pill) =>
      [
        TextSpan(text: text.substring(run.start, run.end - 1), style: _hidden),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          style: base,
          child: IgnorePointer(child: pill),
        ),
      ];

  /// Where the token the caret is in starts, or -1.
  ///
  /// The rule differs by kind, and it has to. An `:emoji:` run only exists
  /// once it is closed, so *strictly* inside is right there: a caret at either
  /// end must not reveal it, or typing the closing colon would never show the
  /// picture. A mention or a hashtag has no closing character — the run grows
  /// under the caret as it is typed — so the caret is always at its end, and
  /// strict-inside would substitute a chip half way through a word and ask the
  /// site about every prefix on the way. Adjacency is what makes `#ran` stay
  /// text until the space that finishes it.
  static int _revealedPill(List<MarkdownRun> runs, TextSelection selection) {
    if (!selection.isValid) return -1;

    for (final run in runs) {
      final inside = run.has(Md.emoji)
          ? selection.start < run.end && selection.end > run.start
          : selection.start <= run.end && selection.end >= run.start;
      if (!inside) continue;
      if (run.has(Md.emoji) || run.has(Md.mention) || run.has(Md.hashtag)) {
        return run.start;
      }
    }
    return -1;
  }

  static bool _overlapsComposing(MarkdownRun run, TextRange? composing) =>
      composing != null &&
      composing.start < run.end &&
      composing.end > run.start;

  TextStyle _styleFor(
    MarkdownRun run,
    TextStyle base,
    ThemeData theme,
    TextRange? composing,
  ) {
    final style = markdownStyle(run.mask, run.detail, base, theme);
    if (composing == null ||
        run.start < composing.start ||
        run.end > composing.end) {
      return style;
    }
    // Combined rather than replaced, so an underline over struck-through text
    // does not take the strikethrough away.
    return style.copyWith(
      decoration: TextDecoration.combine([
        if (style.decoration != null) style.decoration!,
        TextDecoration.underline,
      ]),
    );
  }

  /// The `:smile` of a `:smile:` that is being drawn as a picture.
  ///
  /// They stay in the span tree — they have to, or every caret offset after
  /// them is wrong — but they take no room and paint nothing.
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

  /// Cuts [run] where the composing range starts and ends, so the underline
  /// lands on exactly the characters the IME is holding.
  static List<MarkdownRun> _splitAt(MarkdownRun run, TextRange? composing) {
    if (composing == null) return [run];

    final cuts = <int>{
      run.start,
      run.end,
      if (composing.start > run.start && composing.start < run.end)
        composing.start,
      if (composing.end > run.start && composing.end < run.end) composing.end,
    }.toList()..sort();

    return [
      for (var i = 0; i < cuts.length - 1; i++)
        MarkdownRun(cuts[i], cuts[i + 1], run.mask, run.detail, run.token),
    ];
  }
}

/// Everything that can change the span tree without changing the source.
///
/// The theme is compared by identity deliberately. [ThemeData.operator ==]
/// walks the entire theme, which would put a large deep comparison back on
/// every caret move. A stable inherited theme is the same object, while a
/// theme animation or replacement supplies a new one and must repaint even
/// when both themes have the same brightness.
class _CachedMarkdownSpan {
  const _CachedMarkdownSpan({
    required this.source,
    required this.style,
    required this.theme,
    required this.composing,
    required this.revealed,
    required this.artwork,
    required this.pollProjection,
    required this.span,
  });

  final String source;
  final TextStyle style;
  final ThemeData theme;
  final TextRange? composing;
  final int revealed;
  final int artwork;
  final int pollProjection;
  final TextSpan span;

  bool matches({
    required String source,
    required TextStyle style,
    required ThemeData theme,
    required TextRange? composing,
    required int revealed,
    required int artwork,
    required int pollProjection,
  }) =>
      this.source == source &&
      this.style == style &&
      identical(this.theme, theme) &&
      this.composing == composing &&
      this.revealed == revealed &&
      this.artwork == artwork &&
      this.pollProjection == pollProjection;
}

/// How a marked-up stretch of source is drawn.
///
/// Block level first, then inline, then the marker dimming last — a `**` inside
/// a heading is still a marker, and dimming it after the heading has set its
/// weight keeps it the same size as the words it wraps.
TextStyle markdownStyle(
  int mask,
  String? detail,
  TextStyle base,
  ThemeData theme,
) {
  var style = base;

  // Sizes multiply into one factor applied at the end rather than each
  // construct assigning its own. `<small>` inside a `##` heading is both
  // things at once, and two assignments would mean the last one read wins.
  var scale = 1.0;

  if (mask & Md.codeBlock != 0) {
    scale *= 0.9;
    style = style.copyWith(
      fontFamily: null,
      fontFamilyFallback: monospaceFallback,
      color: scopeColor(detail, theme.code) ?? theme.colorScheme.onSurface,
    );
  }

  if (mask & Md.heading != 0) {
    // 1.45 down to 1.0, so six levels are visibly six levels without a `#`
    // line towering over the rest of the field.
    final level = int.tryParse(detail ?? '1') ?? 1;
    scale *= 1.45 - (level - 1) * 0.09;
    style = style.copyWith(fontWeight: FontWeight.w700);
  }

  if (mask & Md.quote != 0) {
    style = style.copyWith(color: theme.colorScheme.onSurfaceVariant);
  }

  if (mask & Md.code != 0) {
    // The render path draws inline code as a rounded, padded chip, which has
    // to be a widget — see [InlineCode]. A widget cannot go here: a WidgetSpan
    // is worth exactly one character of the paragraph the caret is measured
    // against, so one standing in for a longer run would put every offset
    // after it wrong. A flat background is the honest approximation.
    scale *= 0.875;
    style = style.copyWith(
      fontFamily: null,
      fontFamilyFallback: monospaceFallback,
      backgroundColor: theme.code.inlineBackground,
    );
  }

  if (mask & Md.bold != 0) style = style.copyWith(fontWeight: FontWeight.w700);
  if (mask & Md.italic != 0) {
    style = style.copyWith(fontStyle: FontStyle.italic);
  }
  if (mask & Md.strikethrough != 0) {
    style = style.copyWith(decoration: TextDecoration.lineThrough);
  }

  if (mask & Md.htmlTag != 0) {
    for (final tag in (detail ?? '').split(',')) {
      final (tagStyle, tagScale) = _tagStyle(tag, style, theme);
      style = tagStyle;
      scale *= tagScale;
    }
  }

  // Links are coloured but never underlined: an underline in an editable is
  // the IME's way of saying a character is not committed yet, and a link that
  // borrows it would be lying about the state of the text.
  if (mask & (Md.linkText | Md.linkUrl | Md.mention | Md.emoji | Md.hashtag) !=
      0) {
    style = style.copyWith(color: theme.colorScheme.primary);
  }
  if (mask & (Md.mention | Md.hashtag) != 0) {
    style = style.copyWith(fontWeight: FontWeight.w600);
  }

  if (mask & Md.marker != 0) {
    // Only the colour: the marker keeps whatever size and weight its
    // surroundings gave it, so `**` sits on the same line as the bold word
    // between them rather than shrinking away from it.
    style = style.copyWith(color: theme.shell.marker);
  }

  return scale == 1.0
      ? style
      : style.copyWith(fontSize: (base.fontSize ?? 14) * scale);
}

/// The eight inline tags Discourse keeps, drawn as what they will become.
///
/// This is what the deleted rich editor's `discourseInlineStyle` did, minus the
/// document model: styling is a function of what is true of a span, so it works
/// just as well over source text as it did over attributions.
(TextStyle, double) _tagStyle(String tag, TextStyle style, ThemeData theme) =>
    switch (tag) {
      'kbd' => (
        style.copyWith(
          fontFamily: null,
          fontFamilyFallback: monospaceFallback,
          backgroundColor: theme.code.inlineBackground,
        ),
        0.9,
      ),
      'mark' => (
        style.copyWith(
          backgroundColor: theme.colorScheme.tertiaryContainer,
          color: theme.colorScheme.onTertiaryContainer,
        ),
        1.0,
      ),
      'sup' => (
        style.copyWith(fontFeatures: const [FontFeature.superscripts()]),
        1.0,
      ),
      'sub' => (
        style.copyWith(fontFeatures: const [FontFeature.subscripts()]),
        1.0,
      ),
      'small' => (style, 0.85),
      'big' => (style, 1.15),
      // The one construct allowed an underline, because that is what the tag
      // means. Everything else leaves it to the IME.
      'ins' => (style.copyWith(decoration: TextDecoration.underline), 1.0),
      'del' => (style.copyWith(decoration: TextDecoration.lineThrough), 1.0),
      _ => (style, 1.0),
    };
