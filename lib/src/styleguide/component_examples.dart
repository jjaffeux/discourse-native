import 'examples/direction_examples.dart';
import 'examples/foundation_examples.dart';
import 'examples/separator_examples.dart';
import 'styleguide_example.dart';

/// Each component task replaces its baseline or adds its own example file.
final componentExamples = <String, ComponentExamples>{
  'foundations': foundationExamples,
  'direction': directionExamples,
  'separator': separatorExamples,
  'button': baselineButtonExamples,
  'tooltip': baselineTooltipExamples,
  'select': baselineSelectExamples,
};
