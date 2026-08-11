import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../models/post.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'shell_scope.dart';

/// Builds the portable BBCode block Discourse uses for a selected post quote.
String buildPostQuote({
  required Post post,
  required int topicId,
  required String contents,
}) {
  final selected = contents.trim();
  if (selected.isEmpty) return '';

  final fullName = post.name?.trim();
  final usesFullName = fullName != null && fullName.isNotEmpty;
  final quotedName = (usesFullName ? fullName : post.username).replaceAll(
    RegExp(r'''["'‘’“”«»‹›]'''),
    '',
  );
  final params = <String>[
    quotedName,
    'post:${post.postNumber}',
    'topic:$topicId',
    if (usesFullName) 'username:${post.username}',
  ];

  return '[quote="${params.join(', ')}"]\n$selected\n[/quote]\n\n';
}

/// Reconstructs the Markdown structure Flutter's selection API leaves out.
///
/// [SelectedContent.plainText] concatenates independently rendered HTML
/// blocks, so selecting two cooked paragraphs produces `First.Second` even
/// though Discourse quotes the selected HTML as `First.\n\nSecond`. Match that
/// character stream back to the cooked DOM and restore block boundaries and
/// the common inline marks core's `toMarkdown` preserves.
String postQuoteContentsFromSelection(String cooked, String plainText) {
  final selected = plainText.trim();
  if (selected.isEmpty || cooked.isEmpty) return selected;

  final source = _CookedSelectionSource.fromHtml(cooked);
  final directStart = source.plainText.indexOf(selected);
  if (directStart >= 0) {
    return source.markdown(directStart, directStart + selected.length);
  }

  // A rendered `<br>` may already contribute a newline on one Flutter
  // platform and be omitted on another. Structural breaks are held outside
  // [plainText], so remove them before the fallback match.
  final compact = selected.replaceAll(RegExp(r'[\r\n]'), '');
  final compactStart = source.plainText.indexOf(compact);
  return compactStart < 0
      ? selected
      : source.markdown(compactStart, compactStart + compact.length);
}

/// Makes one post body selectable and offers Discourse's quote actions.
///
/// A separate selection region per post deliberately prevents a drag from
/// attributing text from two different posts to one author. Flutter only
/// opens its stock menu automatically for touch selection; this owns the
/// overlay so the same toolbar also appears after a desktop mouse drag.
class PostTextSelection extends StatefulWidget {
  const PostTextSelection({
    super.key,
    required this.post,
    required this.topicId,
    required this.child,
  });

  final Post post;
  final int topicId;
  final Widget child;

  @override
  State<PostTextSelection> createState() => _PostTextSelectionState();
}

class _PostTextSelectionState extends State<PostTextSelection> {
  static const Duration _toolbarDelay = Duration(milliseconds: 150);

  final GlobalKey<SelectionAreaState> _selectionKey = GlobalKey();
  final OverlayPortalController _portal = OverlayPortalController();

  Timer? _showTimer;
  TextSelectionToolbarAnchors? _anchors;
  String _selectedText = '';
  ScrollPosition? _scroll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _scroll)) return;
    _scroll?.removeListener(_hideWhileScrolling);
    _scroll = position?..addListener(_hideWhileScrolling);
  }

  @override
  void didUpdateWidget(PostTextSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id ||
        oldWidget.post.cooked != widget.post.cooked) {
      _dismiss(clearSelection: true);
    }
  }

  void _hideWhileScrolling() => _dismiss(clearSelection: false);

  void _selectionChanged(SelectedContent? content) {
    _showTimer?.cancel();
    _selectedText = postQuoteContentsFromSelection(
      widget.post.cooked,
      content?.plainText ?? '',
    );
    if (_selectedText.isEmpty) {
      _dismiss(clearSelection: false);
      return;
    }

    // Selection changes for every pointer move. Waiting briefly keeps the
    // menu from chasing the cursor while still feeling immediate on release.
    _showTimer = Timer(_toolbarDelay, _showToolbar);
  }

  void _showToolbar() {
    if (!mounted || _selectedText.isEmpty) return;
    final area = _selectionKey.currentState;
    if (area == null) return;

    final anchors = area.selectableRegion.contextMenuAnchors;
    setState(() => _anchors = anchors);
    if (!_portal.isShowing) _portal.show();
  }

  void _dismiss({required bool clearSelection}) {
    _showTimer?.cancel();
    _showTimer = null;
    if (_portal.isShowing) _portal.hide();
    if (clearSelection) {
      _selectionKey.currentState?.selectableRegion.clearSelection();
    }
  }

  String get _quote => buildPostQuote(
    post: widget.post,
    topicId: widget.topicId,
    contents: _selectedText,
  );

  void _insertQuote() {
    final quote = _quote;
    if (quote.isEmpty) return;
    final controller = ShellScope.read(context);
    _dismiss(clearSelection: true);
    unawaited(controller.openQuote(widget.post, quote));
  }

  Future<void> _copyQuote() async {
    final quote = _quote;
    if (quote.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: quote));
    if (!mounted) return;
    _dismiss(clearSelection: true);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Quote copied to clipboard.')),
    );
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _scroll?.removeListener(_hideWhileScrolling);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShellSelector<bool>(
    select: (controller) => controller.canReplyHere,
    builder: (context, canQuote, _) => OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        final anchors = _anchors;
        if (anchors == null || _selectedText.isEmpty) {
          return const SizedBox.shrink();
        }
        return _PostTextSelectionToolbar(
          anchors: anchors,
          canQuote: canQuote,
          onQuote: _insertQuote,
          onCopyQuote: _copyQuote,
        );
      },
      child: SelectionArea(
        key: _selectionKey,
        // The app-owned overlay is also shown after a precise mouse drag. Keep
        // Flutter's platform menu disabled so touch does not draw both.
        contextMenuBuilder: (context, selectableRegionState) =>
            const SizedBox.shrink(),
        onSelectionChanged: _selectionChanged,
        child: widget.child,
      ),
    ),
  );
}

