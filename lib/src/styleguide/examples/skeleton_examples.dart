import 'package:flutter/material.dart';

import '../../../discourse_ui.dart';
import '../styleguide_example.dart';

final skeletonExamples = ComponentExamples(
  topLevelExampleIndex: 7,
  description: 'Show a placeholder while content is loading.',
  status: ComponentStatus.implemented,
  notes:
      'Import discourse_ui.dart. Geometry uses logical pixels and live site '
      'muted color and medium radius; native layout widgets provide fractions '
      'and aspect ratios. '
      'Omitted dimensions fill bounded axes and collapse on unbounded axes. '
      'DSkeletonRegion shares a two-second opacity pulse and announces one '
      'localized label. Its children are decorative; keep controls and scroll '
      'views outside it. Reduced motion pauses at full opacity. Callers own '
      'loading/error/ready state. Frozen reference dimensions, spacing and '
      'compositions are preserved; sample state controls sit outside them.',
  examples: [
    StyleguideExample(
      title: 'Geometry and motion',
      description:
          'The reference demo and 100×20 pill precede the interactive controls. '
          'Change the standalone shape, dimensions, corner radius and pulse. '
          'Tab to a slider and use arrow keys. Reduce motion overrides Pulse; '
          'changing theme or direction preserves all controls. The second '
          'shape explicitly opts out of a region’s pulse.',
      states: const [
        'Standalone',
        'Circle',
        'Pill',
        'Radius',
        'Static',
        'Pulse',
      ],
      code: '''DSkeletonRegion(
  semanticsLabel: 'Loading profile',
  child: SizedBox(width: 314, child: Row(children: [
    const DSkeleton.circle(diameter: 48),
    const SizedBox(width: 16),
    Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
      const DSkeleton(width: 250, height: 16),
      const SizedBox(height: 8),
      const DSkeleton(width: 200, height: 16),
    ])),
  ])),
)
DSkeleton(width: 100, height: 20,
  borderRadius: BorderRadius.circular(999))
DSkeleton(width: 160, height: 32) // Medium radius: site base × 0.8.
DSkeleton.circle(diameter: 48)
DSkeleton(
  width: 160,
  height: 32,
  borderRadius: BorderRadius.circular(999),
  animate: false,
)
DSkeletonRegion(
  semanticsLabel: 'Loading preview',
  child: Row(children: [
    const Expanded(child: DSkeleton(height: 16)),
    const SizedBox(width: DSpacing.sm),
    const DSkeleton(width: 48, height: 16, animate: false),
  ]),
)''',
      builder: (_) => const _GeometryPreview(),
    ),
    StyleguideExample(
      title: 'Avatar',
      description:
          'A circular avatar and two lines share one loading label and pulse. '
          'Choose Ready, Loading or Error to exercise the content transition; '
          'Retry returns to loading. No request is made.',
      states: const ['Loading', 'Ready', 'Error', 'Retry', 'Narrow'],
      code: '''DSkeletonRegion(
  semanticsLabel: 'Loading profile',
  child: SizedBox(width: 206, child: Row(children: [
    const DSkeleton.circle(diameter: 40),
    const SizedBox(width: DSpacing.lg),
    Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DSkeleton(width: 150, height: 16),
        const SizedBox(height: DSpacing.sm),
        const DSkeleton(width: 100, height: 16),
      ],
    )),
  ])),
)''',
      builder: (_) => const _LoadingPreview(
        semanticsLabel: 'Loading profile',
        maxWidth: 206,
        placeholder: _AvatarPlaceholder(),
        content: _ProfileContent(),
      ),
    ),
    StyleguideExample(
      title: 'Card',
      description:
          'A 320px card has 16px padding, a 4px title gap, a 16px section gap '
          'and a 16:9 cover, matching the frozen reference. '
          'Switch to Ready and activate Follow to verify the real content.',
      states: const ['Aspect ratio', 'Fractional width', 'Ready action'],
      code: """DSkeletonRegion(
  semanticsLabel: 'Loading card',
  child: SizedBox(width: 320, child: DCard(children: [
    DCardHeader(
      title: FractionallySizedBox(widthFactor: 2 / 3, child: DSkeleton(height: 16)),
      description: FractionallySizedBox(widthFactor: 0.5, child: DSkeleton(height: 16)),
    ),
    DCardContent(child: DAspectRatio(ratio: 16 / 9, child: DSkeleton())),
  ])),
)""",
      builder: (_) => const _LoadingPreview(
        semanticsLabel: 'Loading card',
        placeholder: _CardPlaceholder(),
        content: _CardContent(),
      ),
    ),
    StyleguideExample(
      title: 'Text',
      description:
          'Two full-width lines and a shorter trailing line follow the preview '
          'direction. Ready text reflows naturally at 200% text scale.',
      states: const ['Text lines', 'RTL', 'Text scaling'],
      code: '''DSkeletonRegion(
  semanticsLabel: 'Loading article',
  child: SizedBox(width: 320, child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const DSkeleton(height: 16),
      const SizedBox(height: DSpacing.sm),
      const DSkeleton(height: 16),
      const SizedBox(height: DSpacing.sm),
      const FractionallySizedBox(
        widthFactor: 0.75, child: DSkeleton(height: 16)),
    ],
  )),
)''',
      builder: (_) => const _LoadingPreview(
        semanticsLabel: 'Loading article',
        placeholder: _TextPlaceholder(),
        content: Text(
          'A thoughtful community starts with a conversation. Share a question, '
          'offer your experience, and make room for someone new.',
        ),
      ),
    ),
    StyleguideExample(
      title: 'Form',
      description:
          'Label, input and button placeholders become an editable local form. '
          'Choose Ready, edit a name, then Save. An empty name shows validation. '
          'Theme and direction changes retain edits; reloading replaces the form.',
      states: const [
        'Label/input geometry',
        'Editing',
        'Validation',
        'Keyboard',
      ],
      code: '''DSkeletonRegion(
  semanticsLabel: 'Loading profile form',
  child: SizedBox(width: 320, child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final labelWidth in [80.0, 96.0]) ...[
        DSkeleton(width: labelWidth, height: 16),
        const SizedBox(height: DSpacing.md),
        const DSkeleton(height: 32),
        const SizedBox(height: 28),
      ],
      const DSkeleton(width: 96, height: 32),
    ],
  )),
)''',
      builder: (_) => const _LoadingPreview(
        semanticsLabel: 'Loading profile form',
        placeholder: _FormPlaceholder(),
        content: _FormContent(),
      ),
    ),
    StyleguideExample(
      title: 'Table',
      description:
          'Five rows with 8px row gaps fill up to 384px. Columns have 16px '
          'gaps and fixed 96px/80px trailing widths. Extremely narrow previews '
          'scroll horizontally with a trackpad, touch drag or scrollbar. '
          'The scroll view stays outside the noninteractive loading region.',
      states: const ['Five rows', 'Three columns', 'Horizontal scrolling'],
      code: '''SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: SizedBox(
    width: 384, // Shrinks with available space; scroll only below 256px.
    child: DSkeletonRegion(
      semanticsLabel: 'Loading five members',
      child: Column(children: [
        for (var row = 0; row < 5; row++) ...[
          if (row > 0) const SizedBox(height: DSpacing.sm),
          Row(children: [
              const Expanded(child: DSkeleton(height: 16)),
              const SizedBox(width: DSpacing.lg),
              const DSkeleton(width: 96, height: 16),
              const SizedBox(width: DSpacing.lg),
              const DSkeleton(width: 80, height: 16),
          ]),
        ],
      ]),
    ),
  ),
)''',
      builder: (_) => const _LoadingPreview(
        semanticsLabel: 'Loading five members',
        maxWidth: 384,
        minWidth: 256,
        placeholder: _TablePlaceholder(),
        content: _TableContent(),
      ),
    ),
    StyleguideExample(
      title: 'RTL',
      description:
          'An explicit RTL scope mirrors the reference 48px avatar and '
          '250px/200px lines with 16px/8px gaps. The Arabic '
          'loading label belongs to this composition, not a translation service.',
      states: const ['RTL', 'Localized label'],
      code: '''DDirection(
  textDirection: TextDirection.rtl,
  child: DSkeletonRegion(
    semanticsLabel: 'جارٍ تحميل الملف الشخصي',
    child: SizedBox(width: 314, child: Row(children: [
      const DSkeleton.circle(diameter: 48),
      const SizedBox(width: DSpacing.lg),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DSkeleton(width: 250, height: 16),
          const SizedBox(height: 8),
          const DSkeleton(width: 200, height: 16),
        ],
      )),
    ])),
  ),
)''',
      builder: (_) => const DDirection(
        textDirection: TextDirection.rtl,
        child: _LoadingPreview(
          semanticsLabel: 'جارٍ تحميل الملف الشخصي',
          maxWidth: 314,
          placeholder: _AvatarPlaceholder(
            diameter: 48,
            titleWidth: 250,
            subtitleWidth: 200,
          ),
          content: _ProfileContent(arabic: true),
        ),
      ),
    ),
    StyleguideExample(
      title: 'Reference demo',
      description:
          'The canonical 48px avatar placeholder and two text lines share one loading region.',
      states: const ['Avatar', 'Text lines', 'Loading', 'Reduced motion'],
      code: '''DSkeletonRegion(
  semanticsLabel: 'Loading profile',
  child: SizedBox(
    width: 314,
    child: Row(children: [
      DSkeleton.circle(diameter: 48),
      SizedBox(width: 16),
      Column(children: [
        DSkeleton(width: 250, height: 16),
        SizedBox(height: 8),
        DSkeleton(width: 200, height: 16),
      ]),
    ]),
  ),
)''',
      builder: (_) => const SizedBox(
        width: 314,
        child: DSkeletonRegion(
          semanticsLabel: 'Loading profile',
          child: _AvatarPlaceholder(
            diameter: 48,
            titleWidth: 250,
            subtitleWidth: 200,
          ),
        ),
      ),
    ),
  ],
);

