import 'package:integration_test/integration_test.dart';

import '../test/mobile_reaction_scroll_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  regression.mobileReactionScrollTests(native: true);
}