class _PostTextSelectionToolbar extends StatelessWidget {
  const _PostTextSelectionToolbar({
    required this.anchors,
    required this.canQuote,
    required this.onQuote,
    required this.onCopyQuote,
  });

  final TextSelectionToolbarAnchors anchors;
  final bool canQuote;
  final VoidCallback onQuote;
  final VoidCallback onCopyQuote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions =
        <({Key key, DIconData icon, String label, VoidCallback onPressed})>[
          if (canQuote)
            (
              key: const ValueKey('quote-selection'),
              icon: DIcons.quoteLeft,
              label: 'Quote',
              onPressed: onQuote,
            ),
          (
            key: const ValueKey('copy-quote-selection'),
            icon: DIcons.copy,
            label: 'Copy quote',
            onPressed: onCopyQuote,
          ),
        ];

    return TextSelectionToolbar(
      anchorAbove: anchors.primaryAnchor,
      anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
      toolbarBuilder: (context, child) => Material(
        color: theme.shell.floating,
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: theme.shell.divider),
        ),
        child: child,
      ),
      children: [
        for (var index = 0; index < actions.length; index++)
          TextSelectionToolbarTextButton(
            key: actions[index].key,
            padding: TextSelectionToolbarTextButton.getPadding(
              index,
              actions.length,
            ),
            onPressed: actions[index].onPressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DIcon(
                  actions[index].icon,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Text(actions[index].label),
              ],
            ),
          ),
      ],
    );
  }
}

typedef _MarkdownMark = ({String open, String close});

class _CookedSelectionCharacter {
  const _CookedSelectionCharacter(this.value, this.marks);

  final String value;
  final List<_MarkdownMark> marks;
}

class _CookedSelectionSource {
  _CookedSelectionSource(this.characters, this.breaks)
    : plainText = characters.map((character) => character.value).join();

  factory _CookedSelectionSource.fromHtml(String cooked) {
    final characters = <_CookedSelectionCharacter>[];
    final breaks = <int, int>{};

    void addBreak(int lines) {
      if (characters.isEmpty) return;
      final offset = characters.length;
      final current = breaks[offset] ?? 0;
      if (lines > current) breaks[offset] = lines;
    }

    void visit(dom.Node node, List<_MarkdownMark> marks) {
      if (node is dom.Text) {
        final value = node.data;
        for (var index = 0; index < value.length; index++) {
          characters.add(
            _CookedSelectionCharacter(
              value.substring(index, index + 1),
              List.unmodifiable(marks),
            ),
          );
        }
        return;
      }
      if (node is! dom.Element || _ignoredCookedElement(node)) return;
      if (node.localName == 'br') {
        addBreak(1);
        return;
      }

      final block = _cookedBlockElement(node);
      if (block) addBreak(2);
      final mark = _markdownMark(node);
      final childMarks = mark == null ? marks : [...marks, mark];
      for (final child in node.nodes) {
        visit(child, childMarks);
      }
      if (block) addBreak(2);
    }

    final fragment = html.parseFragment(cooked);
    for (final node in fragment.nodes) {
      visit(node, const []);
    }
    return _CookedSelectionSource(characters, breaks);
  }

  final List<_CookedSelectionCharacter> characters;
  final Map<int, int> breaks;
  final String plainText;

  String markdown(int start, int end) {
    if (start < 0 || end <= start || end > characters.length) return '';
    final out = StringBuffer();
    var active = <_MarkdownMark>[];

    void closeTo(int length) {
      for (var index = active.length - 1; index >= length; index--) {
        out.write(active[index].close);
      }
      active = active.sublist(0, length);
    }

    for (var offset = start; offset < end; offset++) {
      final lines = breaks[offset] ?? 0;
      if (offset > start && lines > 0) {
        closeTo(0);
        out.write(lines == 1 ? '\n' : '\n\n');
      }

      final next = characters[offset].marks;
      var shared = 0;
      while (shared < active.length &&
          shared < next.length &&
          active[shared] == next[shared]) {
        shared++;
      }
      closeTo(shared);
      for (var index = shared; index < next.length; index++) {
        out.write(next[index].open);
      }
      active = List.of(next);
      out.write(characters[offset].value);
    }
    closeTo(0);
    return out.toString().trim();
  }
}

bool _ignoredCookedElement(dom.Element element) =>
    const {'script', 'style'}.contains(element.localName) ||
    element.classes.contains('quote-controls');

bool _cookedBlockElement(dom.Element element) => const {
  'address',
  'aside',
  'blockquote',
  'div',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'li',
  'ol',
  'p',
  'pre',
  'table',
  'tr',
  'ul',
}.contains(element.localName);

_MarkdownMark? _markdownMark(dom.Element element) {
  switch (element.localName) {
    case 'b':
    case 'strong':
      return (open: '**', close: '**');
    case 'i':
    case 'em':
      return (open: '*', close: '*');
    case 'del':
    case 's':
    case 'strike':
      return (open: '~~', close: '~~');
    case 'code':
      return (open: '`', close: '`');
    case 'a':
      final href = element.attributes['href'];
      return href == null || href.isEmpty
          ? null
          : (open: '[', close: ']($href)');
    case 'kbd':
    case 'mark':
    case 'small':
    case 'big':
    case 'sup':
    case 'sub':
    case 'ins':
      final name = element.localName!;
      return (open: '<$name>', close: '</$name>');
  }
  return null;
}
