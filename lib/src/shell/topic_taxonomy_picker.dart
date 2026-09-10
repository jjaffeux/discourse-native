import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'platform.dart';

/// Adapts the topic editors' result callbacks to the Native overlay owners.
/// The popover remains attached to the real control as its layout changes.
class TopicTaxonomyPickerAnchor extends StatefulWidget {
  const TopicTaxonomyPickerAnchor({super.key, required this.child});

  final Widget child;

  /// Opens an editor for a control below this anchor and returns its result.
  static Future<T?> show<T>({
    required BuildContext anchorContext,
    required String title,
    required Key popoverKey,
    required Widget Function(BuildContext, ValueChanged<T?>) builder,
  }) => anchorContext
      .findAncestorStateOfType<_TopicTaxonomyPickerAnchorState>()!
      .show<T>(title: title, popoverKey: popoverKey, builder: builder);

  @override
  State<TopicTaxonomyPickerAnchor> createState() =>
      _TopicTaxonomyPickerAnchorState();
}

class _TopicTaxonomyPickerAnchorState extends State<TopicTaxonomyPickerAnchor> {
  Completer<Object?>? _result;
  Widget _content = const SizedBox.shrink();
  String? _title;
  Key? _popoverKey;
  bool _open = false;

  Future<T?> show<T>({
    required String title,
    required Key popoverKey,
    required Widget Function(BuildContext, ValueChanged<T?>) builder,
  }) {
    if (context.isTouch) {
      return showDDrawer<T>(
        context: context,
        barrierLabel: 'Dismiss ${title.toLowerCase()} picker',
        showSwipeHandle: true,
        builder: (context, drawer) => DDrawerContent(
          semanticLabel: title,
          height: 440,
          children: [
            DDrawerHeader(children: [DDrawerTitle(child: Text(title))]),
            Expanded(child: builder(context, drawer.close)),
          ],
        ),
      );
    }
    _result?.complete(null);
    final result = Completer<Object?>();
    setState(() {
      _result = result;
      _title = title;
      _popoverKey = popoverKey;
      _content = KeyedSubtree(
        key: UniqueKey(),
        child: Builder(
          builder: (context) => builder(context, (value) {
            if (identical(_result, result)) _close(value);
          }),
        ),
      );
      _open = true;
    });
    return result.future.then((value) => value as T?);
  }

  void _close([Object? value]) {
    final result = _result;
    _result = null;
    if (_open) setState(() => _open = false);
    result?.complete(value);
  }

  @override
  void dispose() {
    _result?.complete(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DPopover(
    open: _open,
    onOpenChange: (open, _) {
      if (!open) _close();
    },
    content: DPopoverContent(
      key: _popoverKey,
      semanticLabel: _title,
      align: DPopoverAlign.start,
      collisionPadding: 10,
      padding: EdgeInsets.zero,
      scrollable: false,
      constraints: const BoxConstraints(maxHeight: 360),
      child: _content,
    ),
    child: DPopoverAnchor(child: widget.child),
  );
}

/// Shared search and independently scrolling results for topic taxonomy.
class TopicTaxonomyPickerContent extends StatelessWidget {
  const TopicTaxonomyPickerContent({
    super.key,
    required this.queryKey,
    required this.queryController,
    required this.queryHint,
    required this.onQueryChanged,
    required this.onQuerySubmitted,
    required this.children,
    this.separatorKey,
  });

  final Key queryKey;
  final TextEditingController queryController;
  final String queryHint;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onQuerySubmitted;
  final List<Widget> children;
  final Key? separatorKey;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: DInput(
          key: queryKey,
          controller: queryController,
          hintText: queryHint,
          semanticLabel: queryHint,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: onQueryChanged,
          onSubmitted: onQuerySubmitted,
        ),
      ),
      DSeparator(key: separatorKey),
      Flexible(
        child: DScrollArea(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ],
  );
}

class TopicTaxonomyPickerMessage extends StatelessWidget {
  const TopicTaxonomyPickerMessage(
    this.message, {
    super.key,
    this.error = false,
  });

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: error
            ? DTokens.of(context).destructive
            : DTokens.of(context).mutedForeground,
      ),
    ),
  );
}

class TopicTaxonomyPickerProgress extends StatelessWidget {
  const TopicTaxonomyPickerProgress({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(20),
    child: Center(child: DSpinner(semanticLabel: 'Loading choices')),
  );
}
