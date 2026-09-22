import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/widgets.dart';

import '../styleguide_example.dart';
import 'onebox_samples.dart';

final oneboxExamples = ComponentExamples(
  status: ComponentStatus.implemented,
  description: 'Explore the link previews supported by the native app.',
  notes:
      'Search by provider or preview type, then choose a state. These examples '
      'use the production cooked-content renderers and local sample markup. '
      'Event previews use the same EventCard as hydrated event oneboxes, with '
      'local attendance state. Generic cards cover other providers through '
      'their shared onebox markup. Images and activated video require a network '
      'connection; links open their sample destinations. Theme, width, text '
      'scale and direction can be changed with the styleguide preview settings.',
  examples: [
    StyleguideExample(
      title: 'Browse oneboxes',
      description:
          'Find a onebox, then use the buttons to compare its states and content variations.',
      code: '''CookedHtml(
  html: cookedOneboxMarkup,
  siteUrl: 'https://meta.discourse.org',
  registry: PluginRegistry([
    DiscourseGithubPlugin(cookedTimeParser: cookedTimeParser),
    DiscourseLazyVideosPlugin(),
  ]),
)''',
      builder: (_) => const _OneboxGallery(),
    ),
  ],
);

class _OneboxGallery extends StatefulWidget {
  const _OneboxGallery();

  @override
  State<_OneboxGallery> createState() => _OneboxGalleryState();
}

class _OneboxGalleryState extends State<_OneboxGallery> {
  OneboxSample _sample = oneboxSamples.first;
  int _state = 0;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DField(
          children: [
            const DFieldLabel(child: Text('Onebox')),
            DCombobox<OneboxSample>.controlled(
              key: const ValueKey('onebox-picker'),
              value: _sample,
              autoHighlight: true,
              options: [
                for (final sample in oneboxSamples)
                  DComboboxOption(
                    value: sample,
                    label: sample.name,
                    searchText: '${sample.name} ${sample.keywords}',
                  ),
              ],
              anchor: const DComboboxInput<OneboxSample>(
                placeholder: 'Search oneboxes…',
                semanticLabel: 'Search oneboxes',
              ),
              content: const DComboboxContent(
                children: [
                  DComboboxEmpty<OneboxSample>(
                    child: Text('No oneboxes found.'),
                  ),
                  DComboboxList<OneboxSample>(),
                ],
              ),
              onChanged: (sample, _) {
                if (sample == null || sample == _sample) return;
                setState(() {
                  _sample = sample;
                  _state = 0;
                });
              },
            ),
            DFieldDescription(child: Text(_sample.description)),
          ],
        ),
        const SizedBox(height: DSpacing.lg),
        DField(
          children: [
            const DFieldLabel(child: Text('Preview state')),
            Wrap(
              spacing: DSpacing.controlGap,
              runSpacing: DSpacing.sm,
              children: [
                for (var index = 0; index < _sample.states.length; index++)
                  DToggle(
                    key: ValueKey('onebox-state-${_sample.id}-$index'),
                    pressed: _state == index,
                    variant: DToggleVariant.outline,
                    onPressedChanged: (_) => setState(() => _state = index),
                    child: Text(_sample.states[index].label),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: DSpacing.lg),
        KeyedSubtree(
          key: ValueKey('onebox-preview-${_sample.id}-$_state'),
          child: _sample.states[_state].builder(context),
        ),
      ],
    ),
  );
}