class _GeometryPreview extends StatefulWidget {
  const _GeometryPreview();

  @override
  State<_GeometryPreview> createState() => _GeometryPreviewState();
}

class _GeometryPreviewState extends State<_GeometryPreview> {
  String _shape = 'Rectangle';
  double _width = 160;
  double _height = 32;
  double? _radius;
  bool _animate = true;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Reference demo'),
      const SizedBox(height: DSpacing.sm),
      const SizedBox(
        width: 314,
        child: DSkeletonRegion(
          key: ValueKey('skeleton-reference-demo'),
          semanticsLabel: 'Loading profile',
          child: _AvatarPlaceholder(
            diameter: 48,
            titleWidth: 250,
            subtitleWidth: 200,
          ),
        ),
      ),
      const SizedBox(height: DSpacing.lg),
      const Text('Usage'),
      const SizedBox(height: DSpacing.sm),
      const DSkeleton(
        key: ValueKey('skeleton-reference-usage'),
        width: 100,
        height: 20,
        borderRadius: BorderRadius.all(Radius.circular(999)),
      ),
      const SizedBox(height: DSpacing.xl),
      const Text('Geometry controls'),
      Wrap(
        spacing: DSpacing.sm,
        runSpacing: DSpacing.sm,
        children: [
          for (final shape in ['Rectangle', 'Pill', 'Circle'])
            ChoiceChip(
              label: Text(shape),
              selected: _shape == shape,
              onSelected: (_) => setState(() => _shape = shape),
            ),
          FilterChip(
            label: const Text('Pulse'),
            selected: _animate,
            onSelected: (value) => setState(() => _animate = value),
          ),
        ],
      ),
      if (_shape != 'Circle') ...[
        Text('Width: ${_width.round()}'),
        DSlider(
          semanticFormatterCallback: (value) => 'Width: ${value.round()}',
          value: _width,
          min: 40,
          max: 240,
          step: 10,
          onChanged: (value) => setState(() => _width = value),
        ),
      ],
      Text('${_shape == 'Circle' ? 'Diameter' : 'Height'}: ${_height.round()}'),
      DSlider(
        semanticFormatterCallback: (value) =>
            '${_shape == 'Circle' ? 'Diameter' : 'Height'}: ${value.round()}',
        value: _height,
        min: 8,
        max: 96,
        step: 4,
        onChanged: (value) => setState(() => _height = value),
      ),
      if (_shape == 'Rectangle') ...[
        Text(
          _radius == null
              ? 'Radius: site default'
              : 'Radius: ${_radius!.round()}',
        ),
        DSlider(
          semanticFormatterCallback: (value) =>
              'Corner radius: ${value.round()}',
          value: _radius ?? (DTokens.of(context).radius * 0.8).clamp(0, 32),
          min: 0,
          max: 32,
          step: 2,
          onChanged: (value) => setState(() => _radius = value),
        ),
        DButton(
          variant: DButtonVariant.ghost,
          onPressed: () => setState(() => _radius = null),
          label: const Text('Use site radius'),
        ),
      ],
      Text(
        MediaQuery.disableAnimationsOf(context)
            ? 'Reduced motion: static at full opacity'
            : (_animate ? 'Pulse enabled' : 'Pulse paused at full opacity'),
      ),
      const SizedBox(height: DSpacing.md),
      Semantics(
        label: 'Loading shape preview',
        child: _shape == 'Circle'
            ? DSkeleton.circle(
                key: const ValueKey('skeleton-geometry-shape'),
                diameter: _height,
                animate: _animate,
              )
            : DSkeleton(
                key: const ValueKey('skeleton-geometry-shape'),
                width: _width,
                height: _height,
                animate: _animate,
                borderRadius: _shape == 'Pill'
                    ? BorderRadius.circular(999)
                    : (_radius == null
                          ? null
                          : BorderRadius.circular(_radius!)),
              ),
      ),
      const SizedBox(height: DSpacing.xl),
      const Text('Shared pulse with a static companion'),
      const SizedBox(height: DSpacing.sm),
      DSkeletonRegion(
        semanticsLabel: 'Loading preview',
        animate: _animate,
        child: const Row(
          children: [
            Expanded(child: DSkeleton(height: 16)),
            SizedBox(width: DSpacing.sm),
            DSkeleton(width: 48, height: 16, animate: false),
          ],
        ),
      ),
      const SizedBox(height: DSpacing.lg),
      const Text('Directional corner override'),
      const SizedBox(height: DSpacing.sm),
      DSkeleton(
        width: 160,
        height: 32,
        animate: _animate,
        borderRadius: const BorderRadiusDirectional.only(
          topStart: Radius.circular(20),
          bottomEnd: Radius.circular(20),
        ),
      ),
    ],
  );
}

