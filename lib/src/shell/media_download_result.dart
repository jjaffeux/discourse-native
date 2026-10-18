sealed class MediaDownloadResult {
  const MediaDownloadResult();
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

enum MediaShareOutcome { shared, cancelled }
