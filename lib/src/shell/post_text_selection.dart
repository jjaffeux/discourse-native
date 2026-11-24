import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';

import '../foundation/frame_safe_notifier.dart';
import '../models/post.dart';
import 'mobile_post_selection.dart';
import 'mobile_presentation.dart';
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
    this.displayedCooked,
  });

  final String siteUrl;
  final Post post;
  final int topicId;
  final Widget child;

  /// Presentation used for quoting; edits always target [post]'s source.
  final String? displayedCooked;

  @override
  State<PostTextSelection> createState() => _PostTextSelectionState();
}

class _PostTextSelectionState extends State<PostTextSelection> {
  String get _displayedCooked => widget.displayedCooked ?? widget.post.cooked;
  bool get _transformed => _displayedCooked != widget.post.cooked;
  static const Duration _toolbarDelay = Duration(milliseconds: 150);
  static const _emptySelection = PostTextSelectionResolution(
    markdown: '',
    editText: '',
    supportsFastEdit: false,
  );

  final GlobalKey<SelectionAreaState> _selectionKey = GlobalKey();
  final OverlayPortalController _portal = OverlayPortalController();

  Timer? _showTimer;
  TextSelectionToolbarAnchors? _anchors;
  FrameSafeValueNotifier<MobilePostSelection?>? _mobileSelection;
  ({Object history, Object entry})? _mobileVisit;
  ValueListenable<SelectableRegionSelectionStatus>? _selectionStatus;
  bool _canQuote = false;
  bool _canEdit = false;
  String _plainText = '';
  PostTextSelectionResolution _selection = _emptySelection;
  PostQuoteSelectionResolver? _quoteResolver;
  ScrollPosition? _scroll;

  bool get _active =>
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.isCurrentOf(context) != false;

