import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
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
  });

  final ComposerController composer;

  final Widget field;

  final ComposerSuggestionActionHandler? onAction;

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
    _command.dispose();
    super.dispose();
  }

  void _onPopupChanged() {
    if (!mounted) return;
    if (_popup.isOpen && widget.composer.isEditing) {
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
            child: CustomSingleChildLayout(
              delegate: AnchoredLayout(
                anchor: anchor,
                maxWidth: composerSuggestionsWidth,
                preferAbove: true,
              ),
              child: child!,
            ),
          ),
          child: _Suggestions(
            composer: widget.composer,
            controller: _command,
            onTap: _activate,
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
  });

  final ComposerController composer;
  final DCommandController<ComposerSuggestion> controller;
  final ValueChanged<ComposerSuggestion> onTap;

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
                  Padding(
                    padding: const EdgeInsets.all(DSpacing.md),
                    child: Text(
                      context.l10n.mentionSearchHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DTokens.of(context).mutedForeground,
                      ),
                    ),
                  ),
                Flexible(
                  child: DCommandList<ComposerSuggestion>(
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