class _LoadingPreview extends StatefulWidget {
  const _LoadingPreview({
    required this.semanticsLabel,
    required this.placeholder,
    required this.content,
    this.maxWidth = 320,
    this.minWidth,
  });

  final String semanticsLabel;
  final Widget placeholder;
  final Widget content;
  final double maxWidth;
  final double? minWidth;

  @override
  State<_LoadingPreview> createState() => _LoadingPreviewState();
}

class _LoadingPreviewState extends State<_LoadingPreview> {
  final _scroll = ScrollController();
  String _status = 'Loading';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (_status) {
      'Loading' => DSkeletonRegion(
        semanticsLabel: widget.semanticsLabel,
        child: widget.placeholder,
      ),
      'Ready' => widget.content,
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: const Text('Could not load this sample.'),
          ),
          DButton(
            variant: DButtonVariant.ghost,
            onPressed: () => setState(() => _status = 'Loading'),
            label: const Text('Retry'),
          ),
        ],
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: DSpacing.sm,
          runSpacing: DSpacing.sm,
          children: [
            for (final status in ['Loading', 'Ready', 'Error'])
              ChoiceChip(
                label: Text(status),
                selected: _status == status,
                onSelected: (_) => setState(() => _status = status),
              ),
          ],
        ),
        const SizedBox(height: DSpacing.lg),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: SizedBox(
            width: double.infinity,
            child: widget.minWidth == null
                ? content
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final overflow = constraints.maxWidth < widget.minWidth!;
                      return Scrollbar(
                        controller: _scroll,
                        thickness: DScrollThumb.defaultThickness,
                        thumbVisibility: overflow,
                        child: SingleChildScrollView(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.only(
                            bottom: overflow ? DSpacing.lg : 0,
                          ),
                          child: SizedBox(
                            width: overflow
                                ? widget.minWidth
                                : constraints.maxWidth,
                            child: content,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({
    this.diameter = 40,
    this.titleWidth = 150,
    this.subtitleWidth = 100,
  });

  final double diameter;
  final double titleWidth;
  final double subtitleWidth;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      DSkeleton.circle(diameter: diameter),
      const SizedBox(width: DSpacing.lg),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DSkeleton(width: titleWidth, height: 16),
            const SizedBox(height: DSpacing.sm),
            DSkeleton(width: subtitleWidth, height: 16),
          ],
        ),
      ),
    ],
  );
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({this.arabic = false});

  final bool arabic;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: DTokens.of(context).muted,
          ),
          child: const SizedBox.square(
            dimension: 40,
            child: Icon(Icons.person, size: 20),
          ),
        ),
      ),
      const SizedBox(width: DSpacing.lg),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              arabic ? 'ليلى' : 'Ada',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(arabic ? 'عضو في المجتمع' : 'Community member'),
          ],
        ),
      ),
    ],
  );
}

