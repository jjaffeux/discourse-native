import 'package:flutter/material.dart';

import '../../../discourse_ui.dart';
import '../styleguide_example.dart';

final skeletonExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  notes:
      'Import discourse_ui.dart. Geometry uses logical pixels and live site '
      'colors/radius; native layout widgets provide fractions and aspect ratios. '
      'Omitted dimensions fill bounded axes and collapse on unbounded axes. '
      'DSkeletonRegion shares the existing 675 ms pulse leg and announces one '
      'localized label. Its children are decorative; keep controls and scroll '
      'views outside it. Reduced motion pauses at full opacity. Callers own '
      'loading/error/ready state. These examples use Flutter primitives for '
      'cards, forms and tables.',
  examples: [
    StyleguideExample(
      title: 'Geometry and motion',
      description:
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
      code: '''DSkeleton(width: 160, height: 32) // Live site radius.
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
  child: Row(children: [
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
  ]),
)''',
      builder: (_) => const _LoadingPreview(
        semanticsLabel: 'Loading profile',
        placeholder: _AvatarPlaceholder(),
        content: _ProfileContent(),
      ),
    ),
    StyleguideExample(
      title: 'Card',
      description:
          'Fractional title lines and a 16:9 cover reserve a card’s geometry. '
          'Switch to Ready and activate Follow to verify the real content.',
      states: const ['Aspect ratio', 'Fractional width', 'Ready action'],
      code: '''DSkeletonRegion(
  semanticsLabel: 'Loading card',
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const FractionallySizedBox(
        widthFactor: 2 / 3, child: DSkeleton(height: 16)),
      const SizedBox(height: DSpacing.sm),
      const FractionallySizedBox(
        widthFactor: 0.5, child: DSkeleton(height: 16)),
      const SizedBox(height: DSpacing.lg),
      const AspectRatio(aspectRatio: 16 / 9, child: DSkeleton()),
    ],
  ),
)''',
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
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const DSkeleton(height: 16),
      const SizedBox(height: DSpacing.sm),
      const DSkeleton(height: 16),
      const SizedBox(height: DSpacing.sm),
      const FractionallySizedBox(
        widthFactor: 0.75, child: DSkeleton(height: 16)),
    ],
  ),
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
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final labelWidth in [80.0, 96.0]) ...[
        DSkeleton(width: labelWidth, height: 16),
        const SizedBox(height: DSpacing.md),
        const DSkeleton(height: 32),
        const SizedBox(height: DSpacing.xl),
      ],
      const DSkeleton(width: 96, height: 32),
    ],
  ),
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
          'Five rows with three columns reserve tabular content. At narrow '
          'widths, scroll horizontally with a trackpad, touch drag or scrollbar. '
          'The scroll view stays outside the noninteractive loading region.',
      states: const ['Five rows', 'Three columns', 'Horizontal scrolling'],
      code: '''SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: SizedBox(
    width: 520,
    child: DSkeletonRegion(
      semanticsLabel: 'Loading five members',
      child: Column(children: [
        for (var row = 0; row < 5; row++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DSpacing.sm),
            child: Row(children: [
              const Expanded(child: DSkeleton(height: 16)),
              const SizedBox(width: DSpacing.lg),
              const DSkeleton(width: 96, height: 16),
              const SizedBox(width: DSpacing.lg),
              const DSkeleton(width: 80, height: 16),
            ]),
          ),
      ]),
    ),
  ),
)''',
      builder: (_) => const _LoadingPreview(
        semanticsLabel: 'Loading five members',
        scrollWidth: 520,
        placeholder: _TablePlaceholder(),
        content: _TableContent(),
      ),
    ),
    StyleguideExample(
      title: 'RTL and directional corners',
      description:
          'An explicit RTL scope positions the avatar at the reading start. '
          'The asymmetric corner radius mirrors with direction. The Arabic '
          'loading label belongs to this composition, not a translation service.',
      states: const ['RTL', 'Directional radius', 'Localized label'],
      code: '''DDirection(
  textDirection: TextDirection.rtl,
  child: DSkeletonRegion(
    semanticsLabel: 'جارٍ تحميل الملف الشخصي',
    child: Row(children: [
      const DSkeleton.circle(diameter: 48),
      const SizedBox(width: DSpacing.lg),
      const Expanded(child: DSkeleton(
        height: 32,
        borderRadius: BorderRadiusDirectional.only(
          topStart: Radius.circular(20),
          bottomEnd: Radius.circular(20),
        ),
      )),
    ]),
  ),
)''',
      builder: (_) => const DDirection(
        textDirection: TextDirection.rtl,
        child: _LoadingPreview(
          semanticsLabel: 'جارٍ تحميل الملف الشخصي',
          placeholder: _AvatarPlaceholder(directional: true),
          content: _ProfileContent(arabic: true),
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
        Slider(
          semanticFormatterCallback: (value) => 'Width: ${value.round()}',
          value: _width,
          min: 40,
          max: 240,
          divisions: 20,
          onChanged: (value) => setState(() => _width = value),
        ),
      ],
      Text('${_shape == 'Circle' ? 'Diameter' : 'Height'}: ${_height.round()}'),
      Slider(
        semanticFormatterCallback: (value) =>
            '${_shape == 'Circle' ? 'Diameter' : 'Height'}: ${value.round()}',
        value: _height,
        min: 8,
        max: 96,
        divisions: 22,
        onChanged: (value) => setState(() => _height = value),
      ),
      if (_shape == 'Rectangle') ...[
        Text(
          _radius == null
              ? 'Radius: site default'
              : 'Radius: ${_radius!.round()}',
        ),
        Slider(
          semanticFormatterCallback: (value) =>
              'Corner radius: ${value.round()}',
          value: _radius ?? DTokens.of(context).radius.clamp(0, 32),
          min: 0,
          max: 32,
          divisions: 16,
          onChanged: (value) => setState(() => _radius = value),
        ),
        DButton(
          variant: DButtonVariant.flat,
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
            ? DSkeleton.circle(diameter: _height, animate: _animate)
            : DSkeleton(
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
    ],
  );
}

class _LoadingPreview extends StatefulWidget {
  const _LoadingPreview({
    required this.semanticsLabel,
    required this.placeholder,
    required this.content,
    this.scrollWidth,
  });

  final String semanticsLabel;
  final Widget placeholder;
  final Widget content;
  final double? scrollWidth;

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
    final tokens = DTokens.of(context);
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
            variant: DButtonVariant.flat,
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
        Container(
          constraints: const BoxConstraints(maxWidth: 400),
          width: double.infinity,
          padding: const EdgeInsetsDirectional.all(DSpacing.lg),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: tokens.borderRadius,
            border: Border.all(color: tokens.border),
          ),
          child: widget.scrollWidth == null
              ? content
              : Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: DSpacing.lg),
                    child: SizedBox(width: widget.scrollWidth, child: content),
                  ),
                ),
        ),
      ],
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({this.directional = false});

  final bool directional;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      DSkeleton.circle(diameter: directional ? 48 : 40),
      const SizedBox(width: DSpacing.lg),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DSkeleton(
              width: directional ? null : 150,
              height: directional ? 32 : 16,
              borderRadius: directional
                  ? const BorderRadiusDirectional.only(
                      topStart: Radius.circular(20),
                      bottomEnd: Radius.circular(20),
                    )
                  : null,
            ),
            const SizedBox(height: DSpacing.sm),
            const DSkeleton(width: 100, height: 16),
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
      const ExcludeSemantics(child: CircleAvatar(child: Icon(Icons.person))),
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