  bool get _ownsMobileSelection =>
      identical(_mobileSelection?.value?.owner, this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mobile = MobilePostSelectionScope.maybeOf(context);
    final visit = mobile == null
        ? null
        : MobilePresentationScope.maybeOf(context)?.identity;
    final leftVisit =
        _mobileVisit != null &&
        (_mobileVisit != visit || !identical(_mobileSelection, mobile));
    if (leftVisit || !_active) {
      _releaseMobileSelection();
      _showTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (leftVisit || !_active)) {
          _dismiss(clearSelection: true);
        }
      });
    }
    _mobileSelection = visit == null ? null : mobile;
    _mobileVisit = visit;
    if (visit == null) _observeSelectionStatus(null);
    final position = visit == null
        ? Scrollable.maybeOf(context)?.position
        : null;
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
        oldWidget.displayedCooked != widget.displayedCooked ||
        oldWidget.post.isLocalized != widget.post.isLocalized) {
      _quoteResolver = null;
      _dismiss(clearSelection: true);
    }
  }

  void _hideWhileScrolling() => _dismiss(clearSelection: false);

  void _selectionChanged(SelectedContent? content) {
    _showTimer?.cancel();
    if (!_active) return;
    _plainText = content?.plainText ?? '';
    if (_plainText.isEmpty) {
      _selection = _emptySelection;
      // The handles can briefly coincide before a drag extends the range again.
      // Flutter publishes the gesture status after it reports the new range.
      if (content != null && _ownsMobileSelection) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _selectionStatusChanged(),
        );
      } else {
        _dismiss(clearSelection: false);
      }
      return;
    }
    _selection = (_quoteResolver ??= PostQuoteSelectionResolver(
      _displayedCooked,
    )).resolve(_plainText, isLocalized: widget.post.isLocalized);

    if (_mobileSelection != null) {
      _publishMobileSelection();
      return;
    }
    // Selection changes for every pointer move. Waiting briefly keeps the
    // menu from chasing the cursor while still feeling immediate on release.
    _showTimer = Timer(_toolbarDelay, _showToolbar);
  }

  void _observeSelectionStatus(
    ValueListenable<SelectableRegionSelectionStatus>? status,
  ) {
    if (identical(_selectionStatus, status)) return;
    _selectionStatus?.removeListener(_selectionStatusChanged);
    _selectionStatus = status?..addListener(_selectionStatusChanged);
  }

  void _selectionStatusChanged() {
    if (mounted &&
        _plainText.isEmpty &&
        _selectionStatus?.value != SelectableRegionSelectionStatus.changing) {
      _releaseMobileSelection();
    }
  }

  void _showToolbar() {
    if (!mounted || !_active || _plainText.isEmpty) {
      return;
    }
    final area = _selectionKey.currentState;
    if (area == null) return;

    final anchors = area.selectableRegion.contextMenuAnchors;
    setState(() => _anchors = anchors);
    if (!_portal.isShowing) _portal.show();
  }

  void _publishMobileSelection() {
    _mobileSelection?.value = (
      owner: this,
      visit: _mobileVisit!,
      actions: _actions,
    );
  }

  void _releaseMobileSelection() {
    if (_ownsMobileSelection) _mobileSelection?.value = null;
  }

  void _dismiss({required bool clearSelection}) {
    _showTimer?.cancel();
    _showTimer = null;
    _releaseMobileSelection();
    if (_portal.isShowing) _portal.hide();
    if (clearSelection) {
      _plainText = '';
      _selection = _emptySelection;
      _selectionKey.currentState?.selectableRegion.clearSelection();
    }
  }

  String get _quote => buildPostQuote(
    post: widget.post,
    topicId: widget.topicId,
    contents: _selectedText,
    config: ShellScope.read(context).siteConfigFor(widget.siteUrl),
  );

  String get _selectedText => _selection.markdown;

  PostTextSelectionActions get _actions {
    final hasQuote = _selectedText.trim().isNotEmpty;
    return (
      copy: _copyText,
      quote: hasQuote && _canQuote ? _insertQuote : null,
      copyQuote: hasQuote ? _copyQuote : null,
      edit: hasQuote && _canEdit ? _openEditSelection : null,
    );
  }

  void _copyText() => unawaited(
    _copy(
      _quoteResolver?.plainTextFor(_plainText) ?? _plainText,
      context.l10n.copied,
    ),
  );

  void _copyQuote() =>
      unawaited(_copy(_quote, context.l10n.quoteCopiedToClipboard));

  void _openEditSelection() => unawaited(_editSelection());

  void _insertQuote() {
    final quote = _quote;
    if (quote.isEmpty) return;
    final tab = ShellScope.tabOf(context);
    _dismiss(clearSelection: true);
    unawaited(tab.openQuote(widget.post, quote));
  }

  Future<void> _copy(String text, String confirmation) async {
    if (text.isEmpty) return;
    final restoringDock = _ownsMobileSelection;
    _dismiss(clearSelection: true);
    try {
      await Clipboard.setData(ClipboardData(text: text));
      // The dock can show the confirmation once it has replaced the tray.
      if (restoringDock) await WidgetsBinding.instance.endOfFrame;
      if (mounted) DToast.show(context, confirmation, type: DToastType.success);
    } on PlatformException {
      if (mounted) {
        DToast.show(context, appL10n.copyFailed, type: DToastType.error);
      }
    }
  }

  Future<void> _editSelection() async {
    final selection = _selection;
    if (selection.markdown.isEmpty) return;
    final controller = ShellScope.read(context);
    _dismiss(clearSelection: true);
    if (_transformed) {
      ShellScope.tabOf(context).openEdit(widget.post);
      return;
    }
    if (!selection.supportsFastEdit) {
      controller.openEdit(widget.post, focusText: selection.editText);
      return;
    }
    await showPostFastEditor(
      context: context,
      controller: controller,
      siteUrl: widget.siteUrl,
      topicId: widget.topicId,
      post: widget.post,
      selectedMarkdown: selection.editText,
    );
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _observeSelectionStatus(null);
    _releaseMobileSelection();
    _scroll?.removeListener(_hideWhileScrolling);
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ForumTabSelector<({bool canQuote, bool canEdit})>(
    select: (controller, tab) => (
      canQuote: tab.canReplyHere,
      canEdit:
          widget.post.canEdit &&
          controller.siteConfigFor(widget.siteUrl).fastEditEnabled,
    ),
    builder: (context, permissions, _) {
      _canQuote = permissions.canQuote;
      _canEdit = permissions.canEdit;
      if (_active && _plainText.isNotEmpty && _ownsMobileSelection) {
        _publishMobileSelection();
      }
      return OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) {
          final anchors = _anchors;
          if (!_active || anchors == null || _plainText.isEmpty) {
            return const SizedBox.shrink();
          }
          return _PostTextSelectionToolbar(
            anchors: anchors,
            onDismiss: () => _dismiss(clearSelection: false),
            actions: _actions,
          );
        },
        child: CallbackShortcuts(
          bindings: {
            if (permissions.canEdit)
              const CharacterActivator('e'): _openEditSelection,
          },
          child: RouteAwareSelectionArea(
            selectionAreaKey: _selectionKey,
            // The app presents its own actions, while Flutter owns the handles.
            contextMenuBuilder: (context, selectableRegionState) =>
                const SizedBox.shrink(),
            onSelectionChanged: _selectionChanged,
            child: _mobileSelection == null
                ? widget.child
                : Builder(
                    builder: (context) {
                      _observeSelectionStatus(
                        SelectableRegionSelectionStatusScope.maybeOf(context),
                      );
                      return widget.child;
                    },
                  ),
          ),
        ),
      );
    },
  );
}

class _PostTextSelectionToolbar extends StatelessWidget {
  const _PostTextSelectionToolbar({
    required this.anchors,
    required this.onDismiss,
    required this.actions,
  });

  final TextSelectionToolbarAnchors anchors;
  final VoidCallback onDismiss;
  final PostTextSelectionActions actions;

  @override
  Widget build(BuildContext context) {
    final anchor = Rect.fromPoints(
      anchors.primaryAnchor,
      anchors.secondaryAnchor ?? anchors.primaryAnchor,
    ).inflate(.5);
    return Positioned.fromRect(
      rect: anchor,
      child: IgnorePointer(
        child: DDropdownMenu(
          open: true,
          restoreFocus: false,
          onOpenChange: (open, _) {
            if (!open) onDismiss();
          },
          content: DDropdownMenuContent(
            side: DPopoverSide.top,
            align: DPopoverAlign.center,
            width: null,
            autofocus: false,
            scrollable: false,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  for (final item in postTextSelectionItems(context, actions))
                    DButton(
                      key: ValueKey(item.id),
                      label: Text(item.label),
                      onPressed: item.onPressed,
                      variant: DButtonVariant.ghost,
                      size: DButtonSize.toolbar,
                    ),
                ],
              ),
            ],
          ),
          child: const DPopoverAnchor(child: SizedBox.expand()),
        ),
      ),
    );
  }
}
