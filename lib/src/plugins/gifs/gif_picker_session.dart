import 'package:flutter/widgets.dart';

import 'gif.dart';

/// The complete GIF-owned picker available to composer integrations.
///
/// Consumers only decide what to do with a selected [GifResult]. API access,
/// credentials, site lifecycle leases, and GIF-specific settings remain
/// private implementation details of the GIF module.
abstract interface class GifPickerSession {
  bool isAvailable(String siteUrl);

  Future<GifResult?> showPicker({
    required BuildContext context,
    required String siteUrl,
  });
}
