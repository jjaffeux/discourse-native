import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter/services.dart';

import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import 'anchored_layout.dart';
import 'avatar_image.dart';
import 'composer_autocomplete.dart';
import 'composer_controller.dart';
import 'composer_triggers.dart';
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
    this.onModifiedEnter,
    this.renderEditable,
    this.scroll,
  });

  final ComposerController composer;

  final Widget field;

  final ComposerSuggestionActionHandler? onAction;
  final KeyEventResult Function(KeyEvent)? onModifiedEnter;
  final RenderEditable? Function()? renderEditable;
  final Listenable? scroll;

  @override
  State<ComposerSuggestionField> createState() =>
      _ComposerSuggestionFieldState();
}

class _ComposerSuggestionFieldState extends State<ComposerSuggestionField> {
  final DCommandController<ComposerSuggestion> _command =
      DCommandController<ComposerSuggestion>();
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _anchorKey = GlobalKey();
  final ValueNotifier<Rect?> _anchor = ValueNotifier<Rect?>(null);
  final FocusNode _searchFocus = FocusNode(debugLabel: 'Mention search');

  late ComposerAutocomplete _popup;
  Object? _popupSyncToken;

  @override
  void initState() {
    super.initState();
    _searchFocus.onKeyEvent = _onSearchKey;
    _popup = widget.composer.autocomplete;
    _popup.addListener(_onPopupChanged);
    widget.scroll?.addListener(_onPopupChanged);
    _syncPopupAfterLayout(_popup);
  }

