import 'package:integration_test/integration_test.dart';

import '../test/mobile_search_topic_geometry_test.dart' as regression;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  regression.main();
}
