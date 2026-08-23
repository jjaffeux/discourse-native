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

typedef ComposerSuggestionActionHandler =
    Future<void> Function({
      required BuildContext context,
      required ComposerController composer,
      required ComposerSuggestion suggestion,
      Rect? anchor,
    });

/// The composer's text field, with the completion list over it.
///
/// The list has to draw outside the composer panel — it is 220px tall and the
/// list would have nowhere to go inside it — so it is an [OverlayPortal],
/// positioned by [AnchoredLayout], the way every other floating panel in the
/// shell is.
class ComposerSuggestionField extends StatefulWidget {
  const ComposerSuggestionField({
    super.key,
    required this.composer,
    required this.field,
    this.onAction,
  });

  final ComposerController composer;

  /// The field itself, built by the panel — this widget only wraps it.
  final Widget field;

  /// Handles rows that open a secondary surface instead of completing text.
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

  /// The field's own box, in the overlay's coordinates.
  ///
  /// The whole field rather than the caret: reaching the caret's rect means
  /// reaching into `RenderEditable`, which `TextField` does not expose, and a
  /// list that followed the caret around a 220px panel would jitter under the
  /// cursor while somebody typed.
  Rect? _anchorRect() => anchorRect(
    anchor: _anchorKey.currentContext?.findRenderObject() as RenderBox?,
    overlay: Overlay.of(context).context.findRenderObject() as RenderBox?,
  );

  /// Keys the list claims, and only while it has something to claim them for.
  ///
  /// A plain [Focus] rather than another `CallbackShortcuts`, which is the
  /// trap here: that widget reports a key handled whenever one of its
  /// activators matches, whatever its callback did. A second one binding
  /// Escape would therefore swallow Escape even with no list open, and the
  /// composer would stop closing. This returns [KeyEventResult.ignored] and
  /// lets the panel's own binding have it.
  ///
  /// It sits between the panel's bindings and the field, which is what puts it
  /// nearer the focused node than either — near enough to see Escape before
  /// `closeComposer`, and the arrows before `DefaultTextEditingShortcuts`
  /// moves the caret.
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
                    ArtIcon(:final name, :final colorValue) => DIcon(
                      name == null
                          ? DIcons.tag
                          : DIcons.byName[name] ?? DIcons.tag,
                      size: 18,
                      color: colorValue == null
                          ? theme.colorScheme.onSurfaceVariant
                          : Color(colorValue),
                    ),
                  },
                ),
                const SizedBox(width: 10),
                Text(
                  suggestion.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
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
        ),
      ),
    );
  }
}

/// A category's colour, split down the middle for a subcategory the way the
/// hashtag pill does it — parent on the left, child on the right.
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
