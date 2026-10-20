import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/assignment_list_virtualization_test.dart' as assignments;
import '../test/d_radio_group_navigation_test.dart' as radios;
import '../test/menu_list_virtualization_test.dart' as menus;
import '../test/ui/dropdown_list_virtualization_test.dart' as dropdowns;
import '../test/ui/option_list_virtualization_test.dart' as options;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  menus.menuListVirtualizationTests(platforms: const [TargetPlatform.iOS]);
  options.optionListVirtualizationTests();
  group('Native dropdown lists', dropdowns.dropdownListVirtualizationTests);
  radios.radioListNavigationTests();
  assignments.assignmentListVirtualizationTests();
}
