import 'package:flutter_test/flutter_test.dart';

import '../packages/flutter_widget_from_html_core/test/default_styles_cache_test.dart'
    as cache;
import '../packages/flutter_widget_from_html_core/test/default_styles_rendering_test.dart'
    as rendering;

void main() {
  group('HTML default style cache', cache.main);
  group('HTML default style rendering', rendering.main);
}
