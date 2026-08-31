import 'package:flutter/widgets.dart';

import 'gif.dart';

abstract interface class GifPickerSession {
  bool isAvailable(String siteUrl);

  Future<GifResult?> showPicker({
    required BuildContext context,
    required String siteUrl,
  });
}
