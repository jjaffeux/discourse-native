import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final textRevisionPreviewExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Preview the source words a discard removes and restores.',
  notes:
      'The live editor stays mounted. Hover or keyboard focus previews a '
      'Native action without expanding its hit area. Supply a restoration '
      'animation only after persistence succeeds; reduced motion shows the '
      'saved text immediately. Removed words are struck through and both '
      'change kinds have explicit screen reader labels.',
  examples: [
    for (final reduced in [false, true])
      StyleguideExample(
        title: reduced ? 'Reduced motion' : 'Discard preview',
        description:
            'Edit the text, then hover or focus Discard changes. '
            'This demonstration has no persistence.',
        code:
            'DTextRevisionPreview(current: current, saved: saved, '
            'active: preview, child: editor)',
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations:
                reduced || MediaQuery.disableAnimationsOf(context),
          ),
          child: const _RevisionExample(),
        ),
      ),
  ],
);

class _RevisionExample extends StatefulWidget {
  const _RevisionExample();
  @override
  State<_RevisionExample> createState() => _RevisionExampleState();
}

class _RevisionExampleState extends State<_RevisionExample>
    with SingleTickerProviderStateMixin {
  static const _saved = 'We can meet on Friday.\nBring the original notes.';
  final _text = TextEditingController(
    text: 'We can meet on Saturday.\nBring the revised notes.',
  );
  late final _animation = AnimationController(
    vsync: this,
    duration: DTextRevisionPreview.restorationDuration,
  );
  bool _preview = false;
  bool _restoring = false;
  String? _from;

  @override
  void dispose() {
    _animation.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    setState(() {
      _from = _text.text;
      _text.text = _saved;
      _restoring = true;
    });
    _animation.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : DTextRevisionPreview.restorationDuration;
    try {
      await _animation.forward(from: 0).orCancel;
      if (mounted) setState(() => _restoring = _preview = false);
    } on TickerCanceled {
      // The styleguide navigated away during the demonstration.
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: DSpacing.md,
    children: [
      SizedBox(
        height: 180,
        child: ValueListenableBuilder(
          valueListenable: _text,
          builder: (context, value, child) => DTextRevisionPreview(
            current: _restoring ? _from! : value.text,
            saved: _saved,
            active: _preview || _restoring,
            restoration: _restoring ? _animation : null,
            child: child!,
          ),
          child: DTextarea(controller: _text),
        ),
      ),
      DRevisionPreviewTarget(
        onChanged: (value) {
          if (!_restoring) setState(() => _preview = value);
        },
        child: DButton(
          onPressed: _restoring ? null : _restore,
          label: const Text('Discard changes'),
        ),
      ),
    ],
  );
}
