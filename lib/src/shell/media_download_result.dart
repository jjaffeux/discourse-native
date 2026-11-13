import '../foundation/media_download_environment.dart';

sealed class MediaDownloadResult {
  const MediaDownloadResult();

  factory MediaDownloadResult.savedTo(String path, {required bool windows}) =>
      MediaDownloadSaved(Uri.file(path, windows: windows).pathSegments.last);

  factory MediaDownloadResult.fromShare(MediaShareOutcome outcome) =>
      switch (outcome) {
        MediaShareOutcome.shared => const MediaDownloadShared(),
        MediaShareOutcome.cancelled => const MediaDownloadCancelled(),
      };
}

final class MediaDownloadSaved extends MediaDownloadResult {
  const MediaDownloadSaved(this.filename);

  final String filename;
}

final class MediaDownloadShared extends MediaDownloadResult {
  const MediaDownloadShared();
}

final class MediaDownloadCancelled extends MediaDownloadResult {
  const MediaDownloadCancelled();
}