class _CardPlaceholder extends StatelessWidget {
  const _CardPlaceholder();

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FractionallySizedBox(widthFactor: 2 / 3, child: DSkeleton(height: 16)),
      SizedBox(height: DSpacing.sm),
      FractionallySizedBox(widthFactor: 0.5, child: DSkeleton(height: 16)),
      SizedBox(height: DSpacing.lg),
      AspectRatio(aspectRatio: 16 / 9, child: DSkeleton()),
    ],
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Community garden', style: Theme.of(context).textTheme.titleMedium),
      const Text('A place to share what you grow.'),
      const SizedBox(height: DSpacing.lg),
      AspectRatio(
        aspectRatio: 16 / 9,
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
        variant: DButtonVariant.flat,
        onPressed: () => setState(() => _following = !_following),
        label: Text(_following ? 'Following' : 'Follow'),
      ),
    ],
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
        const SizedBox(height: DSpacing.xl),
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

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          initialValue: _name,
          decoration: const InputDecoration(labelText: 'Name'),
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'Enter a name' : null,
          onSaved: (value) => _name = value!.trim(),
        ),
        const SizedBox(height: DSpacing.md),
        TextFormField(
          initialValue: 'Community member',
          decoration: const InputDecoration(labelText: 'Bio'),
          maxLines: null,
        ),
        const SizedBox(height: DSpacing.md),
        DButton(
          variant: DButtonVariant.flat,
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
      for (var row = 0; row < 5; row++)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: DSpacing.sm),
          child: Row(
            children: [
              Expanded(child: DSkeleton(height: 16)),
              SizedBox(width: DSpacing.lg),
              DSkeleton(width: 96, height: 16),
              SizedBox(width: DSpacing.lg),
              DSkeleton(width: 80, height: 16),
            ],
          ),
        ),
    ],
  );
}

class _TableContent extends StatelessWidget {
  const _TableContent();

  @override
  Widget build(BuildContext context) => Table(
    columnWidths: const {1: FixedColumnWidth(112), 2: FixedColumnWidth(96)},
    children: [
      for (final (index, name) in [
        'Ada',
        'Grace',
        'Linus',
        'Margaret',
        'Ken',
      ].indexed)
        TableRow(
          children: [
            for (final value in [name, '${index + 2} posts', 'Member'])
              Padding(
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
  );
}
