import 'examples/aspect_ratio_examples.dart';
import 'examples/avatar_examples.dart';
import 'examples/badge_examples.dart';
import 'examples/button_examples.dart';
import 'examples/card_examples.dart';
import 'examples/checkbox_examples.dart';
import 'examples/direction_examples.dart';
import 'examples/foundation_examples.dart';
import 'examples/input_examples.dart';
import 'examples/kbd_examples.dart';
import 'examples/label_examples.dart';
import 'examples/popover_examples.dart';
import 'examples/radio_group_examples.dart';
import 'examples/separator_examples.dart';
import 'examples/sidebar_examples.dart';
import 'examples/skeleton_examples.dart';
import 'examples/spinner_examples.dart';
import 'examples/tooltip_examples.dart';
import 'examples/typography_examples.dart';
import 'styleguide_example.dart';

/// Each component task replaces its baseline or adds its own example file.
final componentExamples = <String, ComponentExamples>{
  'input': inputExamples,
  'radio-group': radioGroupExamples,
  'checkbox': checkboxExamples,
  'card': cardExamples,
  'foundations': foundationExamples,
  'aspect-ratio': aspectRatioExamples,
  'avatar': avatarExamples,
  'badge': badgeExamples,
  'direction': directionExamples,
  'typography': typographyExamples,
  'separator': separatorExamples,
  'kbd': kbdExamples,
  'label': labelExamples,
  'popover': popoverExamples,
  'skeleton': skeletonExamples,
  'sidebar': sidebarExamples,
  'spinner': spinnerExamples,
  'button': buttonExamples,
  'tooltip': tooltipExamples,
  'select': baselineSelectExamples,
};
