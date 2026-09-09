import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../styleguide_example.dart';

final sliderExamples = ComponentExamples(
  status: ComponentStatus.baseline,
  description: 'Choose one value, a range, or several ordered values.',
  notes:
      'Native visual inspection pending. DSlider is controlled scalar input; '
      'DMultiSlider accepts two values for a range or any positive thumb count. '
      'Values are ordered; pointer input pushes neighbours and keyboard input stops at them. Each thumb is a Tab stop '
      'with its own semantic label. Arrows step; Shift+arrows and Page keys step '
      'ten times; Home/End select bounds. Horizontal direction follows RTL, '
      'vertical increases upward. step:null enables continuous pointer input. '
      'A null callback disables input. DSliderField and DMultiSliderField support '
      'Form validation, save, reset and external updates. The base-nova 12px '
      'white thumb, 4px track and 3px ring retain 48px transparent interaction '
      'bounds. No value tooltip is invented. During a drag controlled values remain authoritative; '
      'parent acceptance, clamping and external updates render immediately. '
      'onChangeCancel does not undo changes already delivered to onChanged.',
  examples: [
    for (final example in [
      ('Default', <double>[75], Axis.horizontal, false, false),
      ('Range', <double>[25, 50], Axis.horizontal, false, false),
      ('Multiple Thumbs', <double>[10, 20, 70], Axis.horizontal, false, false),
      ('Vertical', <double>[25, 75], Axis.vertical, false, false),
      ('Controlled', <double>[0.3, 0.7], Axis.horizontal, false, false),
      ('Disabled', <double>[50], Axis.horizontal, true, false),
      ('RTL', <double>[75], Axis.horizontal, false, true),
      (
        'Overlapping thumbs',
        <double>[50, 50, 50],
        Axis.horizontal,
        false,
        false,
      ),
    ])
      StyleguideExample(
        title: example.$1,
        description: example.$1 == 'Controlled'
            ? 'Temperature, from 0 to 1 in steps of 0.1.'
            : 'Drag the track or thumbs; Tab to each thumb and try arrows, Page Up/Down and Home/End.',
        states: [example.$1, 'Keyboard', 'Live theme'],
        code: example.$1 == 'Vertical'
            ? _verticalCode
            : '''// List<double> values = ${example.$2}; // local State
DMultiSlider(
  values: values,
  ${example.$1 == 'Controlled' ? 'max: 1, step: 0.1,' : 'max: 100, step: ${example.$1 == 'Range'
                        ? 5
                        : example.$1 == 'Multiple Thumbs'
                        ? 10
                        : 1},'}
  orientation: Axis.${example.$3.name},
  semanticLabels: ${[for (var i = 0; i < example.$2.length; i++) "'Value ${i + 1}'"]},
  onChanged: ${example.$4 ? 'null' : '(next) => setState(() => values = next)'},
)''',
        builder: (_) => example.$1 == 'Vertical'
            ? const _VerticalReference()
            : _SliderDemo(
                initial: example.$2,
                step: example.$1 == 'Range'
                    ? 5
                    : example.$1 == 'Multiple Thumbs'
                    ? 10
                    : 1,
                axis: example.$3,
                disabled: example.$4,
                rtl: example.$5,
                temperature: example.$1 == 'Controlled',
              ),
      ),
    StyleguideExample(
      title: 'Form',
      description:
          'Validate a minimum of 20, save it, then reset to 10. Errors wrap at narrow widths.',
      code: '''DSliderField(initialValue: 10, semanticLabel: 'Budget',
  validator: (value) => value! < 20 ? 'Choose at least 20.' : null,
  onSaved: (value) => saved = value,
)''',
      states: const ['Invalid', 'Save', 'Reset'],
      builder: (_) => const _SliderForm(),
    ),
    StyleguideExample(
      title: 'Buffered playback and lifecycle',
      description:
          'A local playback value and buffered position; disable while loading or remove during use.',
      code: '''DSlider(value: position, max: 120, step: null,
  secondaryTrackValue: 90, semanticLabel: 'Playback position',
  onChanged: loading ? null : (next) => setState(() => position = next),
)''',
      states: const ['Continuous', 'Buffered', 'Disabled', 'Removal'],
      builder: (_) => const _PlaybackDemo(),
    ),
  ],
);

class _SliderDemo extends StatefulWidget {
  const _SliderDemo({
    required this.initial,
    required this.step,
    required this.axis,
    required this.disabled,
    required this.rtl,
    required this.temperature,
  });
  final List<double> initial;
  final double step;
  final Axis axis;
  final bool disabled, rtl, temperature;
  @override
  State<_SliderDemo> createState() => _SliderDemoState();
}