  @override
  void didUpdateWidget(ComposerSuggestionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scroll != widget.scroll) {
      oldWidget.scroll?.removeListener(_onPopupChanged);
      widget.scroll?.addListener(_onPopupChanged);
    }
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
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!identical(_popupSyncToken, token)) return;
      _popupSyncToken = null;
      if (!mounted || !identical(_popup, expected)) return;
      _syncPopup();
    });
  }

  @override
  void dispose() {
    _popupSyncToken = null;
    _popup.removeListener(_onPopupChanged);
    widget.scroll?.removeListener(_onPopupChanged);
    _anchor.dispose();
    _searchFocus.dispose();
    _command.dispose();
    super.dispose();
  }

  void _onPopupChanged() {
    _syncPopupAfterLayout(_popup);
  }

  void _syncPopup() {
    if (!mounted) return;
    if (_popup.isOpen && widget.composer.isEditing) {
      final opening = !_portal.isShowing;
      _anchor.value = _anchorRect();
      _portal.show();
      if (opening && _popup.trigger?.kind == ComposerTriggerKind.mention) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _portal.isShowing &&
              _popup.trigger?.kind == ComposerTriggerKind.mention) {
            _searchFocus.requestFocus();
          }
        });
      }
    } else {
      _portal.hide();
      if (_searchFocus.hasFocus && widget.composer.isEditing) {
        widget.composer.focus.requestFocus();
      }
    }
  }

  Rect? _anchorRect() {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final trigger = _popup.trigger;
    final editable = widget.renderEditable?.call();
    if (trigger?.kind == ComposerTriggerKind.mention &&
        editable != null &&
        editable.attached &&
        editable.hasSize &&
        overlay != null &&
        overlay.attached) {
      // The trigger stays on the same line while the menu's input is edited.
      // Read its geometry after layout, never from the previous text frame.
      final caret = editable.getLocalRectForCaret(
        TextPosition(offset: trigger!.start),
      );
      return Rect.fromPoints(
        editable.localToGlobal(caret.topLeft, ancestor: overlay),
        editable.localToGlobal(caret.bottomRight, ancestor: overlay),
      );
    }
    return anchorRect(
      anchor: _anchorKey.currentContext?.findRenderObject() as RenderBox?,
      overlay: overlay,
    );
  }

  void _filterMentions(String query) {
    final composer = widget.composer;
    final trigger = _popup.trigger;
    if (!composer.isEditing || trigger?.kind != ComposerTriggerKind.mention) {
      return;
    }
    final value = composer.text.value;
    composer.text.value = TextEditingValue(
      text: value.text.replaceRange(trigger!.start + 1, trigger.end, query),
      selection: TextSelection.collapsed(
        offset: trigger.start + 1 + query.length,
      ),
    );
  }

  void _dismiss() {
    _popup.dismiss();
    if (widget.composer.isEditing) widget.composer.focus.requestFocus();
  }

  void _removeEmptyMention() {
    final composer = widget.composer;
    final trigger = _popup.trigger;
    if (!composer.isEditing ||
        trigger?.kind != ComposerTriggerKind.mention ||
        trigger!.query.isNotEmpty) {
      return;
    }
    composer.text.value = TextEditingValue(
      text: composer.text.text.replaceRange(trigger.start, trigger.end, ''),
      selection: TextSelection.collapsed(offset: trigger.start),
    );
    _dismiss();
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      final keyboard = HardwareKeyboard.instance;
      if (keyboard.isMetaPressed || keyboard.isControlPressed) {
        // The mention input lives in an overlay. Forward send shortcuts to
        // the editor's handlers before the command list accepts a person.
        for (final ancestor in widget.composer.focus.ancestors) {
          final result = ancestor.onKeyEvent?.call(ancestor, event);
          if (result != null && result != KeyEventResult.ignored) return result;
        }
        return KeyEventResult.skipRemainingHandlers;
      } else if (keyboard.isShiftPressed) {
        _dismiss();
        FocusManager.instance.applyFocusChangesIfNeeded();
        return widget.onModifiedEnter?.call(event) ?? KeyEventResult.ignored;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_popup.isOpen || !widget.composer.isEditing) {
      return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.arrowUp:
        if (_popup.suggestions.isEmpty) return KeyEventResult.ignored;
        return _command.handleKeyEvent(
          event,
          isComposing: widget.composer.text.value.composing.isValid,
        );
      case LogicalKeyboardKey.escape:
        _dismiss();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.tab:
        // Modified Enter belongs to the editor's send and newline shortcuts.
        // An open list must not turn either shortcut into choosing an item.
        if (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isShiftPressed) {
          return KeyEventResult.ignored;
        }
        if (_popup.selected == null ||
            widget.composer.text.value.composing.isValid) {
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
    if (!widget.composer.isEditing) return;
    if (choice.action == null) {
      widget.composer.acceptSuggestion(choice);
      widget.composer.focus.requestFocus();
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
          builder: (context, anchor, child) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final mention =
                    _popup.trigger?.kind == ComposerTriggerKind.mention;
                final availableHeight = (constraints.maxHeight - 24).clamp(
                  0.0,
                  double.infinity,
                );
                final above = ((anchor?.top ?? 0) - 20).clamp(
                  0.0,
                  availableHeight,
                );
                final below =
                    (constraints.maxHeight - (anchor?.bottom ?? 0) - 20).clamp(
                      0.0,
                      availableHeight,
                    );
                final preferAbove = !mention || above >= below;
                return CustomSingleChildLayout(
                  delegate: AnchoredLayout(
                    anchor: anchor,
                    maxWidth: composerSuggestionsWidth,
                    preferAbove: preferAbove,
                    keepPreferredPlacement: mention && preferAbove,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: mention
                          ? (preferAbove ? above : below)
                          : double.infinity,
                    ),
                    child: child!,
                  ),
                );
              },
            ),
          ),
          child: TapRegion(
            onTapOutside: (_) => _popup.dismiss(),
            child: _Suggestions(
              composer: widget.composer,
              controller: _command,
              searchFocus: _searchFocus,
              onQueryChanged: _filterMentions,
              onEmptyBackspace: _removeEmptyMention,
              onDismiss: _dismiss,
              onTap: _activate,
            ),
          ),
        ),
        child: EmojiPickerAnchor(
          child: KeyedSubtree(key: _anchorKey, child: widget.field),
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.composer,
    required this.controller,
    required this.onTap,
    required this.searchFocus,
    required this.onQueryChanged,
    required this.onEmptyBackspace,
    required this.onDismiss,
  });

  final ComposerController composer;
  final DCommandController<ComposerSuggestion> controller;
  final ValueChanged<ComposerSuggestion> onTap;
  final FocusNode searchFocus;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onEmptyBackspace;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: composer.autocomplete,
      builder: (context, _) {
        final popup = composer.autocomplete;
        if (!popup.isOpen) return const SizedBox.shrink();
        final mention = popup.trigger?.kind == ComposerTriggerKind.mention;
        return SizedBox(
          width: composerSuggestionsWidth,
          child: DCommand<ComposerSuggestion>(
            controller: controller,
            query: mention ? popup.trigger!.query : '',
            onQueryChanged: mention ? onQueryChanged : null,
            onEscape: onDismiss,
            value: popup.selected,
            onValueChanged: popup.highlight,
            onSelected: onTap,
            shouldFilter: false,
            loop: true,
            outlined: true,
            backgroundColor: Theme.of(context).shell.floating,
            loading: popup.isLoading && popup.suggestions.isEmpty,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (mention)
                  DCommandInput<ComposerSuggestion>(
                    focusNode: searchFocus,
                    onEmptyBackspace: onEmptyBackspace,
                    placeholder: context.l10n.mentionSearchHint,
                    semanticLabel: context.l10n.searchUsersOrGroups,
                  ),
                Flexible(
                  child: DCommandList<ComposerSuggestion>(
                    height: mention ? 288 : null,
                    children: [
                      if (mention) ...[
                        const DCommandLoading(child: DSpinner()),
                        DCommandEmpty(
                          child: Text(
                            popup.hasError
                                ? context.l10n.mentionSearchFailed
                                : popup.trigger!.query.isEmpty
                                ? context.l10n.searchUsersOrGroups
                                : context.l10n.noUsersOrGroupsFound,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      for (final suggestion in popup.suggestions)
                        DCommandItem<ComposerSuggestion>(
                          value: suggestion,
                          searchValue: suggestion.label,
                          semanticLabel: [
                            suggestion.label,
                            ?suggestion.detail,
                            ?suggestion.userStatus?.description,
                          ].join(', '),
                          leading: _SuggestionArt(suggestion: suggestion),
                          trailing: switch ((
                            suggestion.siteUrl,
                            suggestion.userStatus,
                          )) {
                            (final siteUrl?, final status?) =>
                              UserStatusMessage(
                                siteUrl: siteUrl,
                                userId: suggestion.userId,
                                status: status,
                                showDescription: true,
                                size: 15,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            _ => null,
                          },
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  suggestion.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (suggestion.detail case final detail?) ...[
                                const SizedBox(width: DSpacing.sm),
                                Expanded(
                                  child: Text(
                                    detail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: DTokens.of(
                                        context,
                                      ).mutedForeground,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SuggestionArt extends StatelessWidget {
  const _SuggestionArt({required this.suggestion});

  final ComposerSuggestion suggestion;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 22,
    child: switch (suggestion.art) {
      null => null,
      ArtImage(:final url) => EmojiImage(url: url, size: 20, alt: ''),
      ArtAvatar(:final url) => DAvatar.frame(
        child: AvatarImage(
          url: url,
          size: 22,
          fallback: const SizedBox.shrink(),
        ),
      ),
      ArtSquare(:final colorValues) => Center(
        child: _Swatch(colorValues: colorValues),
      ),
      ArtIcon(:final name, :final colorValue, :final fallback) => DIcon(
        name == null ? fallback : pluginIconNamed(context, name) ?? fallback,
        size: 18,
        color: colorValue == null
            ? DTokens.of(context).mutedForeground
            : Color(colorValue),
      ),
    },
  );
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
