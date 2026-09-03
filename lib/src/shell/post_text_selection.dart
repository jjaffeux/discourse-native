import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';

import '../models/post.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'post_fast_edit.dart';
import 'post_quote.dart';
import 'route_aware_selection_area.dart';
import 'shell_scope.dart';

class PostTextSelection extends StatefulWidget {
  const PostTextSelection({
    super.key,
    required this.siteUrl,
    required this.post,
    required this.topicId,
    required this.child,
  });

  final String siteUrl;
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
  PostTextSelectionResolution _selection = const PostTextSelectionResolution(
    markdown: '',
    supportsFastEdit: false,
  );
  PostQuoteSelectionResolver? _quoteResolver;
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
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.post.id != widget.post.id ||
        oldWidget.post.cooked != widget.post.cooked ||
        oldWidget.post.isLocalized != widget.post.isLocalized) {
      _quoteResolver = null;
      _dismiss(clearSelection: true);
    }
  }

  void _hideWhileScrolling() => _dismiss(clearSelection: false);

  void _selectionChanged(SelectedContent? content) {
    _showTimer?.cancel();
    _selection = (_quoteResolver ??= PostQuoteSelectionResolver(
      widget.post.cooked,
    )).resolve(content?.plainText ?? '', isLocalized: widget.post.isLocalized);
    if (_selection.markdown.isEmpty) {
      _dismiss(clearSelection: false);
      return;
    }

    // Selection changes for every pointer move. Waiting briefly keeps the
    // menu from chasing the cursor while still feeling immediate on release.
    _showTimer = Timer(_toolbarDelay, _showToolbar);
  }

  void _showToolbar() {
    if (!mounted || _selection.markdown.isEmpty) return;
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

  String get _selectedText => _selection.markdown;

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

  Future<void> _editSelection() async {
    final selection = _selection;
    if (selection.markdown.isEmpty) return;
    final controller = ShellScope.read(context);
    _dismiss(clearSelection: true);
    if (!selection.supportsFastEdit) {
      controller.openEdit(widget.post, focusText: selection.markdown);
      return;
    }
    await showPostFastEditor(
      context: context,
      controller: controller,
      siteUrl: widget.siteUrl,
      topicId: widget.topicId,
      post: widget.post,
      selectedMarkdown: selection.markdown,
    );
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _scroll?.removeListener(_hideWhileScrolling);
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ShellSelector<({bool canQuote, bool canEdit})>(
    select: (controller) => (
      canQuote: controller.canReplyHere,
      canEdit:
          widget.post.canEdit &&
          controller.siteConfigFor(widget.siteUrl).fastEditEnabled,
    ),
    builder: (context, actions, _) => OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        final anchors = _anchors;
        if (anchors == null || _selection.markdown.isEmpty) {
          return const SizedBox.shrink();
        }
        return _PostTextSelectionToolbar(
          anchors: anchors,
          canQuote: actions.canQuote,
          canEdit: actions.canEdit,
          onQuote: _insertQuote,
          onEdit: () => unawaited(_editSelection()),
          onCopyQuote: _copyQuote,
        );
      },
      child: CallbackShortcuts(
        bindings: {
          if (actions.canEdit)
            const CharacterActivator('e'): () => unawaited(_editSelection()),
        },
        child: RouteAwareSelectionArea(
          selectionAreaKey: _selectionKey,
          // The app-owned overlay is also shown after a precise mouse drag. Keep
          // Flutter's platform menu disabled so touch does not draw both.
          contextMenuBuilder: (context, selectableRegionState) =>
              const SizedBox.shrink(),
          onSelectionChanged: _selectionChanged,
          child: widget.child,
        ),
      ),
    ),
  );
}

class _PostTextSelectionToolbar extends StatelessWidget {
  const _PostTextSelectionToolbar({
    required this.anchors,
    required this.canQuote,
    required this.canEdit,
    required this.onQuote,
    required this.onEdit,
    required this.onCopyQuote,
  });

  final TextSelectionToolbarAnchors anchors;
  final bool canQuote;
  final bool canEdit;
  final VoidCallback onQuote;
  final VoidCallback onEdit;
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
          if (canEdit)
            (
              key: const ValueKey('edit-selection'),
              icon: DIcons.pencil,
              label: 'Edit',
              onPressed: onEdit,
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
