import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import 'shell_controller.dart';
import 'shell_sheet.dart';

class TopicProgressButton extends StatelessWidget {
  const TopicProgressButton({
    super.key,
    required this.position,
    required this.total,
    required this.onPressed,
  });

  final int position;
  final int total;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final boundedPosition = position.clamp(1, total);
    return Tooltip(
      message: 'Topic progress',
      child: Semantics(
        button: true,
        label: 'Topic progress, post $boundedPosition of $total',
        child: Material(
          color: theme.shell.floating,
          borderRadius: BorderRadius.circular(4),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('topic-progress-button'),
            onTap: onPressed,
            child: SizedBox(
              width: 72,
              height: 32,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: boundedPosition / total,
                        child: ColoredBox(
                          key: const ValueKey('topic-progress-fill'),
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.18,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      '$boundedPosition / $total',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showTopicProgress({
  required BuildContext context,
  required ShellController controller,
  required int position,
  required int total,
}) => showShellSheet<void>(
  context: context,
  title: 'Topic progress',
  dialogOnDesktop: true,
  builder: (context) => _TopicProgressEditor(
    controller: controller,
    position: position,
    total: total,
  ),
);

class _TopicProgressEditor extends StatefulWidget {
  const _TopicProgressEditor({
    required this.controller,
    required this.position,
    required this.total,
  });

  final ShellController controller;
  final int position;
  final int total;

  @override
  State<_TopicProgressEditor> createState() => _TopicProgressEditorState();
}

class _TopicProgressEditorState extends State<_TopicProgressEditor> {
  late int _selected = widget.position.clamp(1, widget.total);
  bool _jumping = false;
  String? _error;

  Future<void> _jump([int? position]) async {
    if (_jumping) return;
    final target = (position ?? _selected).clamp(1, widget.total);
    setState(() {
      _selected = target;
      _jumping = true;
      _error = null;
    });
    final opened = await widget.controller.jumpToCurrentTopicIndex(target);
    if (!mounted) return;
    if (opened) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _jumping = false;
      _error = 'Could not open that post. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Post $_selected of ${widget.total}',
          key: const ValueKey('topic-progress-selection'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Slider(
          key: const ValueKey('topic-progress-slider'),
          value: _selected.toDouble(),
          min: 1,
          max: widget.total.toDouble(),
          label: 'Post $_selected',
          onChanged: _jumping
              ? null
              : (value) => setState(() => _selected = value.round()),
        ),
        if (_error case final error?) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            DButton(
              label: const Text('First post'),
              onPressed: _jumping ? null : () => unawaited(_jump(1)),
            ),
            DButton(
              key: const ValueKey('topic-progress-jump'),
              label: const Text('Jump'),
              onPressed: () => unawaited(_jump()),
              variant: DButtonVariant.primary,
              loading: _jumping,
            ),
            DButton(
              label: const Text('Latest post'),
              onPressed: _jumping ? null : () => unawaited(_jump(widget.total)),
            ),
          ],
        ),
      ],
    );
  }
}
