import 'examples/direction_examples.dart';
import 'examples/foundation_examples.dart';
import 'examples/kbd_examples.dart';
import 'examples/typography_examples.dart';
import 'styleguide_example.dart';

/// Each component task replaces its baseline or adds its own example file.
final componentExamples = <String, ComponentExamples>{
  'foundations': foundationExamples,
  'direction': directionExamples,
  'typography': typographyExamples,
  'kbd': kbdExamples,
  'button': baselineButtonExamples,
  'tooltip': baselineTooltipExamples,
  'select': baselineSelectExamples,
};
