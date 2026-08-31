import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_layout.dart';
import 'avatar_image.dart';
import 'composer_autocomplete.dart';
import 'composer_controller.dart';
import 'emoji.dart';
import 'emoji_picker.dart';
import 'shell_metrics.dart';
import 'user_status.dart';

typedef ComposerSuggestionActionHandler =
    Future<void> Function({
      required BuildContext context,
      required ComposerController composer,
      required ComposerSuggestion suggestion,
      Rect? anchor,
    });

class ComposerSuggestionField extends StatefulWidget {
  const ComposerSuggestionField({
    super.key,
    required this.composer,
    required this.field,
    this.onAction,
  });

  final ComposerController composer;

  final Widget field;

  final ComposerSuggestionActionHandler? onAction;

  @override
  State<ComposerSuggestionField> createState() =>
      _ComposerSuggestionFieldState();
}

class _ComposerSuggestionFieldState extends State<ComposerSuggestionField> {
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _anchorKey = GlobalKey();
  final ValueNotifier<Rect?> _anchor = ValueNotifier<Rect?>(null);

  late ComposerAutocomplete _popup;
  Object? _popupSyncToken;

  @override
  void initState() {
    super.initState();
    _popup = widget.composer.autocomplete;
    _popup.addListener(_onPopupChanged);
    _syncPopupAfterLayout(_popup);
  }

  @override
  void didUpdateWidget(ComposerSuggestionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.composer.autocomplete;
    if (identical(_popup, next)) {
      if (next.isOpen) _syncPopupAfterLayout(next);
      return;
    }

    _popup.removeListener(_onPopupChanged);
    _popup = next;
    _popup.addListener(_onPopupChanged);
    _syncPopupAfterLayout(next);
  }

  void _syncPopupAfterLayout(ComposerAutocomplete expected) {
    final token = Object();
    _popupSyncToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!identical(_popupSyncToken, token)) return;
      _popupSyncToken = null;
      if (!mounted || !identical(_popup, expected)) return;
      _onPopupChanged();
    });
  }

  @override
  void dispose() {
    _popupSyncToken = null;
    _popup.removeListener(_onPopupChanged);
    _anchor.dispose();
    super.dispose();
  }

  void _onPopupChanged() {
    if (!mounted) return;
    if (_popup.isOpen) {
      _anchor.value = _anchorRect();
      _portal.show();
    } else {
      _portal.hide();
    }
  }

  Rect? _anchorRect() => anchorRect(
    anchor: _anchorKey.currentContext?.findRenderObject() as RenderBox?,
    overlay: Overlay.of(context).context.findRenderObject() as RenderBox?,
  );

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_popup.isOpen) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _popup.moveSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _popup.moveSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _popup.dismiss();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.tab:
        // Cmd+Enter is the send shortcut and stays the send shortcut. An open
        // list must not be what decides when a reply is posted.
        if (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed) {
          return KeyEventResult.ignored;
        }
        _accept();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _accept() {
    final choice = _popup.selected;
    if (choice != null) _activate(choice);
  }

  void _activate(ComposerSuggestion choice) {
    if (choice.action == null) {
      widget.composer.acceptSuggestion(choice);
      return;
    }

    _popup.close();
    widget.onAction
        ?.call(
          context: _anchorKey.currentContext ?? context,
          composer: widget.composer,
          suggestion: choice,
          anchor: _anchor.value,
        )
        .ignore();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => ValueListenableBuilder<Rect?>(
          valueListenable: _anchor,
          builder: (context, anchor, child) => CustomSingleChildLayout(
            delegate: AnchoredLayout(
              anchor: anchor,
              maxWidth: composerSuggestionsWidth,
              preferAbove: true,
            ),
            child: child!,
          ),
          child: _Suggestions(composer: widget.composer, onTap: _activate),
        ),
        child: EmojiPickerAnchor(
          child: KeyedSubtree(key: _anchorKey, child: widget.field),
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.composer, required this.onTap});

  final ComposerController composer;
  final ValueChanged<ComposerSuggestion> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: composer.autocomplete,
      builder: (context, _) {
        final popup = composer.autocomplete;
        if (!popup.isOpen) return const SizedBox.shrink();

        return Material(
          color: theme.shell.floating,
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: composerSuggestionsWidth,
            decoration: BoxDecoration(
              border: Border.all(color: theme.shell.divider),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, suggestion) in popup.suggestions.indexed)
                  _SuggestionRow(
                    suggestion: suggestion,
                    isSelected: index == popup.selectedIndex,
                    onTap: () => onTap(suggestion),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.isSelected,
    required this.onTap,
  });

  final ComposerSuggestion suggestion;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      // Not an InkWell: it asks for focus when tapped, and taking focus off
      // the field drops the caret and closes this list before the tap has
      // resolved into a completion.
      child: Semantics(
        button: true,
        selected: isSelected,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: composerSuggestionRowHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: isSelected ? theme.shell.hover : null,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: switch (suggestion.art) {
                    null => null,
                    // No `alt`: the name is already written beside it, and
                    // artwork that will not load should leave a gap rather than
                    // print the shortcode twice on the same row.
                    ArtImage(:final url) => EmojiImage(
                      url: url,
                      size: 20,
                      alt: '',
                    ),
                    ArtAvatar(:final url) => ClipOval(
                      child: AvatarImage(
                        url: url,
                        size: 22,
                        fallback: const SizedBox.shrink(),
                      ),
                    ),
                    ArtSquare(:final colorValues) => Center(
                      child: _Swatch(colorValues: colorValues),
                    ),
                    ArtIcon(:final name, :final colorValue, :final fallback) =>
                      DIcon(
                        name == null
                            ? fallback
                            : DIcons.byName[name] ?? fallback,
                        size: 18,
                        color: colorValue == null
                            ? theme.colorScheme.onSurfaceVariant
                            : Color(colorValue),
                      ),
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          suggestion.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (suggestion.detail case final detail?) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if ((suggestion.siteUrl, suggestion.userStatus) case (
                  final siteUrl?,
                  final status?,
                ))
                  UserStatusMessage(
                    siteUrl: siteUrl,
                    userId: suggestion.userId,
                    status: status,
                    showDescription: true,
                    size: 15,
                    style: theme.textTheme.bodySmall,
                    leadingGap: 8,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.colorValues});

  final List<int> colorValues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = [for (final value in colorValues) Color(value)];
    final fill = colors.isEmpty
        ? theme.colorScheme.onSurfaceVariant
        : colors.last;
    final parent = colors.length >= 2 ? colors.first : null;

    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: parent == null ? fill : null,
        gradient: parent == null
            ? null
            : LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [parent, parent, fill, fill],
                stops: const [0, 0.5, 0.5, 1],
              ),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