class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      DCard(children: [DCardContent(child: child)]);
}

class _CardPlaceholder extends StatelessWidget {
  const _CardPlaceholder();

  @override
  Widget build(BuildContext context) => const _CardFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FractionallySizedBox(widthFactor: 2 / 3, child: DSkeleton(height: 16)),
        SizedBox(height: DSpacing.xs),
        FractionallySizedBox(widthFactor: 0.5, child: DSkeleton(height: 16)),
        SizedBox(height: DSpacing.lg),
        DAspectRatio(ratio: 16 / 9, child: DSkeleton()),
      ],
    ),
  );
}

class _CardContent extends StatefulWidget {
  const _CardContent();

  @override
  State<_CardContent> createState() => _CardContentState();
}

class _CardContentState extends State<_CardContent> {
  bool _following = false;

  @override
  Widget build(BuildContext context) => _CardFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Community garden',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text('A place to share what you grow.'),
        const SizedBox(height: DSpacing.lg),
        DAspectRatio(
          ratio: 16 / 9,
          child: ColoredBox(
            color: DTokens.of(context).muted,
            child: const Icon(
              Icons.park,
              size: 64,
              semanticLabel: 'Garden cover',
            ),
          ),
        ),
        DButton(
          variant: DButtonVariant.ghost,
          onPressed: () => setState(() => _following = !_following),
          label: Text(_following ? 'Following' : 'Follow'),
        ),
      ],
    ),
  );
}