class _SliderDemoState extends State<_SliderDemo> {
  late List<double> _values = widget.initial;
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: widget.rtl ? TextDirection.rtl : Directionality.of(context),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.temperature) ...[
            Row(
              children: [
                const Expanded(child: DLabel(child: Text('Temperature'))),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _values.map((v) => v.toStringAsFixed(1)).join(', '),
                    style: TextStyle(
                      fontSize: 14,
                      color: DTokens.of(context).mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(
            height: widget.axis == Axis.vertical ? 160 : 48,
            child: DMultiSlider(
              values: _values,
              orientation: widget.axis,
              max: widget.temperature ? 1 : 100,
              step: widget.temperature ? 0.1 : widget.step,
              semanticLabels: [
                for (var i = 0; i < _values.length; i++)
                  widget.temperature
                      ? 'Temperature ${i + 1}'
                      : 'Value ${i + 1}',
              ],
              onChanged: widget.disabled
                  ? null
                  : (values) => setState(() => _values = values),
            ),
          ),
        ],
      ),
    ),
  );
}

class _VerticalReference extends StatefulWidget {
  const _VerticalReference();
  @override
  State<_VerticalReference> createState() => _VerticalReferenceState();
}

class _VerticalReferenceState extends State<_VerticalReference> {
  double _first = 50, _second = 25;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 84,
    height: 160,
    child: Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 48,
          child: DSlider(
            value: _first,
            orientation: Axis.vertical,
            semanticLabel: 'First vertical value',
            onChanged: (v) => setState(() => _first = v),
          ),
        ),
        Positioned(
          left: 36,
          top: 0,
          bottom: 0,
          width: 48,
          child: DSlider(
            value: _second,
            orientation: Axis.vertical,
            semanticLabel: 'Second vertical value',
            onChanged: (v) => setState(() => _second = v),
          ),
        ),
      ],
    ),
  );
}

class _SliderForm extends StatefulWidget {
  const _SliderForm();
  @override
  State<_SliderForm> createState() => _SliderFormState();
}

class _SliderFormState extends State<_SliderForm> {
  final _key = GlobalKey<FormState>();
  double? _saved;
  @override
  Widget build(BuildContext context) => Form(
    key: _key,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DSliderField(
          initialValue: 10,
          semanticLabel: 'Budget',
          validator: (value) => value! < 20 ? 'Choose at least 20.' : null,
          onSaved: (value) => setState(() => _saved = value),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DButton(
              label: const Text('Save'),
              onPressed: () {
                if (_key.currentState!.validate()) _key.currentState!.save();
              },
            ),
            DButton(
              label: const Text('Reset'),
              onPressed: () => _key.currentState!.reset(),
            ),
          ],
        ),
        Text('Saved: ${_saved ?? 'none'}'),
      ],
    ),
  );
}

class _PlaybackDemo extends StatefulWidget {
  const _PlaybackDemo();
  @override
  State<_PlaybackDemo> createState() => _PlaybackDemoState();
}

class _PlaybackDemoState extends State<_PlaybackDemo> {
  double _position = 30;
  bool _loading = false, _visible = true;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('${_position.round()} / 120 seconds'),
      if (_visible)
        DSlider(
          value: _position,
          max: 120,
          step: null,
          secondaryTrackValue: 90,
          semanticLabel: 'Playback position',
          semanticFormatterCallback: (value) => '${value.round()} seconds',
          onChanged: _loading
              ? null
              : (value) => setState(() => _position = value),
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          DButton(
            label: Text(_loading ? 'Ready' : 'Loading'),
            onPressed: () => setState(() => _loading = !_loading),
          ),
          DButton(
            label: Text(_visible ? 'Remove' : 'Restore'),
            onPressed: () => setState(() => _visible = !_visible),
          ),
        ],
      ),
    ],
  );
}

const _verticalCode =
    '''// Two independent vertical sliders, 160px high; 36px between thumb centers.
SizedBox(width: 84, height: 160, child: Stack(children: [
  Positioned(left: 0, top: 0, bottom: 0, width: 48,
    child: DSlider(value: first, orientation: Axis.vertical,
      semanticLabel: 'First value', onChanged: (v) => setState(() => first = v))),
  Positioned(left: 36, top: 0, bottom: 0, width: 48,
    child: DSlider(value: second, orientation: Axis.vertical,
      semanticLabel: 'Second value', onChanged: (v) => setState(() => second = v))),
]))''';
