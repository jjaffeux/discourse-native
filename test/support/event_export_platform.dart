import 'dart:async';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

final class EventExportFileSelector extends FileSelectorPlatform {
  final filenames = <String?>[];
  final typeGroups = <List<XTypeGroup>?>[];
  Future<String?> Function() choosePath = () async => null;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    filenames.add(options.suggestedName);
    typeGroups.add(acceptedTypeGroups);
    final path = await choosePath();
    return path == null ? null : FileSaveLocation(path);
  }
}
