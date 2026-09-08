import 'examples/aspect_ratio_examples.dart';
import 'examples/card_examples.dart';
import 'examples/direction_examples.dart';
import 'examples/foundation_examples.dart';
import 'examples/kbd_examples.dart';
import 'examples/label_examples.dart';
import 'examples/separator_examples.dart';
import 'examples/skeleton_examples.dart';
import 'examples/typography_examples.dart';
import 'styleguide_example.dart';

/// Each component task replaces its baseline or adds its own example file.
final componentExamples = <String, ComponentExamples>{
  'card': cardExamples,
  'foundations': foundationExamples,
  'aspect-ratio': aspectRatioExamples,
  'direction': directionExamples,
  'typography': typographyExamples,
  'separator': separatorExamples,
  'kbd': kbdExamples,
  'label': labelExamples,
  'skeleton': skeletonExamples,
  'button': baselineButtonExamples,
  'tooltip': baselineTooltipExamples,
  'select': baselineSelectExamples,
};