class _TextPlaceholder extends StatelessWidget {
  const _TextPlaceholder();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DSkeleton(height: 16),
      SizedBox(height: DSpacing.sm),
      DSkeleton(height: 16),
      SizedBox(height: DSpacing.sm),
      FractionallySizedBox(widthFactor: 0.75, child: DSkeleton(height: 16)),
    ],
  );
}

class _FormPlaceholder extends StatelessWidget {
  const _FormPlaceholder();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final labelWidth in [80.0, 96.0]) ...[
        DSkeleton(width: labelWidth, height: 16),
        const SizedBox(height: DSpacing.md),
        const DSkeleton(height: 32),
        const SizedBox(height: 28),
      ],
      const DSkeleton(width: 96, height: 32),
    ],
  );
}

class _FormContent extends StatefulWidget {
  const _FormContent();

  @override
  State<_FormContent> createState() => _FormContentState();
}

class _FormContentState extends State<_FormContent> {
  final _form = GlobalKey<FormState>();
  String _name = 'Ada';
  String? _saved;

  Widget _field(
    BuildContext context, {
    required String label,
    required String initialValue,
    String? Function(String?)? validator,
    void Function(String?)? onSaved,
  }) {
    final tokens = DTokens.of(context);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.radius * 0.8),
      borderSide: BorderSide(color: color),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          label: label,
          child: TextFormField(
            initialValue: initialValue,
            validator: validator,
            onSaved: onSaved,
            style: const TextStyle(fontSize: 14, height: 20 / 14),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 5,
              ),
              enabledBorder: border(tokens.border),
              focusedBorder: border(tokens.focusRing),
              errorBorder: border(tokens.destructive),
              focusedErrorBorder: border(tokens.destructive),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(
          context,
          label: 'Name',
          initialValue: _name,
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'Enter a name' : null,
          onSaved: (value) => _name = value!.trim(),
        ),
        const SizedBox(height: 28),
        _field(context, label: 'Bio', initialValue: 'Community member'),
        const SizedBox(height: 28),
        DButton(
          variant: DButtonVariant.ghost,
          onPressed: () {
            if (_form.currentState!.validate()) {
              _form.currentState!.save();
              setState(() => _saved = _name);
            }
          },
          label: const Text('Save'),
        ),
        if (_saved != null)
          Semantics(liveRegion: true, child: Text('Saved: $_saved')),
      ],
    ),
  );
}

class _TablePlaceholder extends StatelessWidget {
  const _TablePlaceholder();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var row = 0; row < 5; row++) ...[
        if (row > 0) const SizedBox(height: DSpacing.sm),
        const Row(
          children: [
            Expanded(child: DSkeleton(height: 16)),
            SizedBox(width: DSpacing.lg),
            DSkeleton(width: 96, height: 16),
            SizedBox(width: DSpacing.lg),
            DSkeleton(width: 80, height: 16),
          ],
        ),
      ],
    ],
  );
}

class _TableContent extends StatelessWidget {
  const _TableContent();

  @override
  Widget build(BuildContext context) => DTable(
    columnWidths: const {1: FixedColumnWidth(112), 2: FixedColumnWidth(96)},
    body: DTableBody(
      rows: [
        for (final (index, name) in [
          'Ada',
          'Grace',
          'Linus',
          'Margaret',
          'Ken',
        ].indexed)
          DTableRow(
            cells: [
              for (final value in [name, '${index + 2} posts', 'Member'])
                DTableCell(
                  padding: const EdgeInsetsDirectional.only(
                    end: DSpacing.lg,
                    top: DSpacing.sm,
                    bottom: DSpacing.sm,
                  ),
                  child: Text(value),
                ),
            ],
          ),
      ],
    ),
  );
}
