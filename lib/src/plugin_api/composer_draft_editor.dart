import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextEditingController;

import '../models/composer_upload.dart';

abstract interface class ComposerDraftEditor implements Listenable {
  TextEditingController get text;
  String get raw;
  List<ComposerUploadResult> get completedUploads;
  bool get hasActiveUploads;

  void replacePluginDocument({
    required String raw,
    required Iterable<ComposerUploadResult> uploads,
  });
  void clearDocument();
  void dispose();
}
